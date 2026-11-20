import AppKit
import Darwin
import SwiftTerm

@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminal: NotchTerminalView
    let shell: String
    private(set) var title: String
    private(set) var directory: String
    private(set) var isRunning = false
    private(set) var exitDescription: String?
    var onChange: (() -> Void)?
    private var lastDirectoryCheck = Date.distantPast

    init(directory: String, fontSize: CGFloat) {
        let configured = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) }
        shell = configured.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        title = URL(fileURLWithPath: shell).lastPathComponent
        self.directory = directory
        terminal = NotchTerminalView(frame: NSRect(x: 0, y: 0, width: 864, height: 338))
        super.init()
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = Palette.background
        terminal.nativeForegroundColor = Palette.text
        terminal.caretColor = Palette.accent
        terminal.optionAsMetaKey = false
        terminal.optionAsMetaKeyForFunctionalKeys = true
        terminal.processDelegate = self
        terminal.accessibilityLabelOverride = "Terminal session"
        terminal.setProcessOutputHandler { [weak self] in
            Task { @MainActor [weak self] in self?.refreshDirectory() }
        }
    }

    func start() {
        guard !isRunning else { return }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Notchbox"
        environment["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.4"
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        exitDescription = nil
        isRunning = true
        terminal.startProcess(executable: shell, args: ["-l"],
                              environment: environment.map { "\($0.key)=\($0.value)" },
                              currentDirectory: directory)
        onChange?()
    }

    private func refreshDirectory() {
        guard Date().timeIntervalSince(lastDirectoryCheck) > 0.3 else { return }
        lastDirectoryCheck = Date()
        let path = currentDirectory
        if path != directory { directory = path; onChange?() }
    }

    var hasForegroundJob: Bool {
        guard isRunning else { return false }
        let foreground = tcgetpgrp(terminal.process.childfd)
        return foreground > 0 && foreground != terminal.process.shellPid
    }

    /// Read the actual shell cwd as well as OSC 7, so plain shells need no injected hooks.
    var currentDirectory: String {
        guard isRunning else { return directory }
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let result = proc_pidinfo(terminal.process.shellPid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size))
        if result == size {
            let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if !path.isEmpty { return path }
        }
        return directory
    }

    func stop() {
        guard isRunning else { return }
        let foreground = tcgetpgrp(terminal.process.childfd)
        if foreground > 0 && foreground != getpgrp() {
            kill(-foreground, SIGHUP)
        }
        terminal.terminate()
        isRunning = false
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { onChange?() }
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let clean = title.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(80)
        self.title = clean.isEmpty ? URL(fileURLWithPath: shell).lastPathComponent : String(clean)
        onChange?()
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory else { return }
        if let url = URL(string: directory), url.isFileURL { self.directory = url.path }
        else if directory.hasPrefix("/") { self.directory = directory }
        onChange?()
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isRunning = false
        exitDescription = exitCode.map { "Shell exited · \($0)" } ?? "Shell ended"
        onChange?()
    }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        isRunning = false
        exitDescription = "Shell could not start"
        onChange?()
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}

@MainActor
final class NotchTerminalView: LocalProcessTerminalView {
    var accessibilityLabelOverride: String = "Terminal"
    override func accessibilityLabel() -> String? { accessibilityLabelOverride }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
