#!/bin/bash
# A normal run requires Developer ID + notarization credentials. --unsigned is
# for packaging checks only; its output goes in a separate directory.
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
    if [[ "${APPLE_SIGNING_IDENTITY:-}" != "Developer ID Application: "* ]]; then
        echo "Set APPLE_SIGNING_IDENTITY to a Developer ID Application identity (see docs/releasing.md)" >&2
        exit 1
    fi
    if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
        notary_args=(--keychain-profile "$NOTARYTOOL_PROFILE")
    else
        for name in APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID; do
            if [[ -z "${!name:-}" ]]; then
                echo "Set $name or use NOTARYTOOL_PROFILE (see docs/releasing.md)" >&2
                exit 1
            fi
        done
        notary_args=(--apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID")
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
    codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$app"
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
