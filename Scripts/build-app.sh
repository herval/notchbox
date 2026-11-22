#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
architecture="${3:-native}"
if [[ $# -gt 3 || ( "$configuration" != "release" && "$configuration" != "debug" ) || ( "$architecture" != "native" && "$architecture" != "universal" ) ]]; then
    echo "Usage: Scripts/build-app.sh [release|debug] [app-path] [native|universal]" >&2
    exit 1
fi
app_path="${2:-$PWD/build/Notchbox.app}"
build_args=(-c "$configuration" --product Notchbox --force-resolved-versions)
if [[ "$architecture" == "universal" ]]; then
    # Separate triples avoid a dependency on Xcode's SwiftPM build backend.
    # Keep the deployment target aligned with Package.swift and Info.plist.
    minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
    for arch in arm64 x86_64; do
        swift build "${build_args[@]}" --triple "$arch-apple-macosx$minimum_macos"
    done
else
    swift build "${build_args[@]}"
fi
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "$architecture" == "universal" ]]; then
    binaries=()
    for arch in arm64 x86_64; do
        bin_path="$(swift build "${build_args[@]}" --triple "$arch-apple-macosx$minimum_macos" --show-bin-path)"
        binaries+=("$bin_path/Notchbox")
    done
    lipo -create "${binaries[@]}" -output "$app_path/Contents/MacOS/Notchbox"
    lipo "$app_path/Contents/MacOS/Notchbox" -verify_arch arm64 x86_64
else
    bin_path="$(swift build "${build_args[@]}" --show-bin-path)"
    cp "$bin_path/Notchbox" "$app_path/Contents/MacOS/Notchbox"
fi
cp Resources/Info.plist "$app_path/Contents/Info.plist"
install -m 644 .build/checkouts/SwiftTerm/LICENSE "$app_path/Contents/Resources/SwiftTerm-LICENSE.txt"
swift Scripts/MakeIcon.swift "$PWD/build"
cp build/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
echo "Built $app_path"
echo "Launch with: open \"$app_path\""
