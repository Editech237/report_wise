#!/usr/bin/env python3
"""Operator-only encrypted DB + Storage backup. No credentials belong in Flutter.

Requires pg_dump, age, Python 3.10+, a read-capable DB connection and Supabase
service key. Writes must be paused for a consistent database/storage pair.
This creates a local archive; copying it off-site is a separate required step.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
from datetime import datetime, timezone
from urllib.parse import quote, urlparse
from urllib.request import Request, build_opener, HTTPRedirectHandler


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('Storage redirected; refusing to forward credentials')


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


class Storage:
    def __init__(self, url, key):
        parsed = urlparse(url)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username:
            raise ValueError('SUPABASE_URL must be an HTTPS project URL')
        self.url = url.rstrip('/') + '/storage/v1'
        self.key = key
        self.opener = build_opener(NoRedirect())

    def request(self, route, payload=None):
        headers = {'Authorization': 'Bearer ' + self.key, 'apikey': self.key}
        body = None
        if payload is not None:
            headers['Content-Type'] = 'application/json'
            body = json.dumps(payload).encode()
        return self.opener.open(Request(self.url + route, data=body, headers=headers), timeout=60)

    def json(self, route, payload=None):
        with self.request(route, payload) as response:
            return json.load(response)

    def objects(self, bucket, prefix=''):
        offset = 0
        while True:
            rows = self.json('/object/list/' + quote(bucket, safe=''), {
                'prefix': prefix, 'limit': 100, 'offset': offset,
                'sortBy': {'column': 'name', 'order': 'asc'}})
            if not isinstance(rows, list):
                raise ValueError('Invalid Storage listing')
            for row in rows:
                name = (prefix + '/' if prefix else '') + row['name']
                if row.get('id') is None:
                    yield from self.objects(bucket, name)
                else:
                    yield name, row
            if len(rows) < 100:
                break
            offset += len(rows)


def collect(storage, folder):
    buckets = storage.json('/bucket')
    manifest = {'version': 1, 'created_at': datetime.now(timezone.utc).isoformat(),
                'buckets': buckets, 'objects': [], 'files': {}}
    objects_dir = folder / 'objects'
    objects_dir.mkdir(mode=0o700)
    for bucket in buckets:
        bucket_id = bucket['id']
        for name, metadata in storage.objects(bucket_id):
            # Never use remote object names as local filesystem paths.
            filename = 'objects/' + hashlib.sha256(json.dumps([bucket_id, name]).encode()).hexdigest()
            path = folder / filename
            with storage.request('/object/' + quote(bucket_id, safe='') + '/' + quote(name, safe='/')) as response, path.open('xb') as output:
                shutil.copyfileobj(response, output)
            manifest['objects'].append({'bucket': bucket_id, 'name': name,
                                        'file': filename, 'metadata': metadata})
            manifest['files'][filename] = {'sha256': digest(path), 'bytes': path.stat().st_size}
    database = folder / 'database.dump'
    manifest['files']['database.dump'] = {'sha256': digest(database), 'bytes': database.stat().st_size}
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    return manifest


def verify_tar(path):
    """Verify without extracting untrusted archive paths or links."""
    with tarfile.open(path) as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if len(names) != len(set(names)) or any(not m.isfile() for m in members):
            raise ValueError('Unexpected links, directories or duplicate entries')
        manifest = json.load(archive.extractfile('manifest.json'))
        if manifest.get('version') != 1:
            raise ValueError('Unsupported manifest')
        expected = manifest['files']
        if 'database.dump' not in expected or set(names) != set(expected) | {'manifest.json'}:
            raise ValueError('Archive files do not match manifest')
        for name, entry in expected.items():
            if name.startswith('/') or '..' in name.split('/'):
                raise ValueError('Unsafe archive path')
            value, size = hashlib.sha256(), 0
            with archive.extractfile(name) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    value.update(chunk)
                    size += len(chunk)
            if value.hexdigest() != entry['sha256'] or size != entry['bytes']:
                raise ValueError('Archive integrity check failed')
        return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    backup = commands.add_parser('create')
    backup.add_argument('--output', type=Path, required=True)
    backup.add_argument('--recipient', required=True, help='age public recipient, not a private key')
    backup.add_argument('--writes-paused', action='store_true', required=True)
    verify = commands.add_parser('verify')
    verify.add_argument('--archive', type=Path, required=True)
    verify.add_argument('--identity', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    if not shutil.which('age'):
        parser.error('Install age first')
    with tempfile.TemporaryDirectory(prefix='reportwise-backup-') as temp:
        folder = Path(temp)
        tar_path = folder / 'bundle.tar'
        if args.command == 'verify':
            subprocess.run(['age', '--decrypt', '-i', str(args.identity), '-o', str(tar_path), str(args.archive)], check=True)
            manifest = verify_tar(tar_path)
            print(f"Integrity verified: {len(manifest['objects'])} objects. A database restore drill is still required.")
            return
        if not shutil.which('pg_dump'):
            parser.error('Install PostgreSQL client tools matching the database major version')
        # DB credentials use libpq PGHOST/PGPORT/PGDATABASE/PGUSER and PGPASSFILE.
        # Never put a DB URL/password in command arguments or captured logs.
        for name in ('PGHOST', 'PGDATABASE', 'PGUSER', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'):
            if not os.environ.get(name):
                parser.error('Missing environment setting: ' + name)
        content = folder / 'content'
        content.mkdir(mode=0o700)
        subprocess.run(['pg_dump', '--format=custom', '--no-password', '--file', str(content / 'database.dump')], check=True)
        manifest = collect(Storage(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SERVICE_ROLE_KEY']), content)
        with tarfile.open(tar_path, 'w') as archive:
            for path in sorted(content.rglob('*')):
                if path.is_file():
                    archive.add(path, arcname=path.relative_to(content).as_posix(), recursive=False)
        verify_tar(tar_path)
        # Exclusive creation prevents overwriting an existing backup.
        with args.output.open('xb') as output:
            try:
                subprocess.run(['age', '--encrypt', '-r', args.recipient, str(tar_path)], stdout=output, check=True)
            except BaseException:
                output.close()
                args.output.unlink(missing_ok=True)  # Only this invocation's incomplete output.
                raise
        print(f"Encrypted local backup created ({len(manifest['objects'])} objects). Copy off-site and test restoration.")


if __name__ == '__main__':
    main()
