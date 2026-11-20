# Notchbox

A little terminal, tucked into your Mac's notch. Hover to open, run a command, get back to work.

Native AppKit + SwiftTerm. Independent terminal tabs. Your usual login shell and tools. Terminal sessions keep running when the panel is hidden.

## Build and run

Requires macOS 14+ and Xcode 26 with Swift 6.2 or later.

```sh
Scripts/build-app.sh
open build/Notchbox.app
```

The script creates a locally ad-hoc-signed app at `build/Notchbox.app`. Drag it into Applications if desired. It is a menu-bar app, so there is no Dock icon. The release build is for the Mac running the script. A public distribution still needs a Developer ID signature and notarization.

For a faster development build, use `Scripts/build-app.sh debug`. To build an update without replacing a running app, pass a separate output path: `Scripts/build-app.sh release "$PWD/build/Notchbox-0.1.4.app"`. Quit the current app before opening the update; its terminal sessions end on Quit. You can also open `Package.swift` in Xcode and run the Notchbox executable scheme. `--background` launches without opening the panel.

## Use

Hover the notch to reveal the panel and start typing immediately. On a display without a notch, hover the small Notchbox handle at the top center. The terminal takes keyboard focus as it opens. Moving the pointer away from the notch and panel starts the upward close animation immediately, even while it has keyboard focus or is still opening. Hovering back over the notch can reverse the closing slide. A keyboard reveal with the pointer elsewhere stays open until the pointer first enters and leaves the panel. Hiding it returns focus to the previously active app if that app is still running. Clicking another app dismisses the terminal and keeps that newly chosen app focused. You can also use the hide button or keyboard shortcut. Pin it to keep it visible when moving away or working in another app. Tabs and controls share a single row. The terminal slides down from the notch and retracts upward when dismissed; Reduce Motion skips the animation.

| Shortcut | Action |
| --- | --- |
| Control + backtick | Show/focus/hide the terminal from any app |
| Command + T / W | New / close tab |
| Command + 1–8 / 9 | Select tab / last tab |
| Control + Tab / Control + Shift + Tab | Next / previous tab |
| Command + Shift + [ / ] | Previous / next tab |
| Command + Escape | Hide the panel |
| Command + C / V | Copy / paste |
| Command + + / − / 0 | Increase / decrease / reset text size |

Escape and Control + C reach your terminal programs normally. New tabs inherit the current directory of the selected shell. A finished shell keeps its output and offers **Restart shell**. Closing a tab with a foreground command asks first. Closing the last tab hides the panel; opening it again starts a fresh shell.

The menu-bar terminal icon provides show/hide, new tab, pin, three panel sizes, and Quit. Panel and text size are saved. Sessions survive panel dismissal, and end when you quit the app. The app does not restore shell processes after relaunch.

## Verification

```sh
swift test
Scripts/test-app.sh
# Optional: run the same integration checks against a release build.
Scripts/test-app.sh release
```

Run the integration check in a logged-in graphical macOS session. The script builds a separate test app with its own bundle ID and Control–Option–Shift–backtick shortcut, leaving the running app and its sessions alone. It launches real shells, checks PTY behavior and tab isolation, resizing, hover sampling without mouse events, typing immediately after hover, pointer jitter and re-entry, focused auto-hide and focus restoration, immediate exit during reveal and reopening during close, pinning, upward slide movement, interrupted animations, and process cleanup, then quits. Results are written to `build/smoke-results.json` (override with `NOTCHBOX_SMOKE_REPORT`). A disposable native fixture app verifies that hiding restores its focused text field, a terminated destination stays closed, tab changes retain the original focus destination, and switching apps during reveal does not steal focus back. Keyboard and focus checks are reported as not checked if native focus is unavailable. The fixture changes only its own shells' environments and directories; it does not move the desktop pointer.

See [product research and interaction decisions](docs/inspiration.md).

For a view-only image export during development:

```sh
NOTCHBOX_PREVIEW_PATH="$PWD/build/notchbox-preview.png" \
  build/Notchbox.app/Contents/MacOS/Notchbox --render-preview
```

This renders the app's own view after running `pwd` and `ls` in the current directory. It does not capture the desktop.
