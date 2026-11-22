#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: Scripts/render-cask.sh vX.Y.Z /path/to/notchbox_X.Y.Z_universal.zip" >&2
    exit 1
fi
version="${1#v}"
archive="$2"
if [[ ! -f "$archive" || "$(basename "$archive")" != "notchbox_${version}_universal.zip" ]]; then
    echo "Expected an existing notchbox_${version}_universal.zip archive" >&2
    exit 1
fi
sha="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
sed -E \
    -e "s/^  version \".*\"/  version \"$version\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" \
    -e '/^# /d' \
    packaging/homebrew/notchbox.rb
