import AppKit
import SwiftTerm
import NotchboxCore

/// Opt-in integration check against real shell processes and the real AppKit panel.
@MainActor
enum SmokeTest {
    struct Check: Codable {
        let name: String
        let passed: Bool?
        let detail: String?
    }
    static func run(controller: AppController) async {
        var checks: [Check] = []
        var pointer = NSPoint(x: -1_000_000, y: -1_000_000)
        controller.pointerLocation = { pointer }
        func movePointer(to point: NSPoint) {
            pointer = point
            controller.pointerMoved(to: point)
        }
        func record(_ name: String, _ passed: Bool) {
            checks.append(Check(name: name, passed: passed, detail: nil))
            print("\(passed ? "PASS" : "FAIL") \(name)")
            fflush(stdout)
        }
        func notChecked(_ name: String) {
            checks.append(Check(name: name, passed: nil, detail: "The background test app did not receive native keyboard focus."))
            print("NOT CHECKED \(name): native foreground focus unavailable")
            fflush(stdout)
        }
        controller.show(focus: false, animated: false)
        let inside = NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.minY + 40)
        movePointer(to: inside)
        guard let first = controller.selectedSession else {
            print("FAIL initial session missing")
            exit(1)
        }
        record("isolated test shortcut registers without Accessibility access", controller.shortcutIsRegistered)
        first.terminal.send(txt: "printf 'READY_%s\\n' 'ONE'\r")
        record("login shell starts in a real PTY", await wait { text(first).contains("READY_ONE") })
        let firstPID = first.terminal.process.shellPid
        record("PTY has a live child process", firstPID > 0 && kill(firstPID, 0) == 0)
        first.terminal.send(txt: "export NOTCHBOX_SMOKE=alpha; cd /tmp; printf '\\033]2;smoke-one\\007\\033]7;file://localhost/tmp\\007'; printf '\\033[32mCOLOR_%s\\033[0m\\n' 'OK'; sleep 1\r")
        record("ANSI output, title, and working directory update", await wait {
            text(first).contains("COLOR_OK") && first.title == "smoke-one" && first.currentDirectory.hasSuffix("/tmp")
        })
        _ = await wait { !first.hasForegroundJob }
        let before = first.terminal.terminalDimensions.cols
        let smaller = NSRect(x: controller.panel.frame.minX, y: controller.panel.frame.minY, width: 700, height: controller.panel.frame.height)
        controller.panel.setFrame(smaller, display: true)
        controller.panel.contentView?.layoutSubtreeIfNeeded()
        record("terminal grid resizes with its panel", await wait { first.terminal.terminalDimensions.cols < before })
        controller.hide(restoreFocus: false, animated: false)
        let focusFixture = try? await FocusTestApp.launch()
        if let focusFixture {
            _ = await wait(timeout: 3) { focusFixture.isFocused }
            await focusFixture.yield(to: .current)
        }
        controller.show(focus: true, animated: false)
        let nativeFocusAvailable = await wait(timeout: 2) {
            controller.panel.isKeyWindow && controller.panel.firstResponder === controller.selectedSession?.terminal
        }
        if nativeFocusAvailable {
            // Exercise the application's shortcut through the normal AppKit event loop.
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.panel.windowNumber,
                                           context: nil, characters: "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17) {
                NSApp.postEvent(event, atStart: false)
            }
            record("Command-T opens and selects a second tab", await wait { controller.orderedSessions.count == 2 })
        } else {
            notChecked("Command-T opens and selects a second tab")
            controller.addSession(focus: false)
        }
        guard let second = controller.selectedSession, second.id != first.id else {
            focusFixture?.close()
            write(checks)
            exit(1)
        }
        second.terminal.send(txt: "printf 'ISOLATED_%s\\n' \"${NOTCHBOX_SMOKE-unset}\"; printf 'CWD_%s\\n' \"$PWD\"\r")
        record("tabs have isolated shell environments", await wait { text(second).contains("ISOLATED_unset") })
        record("new tab inherits the active working directory", second.currentDirectory.hasSuffix("/tmp"))
        record("tabs use independent processes", second.terminal.process.shellPid > 0 && second.terminal.process.shellPid != firstPID)
        controller.select(first.id)
        first.terminal.send(txt: "sleep 0.4; printf 'HIDDEN_%s\\n' 'OK'\r")
        controller.hide(animated: false)
        record("hidden terminal keeps its process and output", await wait { text(first).contains("HIDDEN_OK") && kill(firstPID, 0) == 0 && !controller.isPresented })
        controller.show(focus: true, animated: false)
        first.terminal.send(txt: "printf 'PRESERVED_%s\\n' \"$NOTCHBOX_SMOKE\"\r")
        record("showing the panel preserves shell state", await wait { text(first).contains("PRESERVED_alpha") && first.terminal.process.shellPid == firstPID })
        first.terminal.send(txt: "sleep 30\r")
        record("foreground job is detected before closing", await wait { first.hasForegroundJob })
        first.terminal.send(txt: "\u{03}")
        record("Control-C interrupts the foreground command", await wait { !first.hasForegroundJob })
        first.terminal.send(txt: "printf '\\033[?1049h\\033[2J\\033[HALT_%s' 'SCREEN'\r")
        record("TUI alternate screen is supported", await wait { first.terminal.terminalContentSnapshot(region: .all)?.bufferKind == .alt && text(first).contains("ALT_SCREEN") })
        first.terminal.send(txt: "printf '\\033[?1049l'\r")
        record("leaving a TUI restores normal scrollback", await wait { first.terminal.terminalContentSnapshot(region: .all)?.bufferKind == .normal && text(first).contains("PRESERVED_alpha") })
        controller.select(second.id)
        second.terminal.send(txt: "exit\r")
        record("shell exit leaves its output available", await wait { !second.isRunning && controller.orderedSessions.count == 2 })
        // Let the library finish its reaper callback before restarting the same PTY host.
        try? await Task.sleep(for: .milliseconds(200))
        second.start()
        second.terminal.send(txt: "printf 'RESTART_%s\\n' 'OK'\r")
        record("an exited shell can be restarted", await wait { second.isRunning && text(second).contains("RESTART_OK") })
        controller.close(second.id)
        record("closing a tab selects the remaining session", controller.selection.selected == first.id && controller.orderedSessions.count == 1)
        // Test hover timing through the same pointer handlers as NSEvent, without moving the desktop pointer.
        controller.hide(animated: false)
        if nativeFocusAvailable, let focusFixture {
            record("hiding restores the previous app and its text field", await wait { focusFixture.isFocused })
        } else { notChecked("hiding restores the previous app and its text field") }
        let outside = NSPoint(x: controller.panel.frame.minX - 40, y: controller.panel.frame.minY - 40)
        let screen = controller.panel.screen ?? NSScreen.screens.first!
        let geometry = PanelGeometry(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                                     leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
        let trigger = NSPoint(x: geometry.notch.midX, y: screen.frame.maxY - 4)
        print("Panel frame \(controller.panel.frame); screen \(screen.frame); notch \(geometry.notch)")
        record("panel is flush with the display's top edge", abs(controller.panel.frame.maxY - screen.frame.maxY) < 1)
        movePointer(to: outside)
        movePointer(to: trigger)
        movePointer(to: outside)
        try? await Task.sleep(for: .milliseconds(250))
        record("passing across the notch does not open it", !controller.isPresented)
        // Change only the sampled location: no mouse-move event is delivered.
        pointer = trigger
        record("stationary hover opens through the pointer sampler without mouse events", await wait { controller.isPresented })
        record("hover immediately requests the selected terminal as first responder", controller.requestsKeyboardFocus && controller.panel.firstResponder === first.terminal)
        if nativeFocusAvailable {
            record("hover captures keyboard focus without a click", await wait { controller.panel.isKeyWindow })
            if controller.panel.isKeyWindow {
                postTyping("printf 'HOVER_%s\\n' 'INPUT'\r", to: controller.panel)
                record("typing after hover reaches the PTY without a click", await wait { text(first).contains("HOVER_INPUT") })
            }
        } else { notChecked("hover captures keyboard focus and accepts typing without a click") }
        movePointer(to: outside)
        record("pointer exit begins hiding synchronously even with keyboard focus", !controller.isPresented)
        record("auto-hide finishes the upward retraction", await wait { !controller.isPresented && !controller.panel.isVisible })
        if nativeFocusAvailable, let focusFixture {
            record("auto-hide restores the previous app and its focused text field", await wait { focusFixture.isFocused })
        } else { notChecked("auto-hide restores the previous app and its focused text field") }
        record("auto-hide preserves the terminal process and its output", first.terminal.process.shellPid == firstPID && kill(firstPID, 0) == 0 && text(first).contains("PRESERVED_alpha"))
        movePointer(to: outside)
        for step in 0..<16 {
            movePointer(to: NSPoint(x: trigger.x + CGFloat(step % 3 - 1) * 3, y: trigger.y))
            try? await Task.sleep(for: .milliseconds(20))
        }
        record("pointer jitter inside the notch does not postpone opening", controller.isPresented)
        controller.hide(restoreFocus: false, animated: false)
        try? await Task.sleep(for: .milliseconds(250))
        record("explicit close stays closed while the cursor remains on the notch", !controller.isPresented)
        movePointer(to: outside)
        pointer = trigger
        record("hover rearms after leaving and reentering the notch", await wait { controller.isPresented })
        movePointer(to: outside)
        record("pointer exit interrupts reveal without waiting for the opening animation", !controller.isPresented)
        // Return immediately, without another outside sample after hide, to verify rearming.
        movePointer(to: trigger)
        record("returning to the notch can reopen during the closing slide", await wait { controller.isPresented })
        movePointer(to: inside)
        controller.hide(animated: false)
        movePointer(to: outside)
        controller.show(focus: true, animated: false)
        try? await Task.sleep(for: .milliseconds(650))
        record("keyboard reveal with the pointer elsewhere waits for its first pointer exit", controller.isPresented)
        movePointer(to: inside)
        controller.togglePin()
        movePointer(to: outside)
        try? await Task.sleep(for: .milliseconds(650))
        record("pinning prevents auto-hide when the pointer leaves", controller.isPresented && controller.isPinned)
        controller.pointerClicked(at: outside, window: nil)
        record("pinning keeps the panel open after an outside click", controller.isPresented && controller.isPinned)
        controller.togglePin()
        record("unpinning outside the panel starts hiding synchronously", !controller.isPresented)
        _ = await wait { !controller.panel.isVisible }
        movePointer(to: inside)
        controller.show(focus: true, animated: false)
        controller.pointerClicked(at: outside, window: nil)
        record("an outside click dismisses an unpinned panel", !controller.isPresented)
        controller.show(focus: true, animated: false)
        let expanded = controller.panel.frame
        let dimensions = first.terminal.terminalDimensions
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            controller.hide(restoreFocus: false, animated: true)
            record("close installs an opaque upward slide", controller.panel.isVisible && controller.panel.alphaValue == 1 && controller.isSlideAnimating)
            try? await Task.sleep(for: .milliseconds(80))
            record("close moves the panel upward", controller.panelSlideOffset < -1)
            record("sliding preserves the terminal grid and shell process", first.terminal.terminalDimensions == dimensions && first.terminal.process.shellPid == firstPID)
            record("close retracts the entire panel beyond the top edge", await wait {
                !controller.panel.isVisible && controller.panelSlideOffset <= -expanded.height + 1
            })
            controller.show(focus: true, animated: true)
            record("open slides back to the notch position", await wait {
                abs(controller.panelSlideOffset) < 1 && controller.panel.isVisible
            })
            controller.hide(restoreFocus: false, animated: true)
            try? await Task.sleep(for: .milliseconds(60))
            controller.show(focus: true, animated: true)
            try? await Task.sleep(for: .milliseconds(350))
            record("reopening during close leaves the panel visible at its final position", controller.isPresented && controller.panel.isVisible && abs(controller.panelSlideOffset) < 1)
        }
        controller.close(first.id)
        record("closing the last tab hides the panel", !controller.isPresented && controller.orderedSessions.isEmpty)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            record("last tab output stays attached during its closing slide", first.terminal.superview != nil && controller.panel.isVisible)
        }
        record("closed terminal view is released after retraction", await wait { first.terminal.superview == nil && !controller.panel.isVisible })
        record("closed terminal process is reaped", await wait { kill(firstPID, 0) == -1 && errno == ESRCH })
        await checkFocusReturn(controller: controller, fixture: focusFixture, nativeFocusAvailable: nativeFocusAvailable,
                               record: record, notChecked: notChecked)
        focusFixture?.close()
        write(checks)
        if checks.allSatisfy({ $0.passed != false }) { NSApp.terminate(nil) }
        else { exit(1) }
    }
    private static func postTyping(_ text: String, to panel: NSPanel) {
        for character in text {
            let value = String(character)
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                           context: nil, characters: value, charactersIgnoringModifiers: value,
                                           isARepeat: false, keyCode: character == "\r" ? 36 : 0) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static func checkFocusReturn(controller: AppController, fixture: FocusTestApp?, nativeFocusAvailable: Bool,
                                         record: (String, Bool) -> Void, notChecked: (String) -> Void) async {
        guard let fixture, nativeFocusAvailable else {
            notChecked("focus returns only to a live destination and respects a subsequent app switch")
            return
        }
        await fixture.focus()
        guard await wait(timeout: 3, for: { fixture.isFocused }) else {
            notChecked("focus return edge cases: fixture could not become active")
            return
        }
        await fixture.yield(to: .current)
        controller.show(focus: true, animated: false)
        let origin = controller.focusReturnApplication?.processIdentifier
        let first = controller.selection.selected!
        controller.addSession()
        controller.select(first)
        record("tab changes preserve the app focused before reveal", origin == fixture.application.processIdentifier && controller.focusReturnApplication?.processIdentifier == origin)
        controller.togglePin()
        if let second = try? await FocusTestApp.launch() {
            await fixture.yield(to: second.application)
            await second.focus()
            let switched = await wait(timeout: 3) { second.isFocused }
            let stayedPinned = controller.isPresented && controller.focusReturnApplication?.processIdentifier == origin
            controller.hide(animated: false)
            try? await Task.sleep(for: .milliseconds(250))
            record("hiding after switching apps keeps the newly chosen app focused", stayedPinned && switched && second.isFocused)
            await fixture.focus()
            _ = await wait(timeout: 3) { fixture.isFocused }
            await fixture.yield(to: .current)
            controller.show(focus: true, animated: true)
            await fixture.yield(to: second.application)
            await second.focus()
            _ = await wait(timeout: 3) { second.isFocused }
            try? await Task.sleep(for: .milliseconds(350))
            record("finishing the reveal does not steal focus back after an app switch", controller.isPresented && second.isFocused)
            controller.hide(animated: false)
            second.close()
        } else { notChecked("hiding after switching apps keeps the newly chosen app focused") }
        controller.togglePin()
        await fixture.focus()
        _ = await wait(timeout: 3) { fixture.isFocused }
        await fixture.yield(to: .current)
        controller.show(focus: true, animated: false)
        let target = controller.focusReturnApplication
        fixture.application.terminate()
        let exited = await wait { fixture.application.isTerminated }
        controller.hide(animated: false)
        try? await Task.sleep(for: .milliseconds(250))
        record("a terminated focus destination is discarded without relaunching it", exited && target?.isTerminated == true && controller.focusReturnApplication == nil && !NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == fixture.application.processIdentifier })
        controller.selection.ids.forEach { controller.close($0) }
    }

    private static func text(_ session: TerminalSession) -> String {
        String(data: session.terminal.getBufferAsData(), encoding: .utf8) ?? ""
    }
    private static func wait(timeout: TimeInterval = 8, for condition: @escaping () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try? await Task.sleep(for: .milliseconds(100)) }
        return condition()
    }
    private static func write(_ checks: [Check]) {
        let path = ProcessInfo.processInfo.environment["NOTCHBOX_SMOKE_REPORT"] ?? "/tmp/notchbox-smoke-results.json"
        if let data = try? JSONEncoder().encode(checks) { try? data.write(to: URL(fileURLWithPath: path)) }
        let executed = checks.filter { $0.passed != nil }
        print("\(executed.filter { $0.passed == true }.count)/\(executed.count) integration checks passed; \(checks.count - executed.count) not checked")
        fflush(stdout)
    }
}

/// Talks only to the disposable test app built by Scripts/test-app.sh.
@MainActor
private final class FocusTestApp {
    let application: NSRunningApplication
    private let directory: URL

    private init(application: NSRunningApplication, directory: URL) {
        self.application = application
        self.directory = directory
    }

    static func launch() async throws -> FocusTestApp {
        guard let path = ProcessInfo.processInfo.environment["NOTCHBOX_FOCUS_FIXTURE_APP"] else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notchbox-focus-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [directory.path]
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        let application = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
        return FocusTestApp(application: application, directory: directory)
    }


    var isFocused: Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return state["active"] as? Bool == true && state["key"] as? Bool == true && state["fieldFocused"] as? Bool == true
    }

    private func send(_ command: String) async {
        let token = command + " " + UUID().uuidString
        try? token.write(to: directory.appendingPathComponent("command"), atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
               let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               state["command"] as? String == token { return }
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    func yield(to application: NSRunningApplication) async { await send("yield \(application.processIdentifier)") }
    func focus() async {
        if NSApp.isActive { NSApp.yieldActivation(to: application) }
        await send("focus")
    }
    func close() {
        if !application.isTerminated { application.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }
}
