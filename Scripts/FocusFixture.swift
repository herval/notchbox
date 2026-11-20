import AppKit

// A separate, disposable app for verifying cross-application keyboard focus.
@MainActor
final class FocusFixture: NSObject, NSApplicationDelegate {
    private let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    private var window: NSWindow!
    private var field: NSTextField!
    private var timer: Timer?
    private var lastCommand = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 110),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Notchbox focus test"
        field = NSTextField(string: "Keep this field focused")
        field.frame = NSRect(x: 20, y: 40, width: 320, height: 24)
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        NSApp.activate(ignoringOtherApps: true)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let command = (try? String(contentsOf: directory.appendingPathComponent("command"), encoding: .utf8)) ?? ""
        if command != lastCommand {
            lastCommand = command
            let parts = command.split(separator: " ")
            if parts.first == "yield", parts.count >= 2, let pid = Int32(parts[1]),
               let target = NSRunningApplication(processIdentifier: pid) {
                NSApp.yieldActivation(to: target)
            } else if parts.first == "focus" {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(field)
            }
        }
        let state: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "active": NSApp.isActive,
            "key": window.isKeyWindow,
            "fieldFocused": window.firstResponder === field.currentEditor(),
            "command": lastCommand
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let fixture = FocusFixture()
    app.delegate = fixture
    withExtendedLifetime(fixture) { app.run() }
}
