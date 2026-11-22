#!/bin/bash
# Build/sign on this Mac; publishing the release triggers the cask-only workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: Scripts/publish-release.sh vX.Y.Z" >&2
    exit 1
fi
tag="$1"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
[[ "$tag" == "v$version" ]] || { echo "Tag must match Info.plist version $version" >&2; exit 1; }
untracked="$(git ls-files --others --exclude-standard -- Package.swift Package.resolved Sources Resources Scripts packaging .github)"
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$untracked" ]]; then
    echo "Commit the release changes before publishing; the app must match its tag" >&2
    exit 1
fi
if git show-ref --verify --quiet "refs/tags/$tag"; then
    [[ "$(git rev-parse "$tag^{commit}")" == "$(git rev-parse HEAD)" ]] ||
        { echo "Existing tag $tag points at a different commit" >&2; exit 1; }
fi
repo=herval/notchbox
case "$(git config --get remote.origin.url)" in
    https://github.com/herval/notchbox|https://github.com/herval/notchbox.git|git@github.com:herval/notchbox.git|ssh://git@github.com/herval/notchbox.git) ;;
    *) echo "origin must point at herval/notchbox before publishing" >&2; exit 1 ;;
esac
Scripts/release-secrets.sh --check
if draft="$(gh release view "$tag" --repo "$repo" --json isDraft --jq .isDraft 2>/dev/null)"; then
    [[ "$draft" == true ]] || { echo "Refusing to replace published release $tag" >&2; exit 1; }
fi

swift test --force-resolved-versions
Scripts/package-release.sh "$tag"
Scripts/check-release.sh "$tag" build/release --notarized

# Create/push a tag only after the signed archive has passed validation.
if ! git show-ref --verify --quiet "refs/tags/$tag"; then git tag "$tag"; fi
git push origin "refs/tags/$tag"
if ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    gh release create "$tag" --repo "$repo" --verify-tag --draft --title "Notchbox $tag" \
        --notes 'Install with `brew install --cask herval/tap/notchbox`, or download the universal ZIP below and drag Notchbox.app to Applications. Requires macOS 14 or later. Quit Notchbox before upgrading; quitting ends its terminal sessions.'
fi
[[ "$(gh release view "$tag" --repo "$repo" --json isDraft --jq .isDraft)" == true ]] ||
    { echo "Refusing to overwrite a release published while this build was running" >&2; exit 1; }
archive="build/release/notchbox_${version}_universal.zip"
gh release upload "$tag" "$archive" "$archive.sha256" --repo "$repo" --clobber
gh release edit "$tag" --repo "$repo" --draft=false --latest
gh release view "$tag" --repo "$repo" --json url --jq .url
echo "Published. The Homebrew workflow will update herval/tap/notchbox."
