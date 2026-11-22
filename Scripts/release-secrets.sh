#!/bin/bash
# Configure local Keychain notarization and the tap's single GitHub secret.
# The Developer ID private key stays in this Mac's Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=herval/notchbox
tap=herval/homebrew-tap
profile="${NOTARYTOOL_PROFILE:-notchbox}"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
    echo "Usage: Scripts/release-secrets.sh [--check]" >&2
    exit 1
fi
identity="$(Scripts/signing-identity.sh)"
[[ "$identity" =~ \(([A-Z0-9]{10})\)$ ]] || { echo "Cannot determine the Developer ID team" >&2; exit 1; }
team="${BASH_REMATCH[1]}"
command -v gh >/dev/null
existing="$(gh secret list --repo "$repo" --json name --jq '.[].name')"
has_tap_key() { /usr/bin/grep -qx HOMEBREW_TAP_DEPLOY_KEY <<< "$existing"; }
if [[ "${1:-}" == "--check" ]]; then
    xcrun notarytool history --keychain-profile "$profile" >/dev/null ||
        { echo "Configure Keychain profile '$profile' with Scripts/release-secrets.sh" >&2; exit 1; }
    has_tap_key || { echo "Missing GitHub secret HOMEBREW_TAP_DEPLOY_KEY" >&2; exit 1; }
    echo "Ready: $identity; Keychain notarization profile '$profile'; tap secret present."
    exit 0
fi

if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    [[ -t 0 ]] || { echo "Run Scripts/release-secrets.sh in a terminal to enter notarization credentials privately" >&2; exit 1; }
    apple_id="${APPLE_ID:-}"
    if [[ -z "$apple_id" ]]; then IFS= read -r -p "Apple Account email for notarization: " apple_id; fi
    [[ -n "$apple_id" ]] || { echo "An Apple Account email is required" >&2; exit 1; }
    # notarytool prompts securely for the app-specific password and validates it.
    xcrun notarytool store-credentials "$profile" --apple-id "$apple_id" --team-id "$team"
fi

if ! has_tap_key; then
    umask 077
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    ssh-keygen -q -t ed25519 -N '' -C 'notchbox release workflow' -f "$work/tap"
    key_id="$(gh api "repos/$tap/keys" --method POST -f title='notchbox release workflow' \
        -f key="$(cat "$work/tap.pub")" -F read_only=false --jq .id)"
    if ! gh secret set HOMEBREW_TAP_DEPLOY_KEY --repo "$repo" < "$work/tap"; then
        gh api "repos/$tap/keys/$key_id" --method DELETE
        exit 1
    fi
fi
echo "Ready: signing and notarization use this Mac's Keychain; the tap secret is configured."
