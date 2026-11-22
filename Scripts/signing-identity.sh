#!/bin/bash
# Print one existing Developer ID identity; this never exports a key.
set -euo pipefail
identities="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p')"
if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
    if ! /usr/bin/grep -Fxq "$APPLE_SIGNING_IDENTITY" <<< "$identities"; then
        echo "APPLE_SIGNING_IDENTITY is not a valid Developer ID identity in this Mac's Keychain" >&2
        exit 1
    fi
    printf '%s\n' "$APPLE_SIGNING_IDENTITY"
elif [[ "$(printf '%s\n' "$identities" | sed '/^$/d' | wc -l)" -eq 1 ]]; then
    printf '%s\n' "$identities"
else
    echo "Expected one Developer ID Application identity in Keychain. If there are several, set APPLE_SIGNING_IDENTITY to its full name." >&2
    exit 1
fi
