# Notchbox product direction

Research checked 20 November 2026 against the products' own sites and documentation.

| App | Useful reference | Decision for Notchbox |
| --- | --- | --- |
| [QuakeNotch](https://quakenotch.com/user-guide/features/terminal) | Notch-anchored dropdown, independent tabs, familiar create/close/navigation shortcuts. Its wider product also includes music and AI features. | Keep the fast dropdown and tab model. Each shell remains alive when the panel hides. |
| [Notchy terminal](https://notchy.dev/mac-notch-terminal/) and [behavior settings](https://notchy.dev/help/settings/) | A real SwiftTerm terminal, hover reveal, delayed collapse, top-center access on displays without a notch. | Use a native PTY emulator and a small hover target. A short delay avoids accidental activation on a pointer pass. |
| [Ghostty quick terminal](https://ghostty.org/docs/config/reference#quick-terminal-position) | Dedicated top-edge terminal with a global shortcut and configurable focus behavior. | Offer keyboard access alongside hover, close on pointer exit unless pinned, and restore the previous app on dismissal. |
| [iTerm2 hotkey window](https://iterm2.com/documentation-highlights.html) | A dedicated terminal always available with one keystroke for occasional tasks. | Optimize for dropping in, running a command, and returning to the previous app. |

## The complete initial scope

A native macOS menu-bar app. Hover the notch to reveal a compact dark terminal panel. Hover to focus the selected terminal immediately, or reveal it with Control–backtick. Multiple tabs each own an independent login shell and scrollback. The panel can be pinned, and its size and text size adjusted.

Hover reveals the terminal and gives it keyboard focus immediately, including while the reveal animation is still running. A 120 ms dwell is tracked by stable display ID; a 50 ms pointer sampler supplements mouse events so stopping inside the notch still opens it. The trigger includes the exact top edge and a small lip below the cutout. Explicit dismissal stays closed until the pointer leaves the trigger. Leaving the notch and panel for 450 ms slides it closed even while it has keyboard focus, unless pinned or a confirmation sheet is open. Re-entry cancels the pending hide. A keyboard reveal with the pointer elsewhere waits until the pointer has entered the panel before enabling pointer-exit hiding. Dismissing it returns keyboard focus to the app active before reveal if that same app is still running; a later app switch is respected. Changing tabs does not replace the saved focus destination. The animation completion never reactivates Notchbox after focus has moved elsewhere. Clicking another app closes it unless pinned. Hiding never ends a session. Closing a tab with a foreground command asks before stopping it. Escape passes through to the shell and TUI apps; Command–Escape hides the panel.

The normal idle notch has no extra graphics on notched displays. External displays have a small top-center handle. Screen changes and negative display coordinates are supported. The global shortcut uses Carbon's targeted hotkey registration. Hover uses mouse events and AppKit pointer-location sampling without an Accessibility permission prompt.

Music, playback controls, widgets, AI integrations, split panes, notifications, accounts, and cloud services are outside this app's scope. Shells and their contents are in memory only, and end on Quit. Preferences store only panel and font size. No shell startup files are changed.

## Implementation

AppKit owns the borderless nonactivating NSPanel, hover/focus lifecycle, and custom tab strip. Tabs, add, pin, and hide share one row, without a separate brand header. Core Animation translates the panel content inside a clipped viewport: closing slides the terminal upward before hiding the window, while its grid size and shell process stay unchanged. Reopening interrupts the closing animation, and Reduce Motion makes the transition immediate. [SwiftTerm 1.99.3](https://github.com/migueldeicaza/SwiftTerm/releases/tag/v1.99.3) owns VT/xterm emulation, the real pseudo-terminal, rendering, scrollback, selection, clipboard shortcuts, mouse reporting, and terminal resizing. The dependency is pinned, and its MIT license is included in the built app.
