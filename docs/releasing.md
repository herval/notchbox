# Publishing Notchbox with Homebrew

Releases are built, signed, and notarized on the Mac containing your Developer ID
identity. The private key stays in Keychain. Publishing the signed release triggers
GitHub Actions to update `notchbox` in
[`herval/homebrew-tap`](https://github.com/herval/homebrew-tap).
The install target is `brew install --cask herval/tap/notchbox`.

## One-time Keychain setup

On the signing Mac, with Xcode 26 / Swift 6.2 or later and `gh` authenticated:

```sh
Scripts/release-secrets.sh
Scripts/release-secrets.sh --check
```

The setup script uses the existing **Developer ID Application** identity in
Keychain. It asks for your Apple Account email, then `notarytool` securely prompts
for an **app-specific password** and validates it with Apple before storing a
Keychain profile named `notchbox`. Use the Apple Developer account for the team on
the signing certificate. Create an app-specific password at
[Apple Account](https://account.apple.com) if needed.

No certificate export is involved. The only GitHub Actions secret is
`HOMEBREW_TAP_DEPLOY_KEY`, a dedicated write key for the shared tap, which is already
configured for Notchbox. The script keeps an existing tap secret; if absent, it
creates a separate key without changing littleguys' key. Creating a key requires
`gh` admin access to both repositories.

`--check` validates the local signing identity and notarization login and confirms
that the tap secret exists. If macOS asks to authorize `codesign`, approve the
operation locally using your Mac login password.

With several Developer ID identities, select the full name using
`APPLE_SIGNING_IDENTITY`. To reuse another local notarization profile, set
`NOTARYTOOL_PROFILE`; its default is `notchbox`. Both variables may also be passed
to the packaging and publishing commands. Apple signing/notarization credentials
are used locally and are not GitHub secrets.

## Cut a release

1. Update `CFBundleShortVersionString` in `Resources/Info.plist` to `X.Y.Z` and
   increment `CFBundleVersion`. Keep its minimum OS, `Package.swift`, and the cask
   aligned if the minimum OS changes.
2. Commit the release changes and push `main`, including the Homebrew workflow.
3. On the signing Mac, run:

   ```sh
   Scripts/publish-release.sh vX.Y.Z
   ```

The publisher requires clean tracked files and no untracked build inputs. It
rejects a mismatched version, a tag pointing at another commit, or a version
already published. It checks the Keychain setup and tap secret, runs the unit
tests, builds Apple silicon and Intel executables for macOS 14+, and combines them
into a universal app. It signs directly with Keychain using hardened runtime and
a secure timestamp, notarizes the app, staples the ticket, and verifies Gatekeeper.
It then re-extracts the final ZIP and checks its metadata, both architecture slices,
signature, ticket, icon, and SwiftTerm license.

Only after validation does it create/push the tag and upload
`notchbox_X.Y.Z_universal.zip` and its `.sha256` file to a draft GitHub Release.
It then publishes the release as latest. Run the publisher from a checkout whose
`origin` is `herval/notchbox`, with `gh` authenticated to publish there.
Each release runs on the signing Mac; a tag push alone does not publish a binary.

The `Publish Homebrew cask` workflow runs when the release is published. It checks
that this is the latest stable release, downloads and verifies the ZIP/checksum,
renders `Casks/notchbox.rb` from `packaging/homebrew/notchbox.rb`, then pushes it to
the shared tap. It rebases before pushing to accommodate other apps' releases.

## Recovery

If signing or notarization fails, no public release is created. Notarization
reports are under `build/release/`. If uploading fails, the draft can be retried
with the same version from the same commit. Published assets are never overwritten;
fix a published build with the next patch version rather than moving its tag.

If the tap update fails after publication, use **Re-run failed jobs** in Actions,
or run the `Publish Homebrew cask` workflow manually with that release's tag.
The workflow refuses to replace the latest cask with an older release.

## Install and update

After the first release:

```sh
brew install --cask herval/tap/notchbox
open -a Notchbox
# For later releases, quit Notchbox first, then:
brew update
brew upgrade --cask herval/tap/notchbox
```

Quitting or upgrading ends terminal sessions. Homebrew handles upgrades.
Uninstall quits the app; `brew uninstall --zap` also removes its preferences and
saved application state.

## Test packaging

Without signing/notarization credentials:

```sh
swift test
Scripts/package-release.sh --unsigned v0.1.5 # use the current Info.plist version
Scripts/check-release.sh v0.1.5 build/release-unsigned
```

This makes an ad-hoc-signed universal test ZIP under `build/release-unsigned/`.
Do not publish this ZIP or its cask. The macOS checks workflow runs this round trip
for pushes and pull requests without access to signing secrets.
GUI integration checks run separately with `Scripts/test-app.sh` in a logged-in
Mac session.

To make a signed/notarized package locally for review, without publishing:

```sh
Scripts/package-release.sh vX.Y.Z
Scripts/check-release.sh vX.Y.Z build/release --notarized
```

The ZIP / cask arrangement follows the [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).
The signing and Keychain profile steps follow [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
