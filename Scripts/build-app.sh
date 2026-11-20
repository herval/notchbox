#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    echo "Usage: Scripts/build-app.sh [release|debug] [app-path]" >&2
    exit 1
fi
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app_path="${2:-$PWD/build/Notchbox.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Notchbox" "$app_path/Contents/MacOS/Notchbox"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
install -m 644 .build/checkouts/SwiftTerm/LICENSE "$app_path/Contents/Resources/SwiftTerm-LICENSE.txt"
swift Scripts/MakeIcon.swift "$PWD/build"
cp build/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_path"
echo "Built $app_path"
echo "Launch with: open \"$app_path\""
