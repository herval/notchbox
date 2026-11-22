#!/bin/bash
# Sign with this Mac's Keychain identity and notarize with a Keychain profile.
# --unsigned is for packaging checks; its output goes in a separate directory.
set -euo pipefail
cd "$(dirname "$0")/.."

unsigned=false
if [[ "${1:-}" == "--unsigned" ]]; then
    unsigned=true
    shift
fi
if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: Scripts/package-release.sh [--unsigned] vX.Y.Z" >&2
    exit 1
fi
tag="$1"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ "$tag" != "v$version" ]]; then
    echo "Tag $tag must match CFBundleShortVersionString ($version) in Resources/Info.plist" >&2
    exit 1
fi

notary_args=()
if [[ "$unsigned" == false ]]; then
    signing_identity="$(Scripts/signing-identity.sh)"
    profile="${NOTARYTOOL_PROFILE:-notchbox}"
    notary_args=(--keychain-profile "$profile")
    if ! xcrun notarytool history "${notary_args[@]}" >/dev/null; then
        echo "Configure the '$profile' Keychain profile with Scripts/release-secrets.sh first" >&2
        exit 1
    fi
fi

output="$PWD/build/release"
if [[ "$unsigned" == true ]]; then output="$PWD/build/release-unsigned"; fi
mkdir -p "$output"
staging="$(mktemp -d "$output/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Notchbox.app"
Scripts/build-app.sh release "$app" universal

if [[ "$unsigned" == false ]]; then
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app"
    codesign --verify --deep --strict --verbose=2 "$app"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/submission.zip"
    notary_exit=0
    xcrun notarytool submit "$staging/submission.zip" "${notary_args[@]}" --wait \
        --output-format json > "$output/notarization.json" || notary_exit=$?
    submission_id="$(plutil -extract id raw -o - "$output/notarization.json" 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
        xcrun notarytool log "$submission_id" "${notary_args[@]}" "$output/notarization-log.json"
    fi
    status="$(plutil -extract status raw -o - "$output/notarization.json" 2>/dev/null || true)"
    if [[ $notary_exit -ne 0 || "$status" != "Accepted" ]]; then
        echo "Notarization failed; see the notarization reports in $output" >&2
        exit 1
    fi
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
fi

# ZIP files cannot carry a stapled ticket themselves: archive the stapled app.
archive="notchbox_${version}_universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$staging/$archive"
mv -f "$staging/$archive" "$output/$archive"
(cd "$output" && shasum -a 256 "$archive" > "$archive.sha256")
if [[ "$unsigned" == true ]]; then
    echo "UNSIGNED TEST PACKAGE: do not publish or install this through the tap."
fi
echo "Packaged $output/$archive"
