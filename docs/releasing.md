# Publishing Notchbox with Homebrew

The install target is `brew install --cask herval/tap/notchbox`. It becomes available
after the first release workflow finishes. The cask lives in
[`herval/homebrew-tap`](https://github.com/herval/homebrew-tap), alongside littleguys;
`packaging/homebrew/notchbox.rb` here is its template, not an installable cask.

## One-time credentials

Run from a Mac with Xcode 26 / Swift 6.2 or later and `gh` authenticated with admin
access to both `herval/notchbox` and `herval/homebrew-tap`:

```sh
P12=/path/to/developer-id.p12 Scripts/release-secrets.sh
Scripts/release-secrets.sh --check
```

Reuse the **Developer ID Application** certificate and Apple notarization account
used by littleguys. Export the certificate **and private key** as a password-protected
`.p12` from Keychain Access if needed. GitHub cannot reveal or copy the existing
repository secrets back out; they must be supplied again for Notchbox. The script
prompts for the `.p12` password and an Apple app-specific password, checks them,
and sends values to GitHub over stdin without printing them. It keeps complete
credential groups and creates a separate write deploy key for Notchbox, preserving
littleguys' key. Its temporary files are removed on exit. `--check` only checks names.

These seven Actions secrets are required on `herval/notchbox`:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE` | Base64-encoded Developer ID Application `.p12`, including its private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_SIGNING_IDENTITY` | Full `Developer ID Application: … (TEAMID)` identity |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team ID |
| `APPLE_ID` | Apple Account email for notarization |
| `APPLE_PASSWORD` | App-specific password for that Apple Account |
| `HOMEBREW_TAP_DEPLOY_KEY` | Private SSH key whose public key has write access to the tap |

`GITHUB_TOKEN` is provided by Actions. No Tauri updater credentials are needed.
For credential rotation, replace the matching Apple secret group together in
GitHub settings. A new tap key should replace only Notchbox's deploy key.

## Cut a release

1. Update `CFBundleShortVersionString` in `Resources/Info.plist` to `X.Y.Z` and
   increment `CFBundleVersion`. Keep the minimum OS in that plist, `Package.swift`,
   and the cask in sync if it changes.
2. Run `swift test` and the packaging check below. Commit the release changes.
3. Push the commit and matching version tag:

   ```sh
   git push origin main
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

`.github/workflows/release.yml` rejects mismatched / prerelease tags or missing
secrets before compiling. It tests the package, builds Apple silicon and Intel
executables for macOS 14+, combines them into a universal app, signs with Developer
ID and hardened runtime, notarizes it, staples the ticket, and verifies Gatekeeper.
It re-extracts the final ZIP and checks its bundle metadata, architecture slices,
signature, icon, and SwiftTerm license.

The workflow uploads `notchbox_X.Y.Z_universal.zip` and its `.sha256` file into a
draft GitHub Release, then publishes it. Only then does the Homebrew job download
the published ZIP, compute its SHA-256, render `Casks/notchbox.rb`, and push it to
the tap. It rebases before pushing to accommodate releases from other apps.
It never replaces assets in an already-published release.

If signing or notarization fails, no release is published. If updating the tap
fails after publication, use **Re-run failed jobs** in Actions; this retries just
the cask update, using the published archive. Do not move a published version tag.

After the first release, check on a Mac:

```sh
brew install --cask herval/tap/notchbox
open -a Notchbox
# For later releases, quit Notchbox first, then:
brew update
brew upgrade --cask herval/tap/notchbox
```

Quitting or upgrading ends terminal sessions. Notchbox does not update itself;
Homebrew handles upgrades. Uninstall quits the app; `brew uninstall --zap` also
removes its preferences and saved application state.

## Test packaging without credentials

```sh
swift test
Scripts/package-release.sh --unsigned v0.1.5 # use the current Info.plist version
Scripts/check-release.sh v0.1.5 build/release-unsigned
Scripts/render-cask.sh v0.1.5 build/release-unsigned/notchbox_0.1.5_universal.zip
```

This creates an ad-hoc-signed universal app in a ZIP under `build/release-unsigned/`.
It verifies packaging, not notarization or Gatekeeper acceptance. Never publish
this archive or its rendered cask. The macOS checks workflow runs the same round
trip for pushes and pull requests without access to secrets. GUI integration
checks still run separately via `Scripts/test-app.sh` in a logged-in Mac session.

For a local **signed** package, install your Developer ID identity in the keychain,
set `APPLE_SIGNING_IDENTITY`, and either set `APPLE_ID`, `APPLE_PASSWORD`, and
`APPLE_TEAM_ID`, or set `NOTARYTOOL_PROFILE` to a stored `notarytool` credential
profile. Run `Scripts/package-release.sh vX.Y.Z`; the result and notarization
reports are under `build/release/`. Run
`Scripts/check-release.sh vX.Y.Z build/release --notarized` to verify the archive
including its stapled ticket and Gatekeeper acceptance after extraction.

The ZIP / cask arrangement follows the [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).
The signing and ticket steps follow [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
