import AppKit

@MainActor
final class TerminalPanelView: NSView {
    var topInset: CGFloat = 32 { didSet { needsLayout = true } }
    private let tabsScroll = NSScrollView()
    private let tabsDocument = FlippedView()
    let terminalHost = FlippedView()
    private let directoryLabel = Palette.label("~", size: 10)
    private let shellLabel = Palette.label("zsh", size: 10)
    private let shortcutLabel = Palette.label("⌃`  toggle   ·   ⌘T  new tab", size: 10)
    private var pinButton: ActionButton!
    private var collapseButton: ActionButton!
    private var newButton: ActionButton!
    private var restartButton: NSButton!
    private var tabViews: [UUID: TerminalTabView] = [:]
    private var orderedIDs: [UUID] = []
    private var selectedID: UUID?
    private var select: ((UUID) -> Void)?
    private var close: ((UUID) -> Void)?

    init(new: @escaping () -> Void, select: @escaping (UUID) -> Void,
         close: @escaping (UUID) -> Void, pin: @escaping () -> Void,
         collapse: @escaping () -> Void, restart: @escaping () -> Void) {
        super.init(frame: .zero)
        self.select = select
        self.close = close
        wantsLayer = true
        layer?.masksToBounds = true
        [tabsScroll, terminalHost, shellLabel, directoryLabel, shortcutLabel].forEach(addSubview)
        tabsScroll.documentView = tabsDocument
        tabsScroll.drawsBackground = false
        tabsScroll.hasHorizontalScroller = false
        tabsScroll.hasVerticalScroller = false
        tabsScroll.horizontalScrollElasticity = .allowed
        tabsScroll.verticalScrollElasticity = .none
        tabsScroll.contentView.drawsBackground = false
        pinButton = ActionButton(symbol: "pin", help: "Keep terminal open", action: pin)
        collapseButton = ActionButton(symbol: "chevron.up", help: "Hide terminal (⌃`)", action: collapse)
        newButton = ActionButton(symbol: "plus", help: "New terminal tab (⌘T)", action: new)
        [pinButton!, collapseButton!, newButton!].forEach(addSubview)
        restartButton = NSButton(title: "Restart shell", target: nil, action: nil)
        restartButton.bezelStyle = .inline
        restartButton.isBordered = false
        restartButton.font = .systemFont(ofSize: 11, weight: .medium)
        restartButton.contentTintColor = Palette.accent
        restartButton.target = self
        restartButton.action = #selector(restartShell)
        restartHandler = restart
        addSubview(restartButton)
        restartButton.isHidden = true
        setAccessibilityLabel("Notchbox terminal panel")
    }
    private var restartHandler: (() -> Void)?
    @objc private func restartShell() { restartHandler?() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = panelPath()
        Palette.background.setFill()
        path.fill()
        Palette.hairline.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 18, y: topInset + 49))
        line.line(to: NSPoint(x: bounds.width - 18, y: topInset + 49))
        line.lineWidth = 0.5
        line.stroke()
    }

    private func panelPath() -> NSBezierPath {
        let w = bounds.width, h = bounds.height, r: CGFloat = 22
        let path = NSBezierPath()
        path.move(to: .zero)
        path.line(to: NSPoint(x: w, y: 0))
        path.line(to: NSPoint(x: w, y: h - r))
        path.curve(to: NSPoint(x: w - r, y: h), controlPoint1: NSPoint(x: w, y: h - r * 0.45), controlPoint2: NSPoint(x: w - r * 0.45, y: h))
        path.line(to: NSPoint(x: r, y: h))
        path.curve(to: NSPoint(x: 0, y: h - r), controlPoint1: NSPoint(x: r * 0.45, y: h), controlPoint2: NSPoint(x: 0, y: h - r * 0.45))
        path.close()
        return path
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        tabsScroll.frame = NSRect(x: 14, y: topInset + 7, width: w - 132, height: 35)
        newButton.frame = NSRect(x: w - 113, y: topInset + 10, width: 28, height: 28)
        pinButton.frame = NSRect(x: w - 79, y: topInset + 10, width: 28, height: 28)
        collapseButton.frame = NSRect(x: w - 45, y: topInset + 10, width: 28, height: 28)
        let tabWidth = min(185, max(120, (tabsScroll.bounds.width - 6) / CGFloat(max(1, min(orderedIDs.count, 4)))))
        tabsDocument.frame = NSRect(x: 0, y: 0, width: max(tabsScroll.bounds.width, CGFloat(orderedIDs.count) * (tabWidth + 4)), height: 35)
        for (index, id) in orderedIDs.enumerated() {
            tabViews[id]?.frame = NSRect(x: CGFloat(index) * (tabWidth + 4), y: 0, width: tabWidth, height: 33)
        }
        terminalHost.frame = NSRect(x: 20, y: topInset + 62, width: w - 40, height: max(40, bounds.height - topInset - 102))
        terminalHost.subviews.forEach { $0.frame = terminalHost.bounds }
        let footerY = bounds.height - 28
        shellLabel.frame = NSRect(x: 22, y: footerY, width: 94, height: 15)
        directoryLabel.frame = NSRect(x: 112, y: footerY, width: max(0, w - 370), height: 15)
        shortcutLabel.frame = NSRect(x: w - 222, y: footerY, width: 200, height: 15)
        shortcutLabel.alignment = .right
        restartButton.frame = NSRect(x: w - 125, y: footerY - 3, width: 105, height: 22)
        needsDisplay = true
    }

    func update(sessions: [TerminalSession], selected: UUID?, pinned: Bool) {
        let ids = sessions.map(\.id)
        if ids != orderedIDs {
            for id in orderedIDs where !ids.contains(id) { tabViews.removeValue(forKey: id)?.removeFromSuperview() }
            for session in sessions where tabViews[session.id] == nil {
                let id = session.id
                let tab = TerminalTabView(id: id, select: { [weak self] in self?.select?(id) }, close: { [weak self] in self?.close?(id) })
                tabViews[id] = tab
                tabsDocument.addSubview(tab)
            }
            orderedIDs = ids
            needsLayout = true
        }
        for (index, session) in sessions.enumerated() {
            tabViews[session.id]?.update(title: session.title, index: index, selected: session.id == selected, running: session.isRunning, isLast: index == sessions.count - 1)
        }
        pinButton.setActive(pinned)
        pinButton.toolTip = pinned ? "Unpin terminal" : "Keep terminal open"
        // Keep inactive terminals attached but hidden: this preserves their native drawing and input state.
        for view in terminalHost.subviews where !sessions.contains(where: { $0.terminal === view }) {
            view.removeFromSuperview()
        }
        for item in sessions {
            if item.terminal.superview !== terminalHost {
                item.terminal.frame = terminalHost.bounds
                item.terminal.autoresizingMask = [.width, .height]
                terminalHost.addSubview(item.terminal)
            }
            item.terminal.isHidden = item.id != selected
        }
        guard let session = sessions.first(where: { $0.id == selected }) else { return }
        shellLabel.stringValue = session.isRunning ? "●  \(URL(fileURLWithPath: session.shell).lastPathComponent)" : "○  exited"
        shellLabel.textColor = session.isRunning ? Palette.accent : .systemOrange
        let path = session.directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        directoryLabel.stringValue = session.exitDescription ?? (path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
        directoryLabel.toolTip = path
        restartButton.isHidden = session.isRunning
        shortcutLabel.isHidden = !session.isRunning
        if selectedID != selected {
            selectedID = selected
            layoutSubtreeIfNeeded()
            if let selected, let view = tabViews[selected] { view.scrollToVisible(view.bounds) }
        }
    }
}

@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SlideViewport: NSView {
    var blocksInteraction = false
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        blocksInteraction ? (bounds.contains(convert(point, from: superview)) ? self : nil) : super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class TerminalPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AnchorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        let text = ">_   Notchbox"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: Palette.accent]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
}
