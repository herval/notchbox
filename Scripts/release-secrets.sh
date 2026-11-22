#!/bin/bash
# One-time GitHub setup. Complete credential groups are left alone. If a signing
# group is incomplete, all four values are set from the same .p12 so they match.
# Needs gh authenticated with admin access to both repos; never prints secrets.
set -euo pipefail
repo=herval/notchbox
tap=herval/homebrew-tap

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
    echo "Usage: [P12=/path/to/developer-id.p12] Scripts/release-secrets.sh [--check]" >&2
    exit 1
fi
command -v gh >/dev/null
existing="$(gh secret list --repo "$repo" --json name --jq '.[].name')"
has() { /usr/bin/grep -qx "$1" <<< "$existing"; }
needed=(APPLE_CERTIFICATE APPLE_CERTIFICATE_PASSWORD APPLE_SIGNING_IDENTITY APPLE_TEAM_ID APPLE_ID APPLE_PASSWORD HOMEBREW_TAP_DEPLOY_KEY)
if [[ "${1:-}" == "--check" ]]; then
    missing=()
    for name in "${needed[@]}"; do has "$name" || missing+=("$name"); done
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf 'Missing GitHub secret: %s\n' "${missing[@]}" >&2
        exit 1
    fi
    echo "All release secret names are present on $repo (values have not been validated)."
    exit 0
fi

umask 077
work="$(mktemp -d)"
cleanup() {
    if [[ -f "$work/check.keychain-db" ]]; then
        security delete-keychain "$work/check.keychain-db" >/dev/null 2>&1 || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT
put() { gh secret set "$1" --repo "$repo"; }
prompt() {
    [[ -t 0 ]] || { echo "Set $1 before running, or run interactively." >&2; exit 1; }
    IFS= read -r -p "$2: " "$1"
}
prompt_secret() {
    [[ -t 0 ]] || { echo "Set $1 before running, or run interactively." >&2; exit 1; }
    IFS= read -r -s -p "$2: " "$1"
    echo
}

if ! has APPLE_CERTIFICATE || ! has APPLE_CERTIFICATE_PASSWORD || ! has APPLE_SIGNING_IDENTITY || ! has APPLE_TEAM_ID; then
    [[ -n "${P12:-}" ]] || prompt P12 "Path to an exported Developer ID Application certificate (.p12), as used by littleguys"
    [[ -f "$P12" ]] || { echo "No .p12 file at $P12" >&2; exit 1; }
    [[ -n "${P12_PASSWORD:-}" ]] || prompt_secret P12_PASSWORD "Password for the .p12"
    export P12_PASSWORD
    /usr/bin/openssl pkcs12 -in "$P12" -passin env:P12_PASSWORD -clcerts -nokeys -out "$work/cert.pem"
    /usr/bin/openssl x509 -in "$work/cert.pem" -checkend 0 -noout
    subject="$(/usr/bin/openssl x509 -in "$work/cert.pem" -noout -subject -nameopt multiline)"
    identity="$(sed -n 's/^ *commonName *= //p' <<< "$subject")"
    team="$(sed -n 's/^ *organizationalUnitName *= //p' <<< "$subject")"
    [[ "$identity" == "Developer ID Application: "* && "$team" =~ ^[A-Z0-9]{10}$ ]] ||
        { echo "Expected a valid Developer ID Application certificate with a team ID" >&2; exit 1; }
    # Confirm that the .p12 also carries the matching private key, before storing it.
    security create-keychain -p setup "$work/check.keychain-db"
    if ! security import "$P12" -k "$work/check.keychain-db" -P "$P12_PASSWORD" >/dev/null ||
       ! security find-identity -v -p codesigning "$work/check.keychain-db" | /usr/bin/grep -qF "\"$identity\""; then
        security delete-keychain "$work/check.keychain-db"
        echo "The .p12 must contain the certificate and its private key" >&2
        exit 1
    fi
    security delete-keychain "$work/check.keychain-db"
    base64 -i "$P12" | tr -d '\n' | put APPLE_CERTIFICATE
    printf '%s' "$P12_PASSWORD" | put APPLE_CERTIFICATE_PASSWORD
    printf '%s' "$identity" | put APPLE_SIGNING_IDENTITY
    printf '%s' "$team" | put APPLE_TEAM_ID
    APPLE_TEAM_ID="$team"
fi

if ! has APPLE_ID || ! has APPLE_PASSWORD; then
    [[ -n "${APPLE_ID:-}" ]] || prompt APPLE_ID "Apple Account email for notarization"
    [[ -n "${APPLE_PASSWORD:-}" ]] || prompt_secret APPLE_PASSWORD "Apple app-specific password (account.apple.com)"
    [[ -n "${APPLE_TEAM_ID:-}" ]] || prompt APPLE_TEAM_ID "Apple Developer team ID"
    xcrun notarytool history --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" >/dev/null
    printf '%s' "$APPLE_ID" | put APPLE_ID
    printf '%s' "$APPLE_PASSWORD" | put APPLE_PASSWORD
fi

if ! has HOMEBREW_TAP_DEPLOY_KEY; then
    ssh-keygen -q -t ed25519 -N '' -C 'notchbox release workflow' -f "$work/tap"
    key_id="$(gh api "repos/$tap/keys" --method POST -f title='notchbox release workflow' \
        -f key="$(cat "$work/tap.pub")" -F read_only=false --jq .id)"
    if ! put HOMEBREW_TAP_DEPLOY_KEY < "$work/tap"; then
        gh api "repos/$tap/keys/$key_id" --method DELETE
        exit 1
    fi
fi
echo "Release secrets configured on $repo."
