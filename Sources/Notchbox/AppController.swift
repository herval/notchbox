import AppKit
import NotchboxCore
import Carbon

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private(set) var sessions: [UUID: TerminalSession] = [:]
    private(set) var selection = TabSelection()
    private(set) var isPresented = false
    private(set) var isPinned = false
    private(set) var panel: TerminalPanel
    private var shortcut: GlobalShortcut?
    private var statusItem: NSStatusItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var pointerTimer: Timer?
    private var hoverActivation = HoverActivation()
    private var hoverTargets: [(id: UInt32, screen: NSScreen, geometry: PanelGeometry)] = []
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }
    private let isSmokeTest = ProcessInfo.processInfo.arguments.contains("--smoke-test")
    private var hideWork: DispatchWorkItem?
    private var activeScreen: NSScreen?
    private var anchors: [NSPanel] = []
    private var previousApplication: NSRunningApplication?
    private var capturedFocusOrigin = false
    private var presentingAlert = false
    private var animationID = 0
    private var slideCompletion: DispatchWorkItem?
    private let viewport = SlideViewport()
    private var isOpening = false
    private var pointerEnteredPanel = false
    private var wantsKeyboardFocus = false
    private var pinMenuItem: NSMenuItem?
    private var sizeItems: [NSMenuItem] = []
    private var fontSize: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "fontSize")).clamped(to: 11...24, fallback: 13)
    private var panelSize: String = UserDefaults.standard.string(forKey: "panelSize") ?? "Comfortable"
    private lazy var root = TerminalPanelView(
        new: { [weak self] in self?.addSession() },
        select: { [weak self] in self?.select($0) },
        close: { [weak self] in self?.requestClose($0) },
        pin: { [weak self] in self?.togglePin() },
        collapse: { [weak self] in self?.hide() },
        restart: { [weak self] in self?.restartSelected() })

    override init() {
        panel = TerminalPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Notchbox"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        panel.contentView = viewport
        root.autoresizingMask = [.width, .height]
        viewport.addSubview(root)
    }

    var panelSlideOffset: CGFloat {
        guard isSlideAnimating else { return root.layer?.transform.m42 ?? 0 }
        return root.layer?.presentation()?.transform.m42 ?? root.layer?.transform.m42 ?? 0
    }
    var isSlideAnimating: Bool { root.layer?.animation(forKey: "notchSlide") != nil }
    var focusReturnApplication: NSRunningApplication? { previousApplication }
    var requestsKeyboardFocus: Bool { wantsKeyboardFocus }
    var shortcutIsRegistered: Bool { shortcut?.registered == true }
    var orderedSessions: [TerminalSession] { selection.ids.compactMap { sessions[$0] } }
    var selectedSession: TerminalSession? { selection.selected.flatMap { sessions[$0] } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        rebuildAnchors()
        let modifiers = isSmokeTest ? UInt32(controlKey | optionKey | shiftKey) : UInt32(controlKey)
        shortcut = GlobalShortcut(modifiers: modifiers) { [weak self] in self?.toggle() }
        if shortcut?.registered == false { statusItem?.button?.toolTip = "Notchbox · ⌃` is in use by another app. Hover the notch or click here." }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, !self.isSmokeTest else { return }
            self.handlePointer(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown { return self.handleKey(event) ? nil : event }
            if !self.isSmokeTest { self.handlePointer(event) }
            return event
        }
        startPointerSampling()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildAnchors()
                self.activeScreen = self.preferredScreen
                if self.isPresented { self.show(focus: self.panel.isKeyWindow, on: self.preferredScreen) }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--render-preview") {
            show(focus: false, animated: false)
            Task { await ViewPreview.render(controller: self) }
            return
        }
        if !ProcessInfo.processInfo.arguments.contains("--background") { show(focus: true) }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            Task { await SmokeTest.run(controller: self) }
        }
    }

    private var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func geometry(for screen: NSScreen) -> PanelGeometry {
        PanelGeometry(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                      leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }
    private func frame(for screen: NSScreen) -> NSRect {
        let sizes: [String: (CGFloat, CGFloat)] = ["Compact": (740, 360), "Comfortable": (900, 460), "Large": (1120, 600)]
        let size = sizes[panelSize] ?? sizes["Comfortable"]!
        return geometry(for: screen).expandedFrame(width: size.0, height: size.1)
    }

    private func setSlideOffset(_ offset: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.layer?.transform = CATransform3DMakeTranslation(0, offset, 0)
        CATransaction.commit()
    }

    private func slide(to offset: CGFloat, duration: TimeInterval, opening: Bool,
                       completion: @escaping @MainActor () -> Void) {
        slideCompletion?.cancel()
        slideCompletion = nil
        let from = panelSlideOffset
        root.layer?.removeAnimation(forKey: "notchSlide")
        setSlideOffset(offset)
        guard duration > 0, abs(offset - from) > 0.5 else { completion(); return }
        let animation = CABasicAnimation(keyPath: "transform.translation.y")
        animation.fromValue = from
        animation.toValue = offset
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: opening ? .easeOut : .easeInEaseOut)
        root.layer?.add(animation, forKey: "notchSlide")
        panel.invalidateShadow()
        let id = animationID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.animationID == id else { return }
            self.slideCompletion = nil
            self.root.layer?.removeAnimation(forKey: "notchSlide")
            self.panel.invalidateShadow()
            completion()
        }
        slideCompletion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func show(focus: Bool, on screen: NSScreen? = nil, animated: Bool = true) {
        guard let screen = screen ?? activeScreen ?? preferredScreen else { return }
        activeScreen = screen
        hideWork?.cancel()
        hideWork = nil
        hoverActivation.reset()
        animationID += 1
        let wasPresented = isPresented
        let wasVisible = panel.isVisible
        isPresented = true
        root.topInset = geometry(for: screen).topInset
        let destination = frame(for: screen)
        let shouldSlide = !wasPresented && animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isOpening = shouldSlide
        wantsKeyboardFocus = focus
        if focus { captureFocusOrigin() }
        viewport.blocksInteraction = shouldSlide
        panel.ignoresMouseEvents = false
        panel.setFrame(destination, display: true)
        if !wasPresented { pointerEnteredPanel = panel.frame.insetBy(dx: -8, dy: -8).contains(pointerLocation()) }
        viewport.frame = NSRect(origin: .zero, size: destination.size)
        root.frame = viewport.bounds
        root.layoutSubtreeIfNeeded()
        if selection.ids.isEmpty { addSession(focus: false) }
        refresh()
        root.layoutSubtreeIfNeeded()
        anchors.forEach { $0.orderOut(nil) }
        if shouldSlide && !wasVisible { setSlideOffset(-destination.height) }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if focus { focusTerminal() }
        slide(to: 0, duration: shouldSlide ? 0.23 : 0, opening: true) { [weak self] in
            guard let self, self.isPresented else { return }
            self.isOpening = false
            self.viewport.blocksInteraction = false
            if self.wantsKeyboardFocus, NSApp.isActive { self.makeTerminalFirstResponder() }
        }
    }

    func hide(restoreFocus: Bool = true, animated: Bool = true) {
        guard isPresented, !presentingAlert else { return }
        hideWork?.cancel()
        hideWork = nil
        hoverActivation.suppressUntilExit()
        // Decide before ordering out or resigning key changes the foreground application.
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let shouldRestore = restoreFocus && (panel.isKeyWindow || front == ownPID)
            && (front == ownPID || front == previousApplication?.processIdentifier)
        isOpening = false
        wantsKeyboardFocus = false
        panel.ignoresMouseEvents = true
        isPresented = false
        pointerEnteredPanel = false
        animationID += 1
        let duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.21 : 0
        slide(to: -root.bounds.height, duration: duration, opening: false) { [weak self] in
            guard let self, !self.isPresented else { return }
            self.panel.orderOut(nil)
            self.anchors.forEach { $0.orderFrontRegardless() }
            if self.selection.ids.isEmpty { self.refresh() }
        }
        returnKeyboardFocus(restore: shouldRestore)
    }

    @objc private func toggle() {
        if isPresented {
            if panel.isKeyWindow { hide() }
            else { focusTerminal() }
        } else {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? preferredScreen
            show(focus: true, on: screen)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if isPresented && wantsKeyboardFocus { makeTerminalFirstResponder() }
    }

    private func captureFocusOrigin() {
        guard !capturedFocusOrigin else { return }
        capturedFocusOrigin = true
        let front = NSWorkspace.shared.frontmostApplication
        previousApplication = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    private func makeTerminalFirstResponder() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(selectedSession?.terminal)
    }

    private func focusTerminal() {
        guard isPresented else { return }
        captureFocusOrigin()
        wantsKeyboardFocus = true
        // Capture keys during the slide as well, so typing immediately after hovering works.
        NSApp.activate(ignoringOtherApps: true)
        makeTerminalFirstResponder()
    }

    private func returnKeyboardFocus(restore: Bool) {
        let destination = previousApplication
        previousApplication = nil
        capturedFocusOrigin = false
        panel.resignKey()
        // An outside click or app switch already chose the next destination.
        guard restore, let destination, !destination.isTerminated else { return }
        NSApp.yieldActivation(to: destination)
        destination.activate(from: .current, options: [])
    }

    func addSession(focus: Bool = true, directory: String? = nil) {
        let candidate = directory ?? selectedSession?.currentDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        var isDirectory: ObjCBool = false
        let valid = FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) && isDirectory.boolValue
        let session = TerminalSession(directory: valid ? candidate : FileManager.default.homeDirectoryForCurrentUser.path, fontSize: fontSize)
        sessions[session.id] = session
        selection.append(session.id)
        session.onChange = { [weak self] in self?.refresh() }
        refresh()
        root.layoutSubtreeIfNeeded()
        session.start()
        if focus { focusTerminal() }
    }
    func select(_ id: UUID) {
        selection.select(id)
        refresh()
        focusTerminal()
    }
    private func advance(_ offset: Int) {
        selection.advance(by: offset)
        refresh()
        panel.makeFirstResponder(selectedSession?.terminal)
    }
    func requestClose(_ id: UUID) {
        guard let session = sessions[id], !presentingAlert else { return }
        guard session.hasForegroundJob else { close(id); return }
        presentingAlert = true
        let alert = NSAlert()
        alert.messageText = "Close this terminal?"
        alert.informativeText = "A command is still running in this tab. Closing it will stop the command."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Close Terminal")
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            self.presentingAlert = false
            if response == .alertSecondButtonReturn { self.close(id) }
            else { self.focusTerminal() }
        }
    }
    func close(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.onChange = nil
        selection.remove(id)
        session.stop()
        if selection.ids.isEmpty {
            // Keep the terminal's last frame visible until its closing slide finishes.
            if isPresented { hide() } else { refresh() }
        } else {
            refresh()
            panel.makeFirstResponder(selectedSession?.terminal)
        }
    }
    private func restartSelected() {
        guard let session = selectedSession, !session.isRunning else { return }
        session.start()
        focusTerminal()
    }
    @objc func togglePin() {
        isPinned.toggle()
        refresh()
    }
    private func refresh() { root.update(sessions: orderedSessions, selected: selection.selected, pinned: isPinned) }

    private func handlePointer(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            pointerClicked(at: NSEvent.mouseLocation, window: event.window)
        } else { pointerMoved(to: NSEvent.mouseLocation) }
    }

    func pointerClicked(at point: NSPoint, window: NSWindow?) {
        if isPresented, !panel.frame.contains(point), !isPinned, !presentingAlert {
            if window !== panel && window?.sheetParent !== panel { hide(restoreFocus: false) }
        } else if isPresented, panel.frame.contains(point), window === panel, (isOpening || !panel.isKeyWindow) {
            focusTerminal()
        }
    }

    private func startPointerSampling() {
        // Mouse monitors can miss events over the menu bar/camera cutout. Sampling also
        // completes a dwell when the pointer has stopped moving. Common modes include menu tracking.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointerMoved(to: self.pointerLocation())
            }
        }
        timer.tolerance = 0.01
        pointerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func pointerMoved(to point: NSPoint) {
        let target = hoverTargets.first { $0.geometry.triggerFrame.contains(point) }
        if isPresented {
            hoverActivation.reset()
            let inside = panel.frame.insetBy(dx: -8, dy: -8).contains(point)
            if inside { pointerEnteredPanel = true }
            // A keyboard reveal with the pointer elsewhere stays usable until its first pointer exit.
            if isOpening || inside || !pointerEnteredPanel || isPinned || presentingAlert {
                hideWork?.cancel()
                hideWork = nil
            } else if hideWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.hideWork = nil
                    guard self.isPresented, !self.isOpening, !self.isPinned, !self.presentingAlert,
                          self.pointerEnteredPanel,
                          !self.panel.frame.insetBy(dx: -8, dy: -8).contains(self.pointerLocation()) else { return }
                    self.hide()
                }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
            }
        } else if hoverActivation.update(target: target?.id, at: ProcessInfo.processInfo.systemUptime), let target {
            show(focus: true, on: target.screen)
            pointerEnteredPanel = true
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isPresented, panel.isKeyWindow, !presentingAlert else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == [.command] {
            switch key {
            case "t": addSession(); return true
            case "w": if let id = selection.selected { requestClose(id) }; return true
            case "\u{1b}": hide(); return true
            case "=", "+": zoom(1); return true
            case "-": zoom(-1); return true
            case "0": zoom(0); return true
            default:
                if let number = Int(key), (1...9).contains(number) {
                    if number == 9, let last = selection.ids.last { selection.select(last) }
                    else { selection.select(index: number - 1) }
                    refresh()
                    panel.makeFirstResponder(selectedSession?.terminal)
                    return true
                }
            }
        }
        if flags == [.command, .shift] && (event.keyCode == 33 || event.keyCode == 30) {
            advance(event.keyCode == 33 ? -1 : 1); return true
        }
        if event.keyCode == 48 && (flags == [.control] || flags == [.control, .shift]) {
            advance(flags.contains(.shift) ? -1 : 1); return true
        }
        return false
    }
    private func zoom(_ delta: CGFloat) {
        fontSize = delta == 0 ? 13 : min(24, max(11, fontSize + delta))
        orderedSessions.forEach { $0.terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
        UserDefaults.standard.set(Double(fontSize), forKey: "fontSize")
    }

    private func rebuildAnchors() {
        hoverActivation.reset()
        hoverTargets = NSScreen.screens.enumerated().map { index, screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? UInt32(index)
            return (id: id, screen: screen, geometry: geometry(for: screen))
        }
        anchors.forEach { $0.close() }
        anchors = NSScreen.screens.filter { $0.safeAreaInsets.top == 0 }.map { screen in
            let geometry = geometry(for: screen)
            let anchor = NSPanel(contentRect: geometry.notch, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            anchor.isReleasedWhenClosed = false
            anchor.backgroundColor = .clear
            anchor.isOpaque = false
            anchor.level = panel.level
            anchor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            anchor.ignoresMouseEvents = true
            anchor.contentView = AnchorView()
            if !isPresented { anchor.orderFrontRegardless() }
            return anchor
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard !presentingAlert else { return }
        wantsKeyboardFocus = false
        if !isPinned { hide(restoreFocus: false) }
    }

    private func installMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let name = NSMenuItem(title: "Notchbox", action: nil, keyEquivalent: "")
        menu.addItem(name)
        menu.addItem(item("Show / Hide Terminal", #selector(toggle), key: ""))
        let hint = NSMenuItem(title: "Hover the notch or press ⌃`", action: nil, keyEquivalent: "")
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(item("New Tab", #selector(menuNewTab), key: "t"))
        pinMenuItem = item("Keep Open", #selector(togglePin), key: "")
        menu.addItem(pinMenuItem!)
        let sizes = NSMenu()
        for size in ["Compact", "Comfortable", "Large"] {
            let option = item(size, #selector(changeSize(_:)), key: "")
            sizeItems.append(option)
            sizes.addItem(option)
        }
        let sizeItem = NSMenuItem(title: "Panel Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        menu.addItem(item("Quit Notchbox", #selector(quit), key: "q"))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Notchbox")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.toolTip = "Notchbox · hover the notch or press ⌃`"
        statusItem?.menu = menu
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item("Quit Notchbox", #selector(quit), key: "q"))
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }
    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        pinMenuItem?.state = isPinned ? .on : .off
        sizeItems.forEach { $0.state = $0.title == panelSize ? .on : .off }
    }
    @objc private func menuNewTab() {
        if !isPresented {
            let hadSessions = !selection.ids.isEmpty
            show(focus: true)
            if hadSessions { addSession() }
        } else { addSession() }
    }
    @objc private func changeSize(_ sender: NSMenuItem) {
        panelSize = sender.title
        UserDefaults.standard.set(panelSize, forKey: "panelSize")
        if isPresented { show(focus: panel.isKeyWindow, animated: false) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard orderedSessions.contains(where: \.hasForegroundJob) else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Notchbox?"
        alert.informativeText = "Commands are still running in your terminals. Quitting will close every session."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Notchbox")
        presentingAlert = true
        let response = alert.runModal()
        presentingAlert = false
        return response == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        orderedSessions.forEach { $0.onChange = nil; $0.stop() }
        shortcut?.unregister()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        pointerTimer?.invalidate()
        slideCompletion?.cancel()
        hideWork?.cancel()
        anchors.forEach { $0.close() }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>, fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
