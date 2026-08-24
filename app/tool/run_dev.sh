#!/usr/bin/env bash
# Runs the app with your local .env baked in as dart-defines.
# Usage: ./tool/run_dev.sh [platform]   e.g. ./tool/run_dev.sh macos | windows | linux
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Missing .env  ->  cp .env.example .env  and fill in your Supabase keys." >&2
  exit 1
fi

platform="${1:-macos}"
if [[ "$platform" == "windows" ]]; then
  dart_defines=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    dart_defines+=("--dart-define=$line")
  done < .env
  flutter run -d windows "${dart_defines[@]}"
else
  flutter run -d "$platform" --dart-define-from-file=.env
fi