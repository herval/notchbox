#!/bin/bash
# Round-trip the ZIP to check what a user / Homebrew will actually install.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -lt 2 || $# -gt 3 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || ( $# -eq 3 && "$3" != --notarized ) ]]; then
    echo "Usage: Scripts/check-release.sh vX.Y.Z directory-containing-release [--notarized]" >&2
    exit 1
fi
tag="$1"
directory="$(cd "$2" && pwd)"
archive="notchbox_${tag#v}_universal.zip"
(cd "$directory" && shasum -a 256 -c "$archive.sha256")
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto -x -k "$directory/$archive" "$staging"
app="$staging/Notchbox.app"
plist="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "${tag#v}" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == dev.littleguys.notchbox ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" == 14.0 ]]
test -s "$app/Contents/Resources/AppIcon.icns"
test -s "$app/Contents/Resources/SwiftTerm-LICENSE.txt"
test -x "$app/Contents/MacOS/Notchbox"
lipo "$app/Contents/MacOS/Notchbox" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$app"
if [[ "${3:-}" == --notarized ]]; then
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi
Scripts/render-cask.sh "$tag" "$directory/$archive" > "$staging/notchbox.rb"
ruby -c "$staging/notchbox.rb"
echo "Release archive and cask checked: $archive"
