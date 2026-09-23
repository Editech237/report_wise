import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from backup import collect, verify_tar, Storage


class FakeStorage:
    def json(self, route):
        return [{'id': 'student-imports', 'public': False}]

    def objects(self, bucket):
        # Adversarial names must never become filesystem paths.
        yield '../../outside.pdf', {'id': '1'}
        yield 'school/register.pdf', {'id': '2'}

    def request(self, route):
        return io.BytesIO(b'fake PDF bytes')


class BackupTest(unittest.TestCase):
    def test_collection_and_integrity(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            content = root / 'content'
            content.mkdir()
            (content / 'database.dump').write_bytes(b'database fixture')
            manifest = collect(FakeStorage(), content)
            self.assertEqual(len(manifest['objects']), 2)
            self.assertFalse((root / 'outside.pdf').exists())
            archive = root / 'backup.tar'
            def pack():
                with tarfile.open(archive, 'w') as tar:
                    for path in content.rglob('*'):
                        if path.is_file():
                            tar.add(path, arcname=path.relative_to(content).as_posix())
            pack()
            self.assertEqual(verify_tar(archive)['version'], 1)
            (content / 'database.dump').write_bytes(b'corrupted')
            pack()
            with self.assertRaises(ValueError):
                verify_tar(archive)

    def test_rejects_links(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / 'unsafe.tar'
            with tarfile.open(archive, 'w') as tar:
                link = tarfile.TarInfo('link')
                link.type = tarfile.SYMTYPE
                link.linkname = '/etc/passwd'
                tar.addfile(link)
            with self.assertRaises(ValueError):
                verify_tar(archive)

    def test_requires_https(self):
        with self.assertRaises(ValueError):
            Storage('http://example.invalid', 'secret')


if __name__ == '__main__':
    unittest.main()
