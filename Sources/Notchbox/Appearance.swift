import AppKit

@MainActor
enum Palette {
    static let background = NSColor.black
    static let surface = NSColor(srgbRed: 0.092, green: 0.106, blue: 0.102, alpha: 1)
    static let text = NSColor(srgbRed: 0.87, green: 0.90, blue: 0.88, alpha: 1)
    static let secondary = NSColor(srgbRed: 0.46, green: 0.50, blue: 0.48, alpha: 1)
    static let accent = NSColor(srgbRed: 0.64, green: 0.87, blue: 0.72, alpha: 1)
    static let hairline = NSColor.white.withAlphaComponent(0.075)

    static func label(_ text: String, size: CGFloat = 11, color: NSColor? = nil, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color ?? secondary
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}

@MainActor
final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?
    private var tracking: NSTrackingArea?
    private let symbol: String
    private var isActive = false

    init(symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        super.init(frame: .zero)
        actionHandler = action
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        symbolConfiguration = .init(pointSize: 12, weight: .medium)
        isBordered = false
        bezelStyle = .inline
        contentTintColor = Palette.secondary
        toolTip = help
        setAccessibilityLabel(help)
        target = self
        self.action = #selector(invoke)
        wantsLayer = true
        layer?.cornerRadius = 7
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionHandler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Palette.surface.cgColor
        contentTintColor = Palette.text
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = isActive ? Palette.accent : Palette.secondary
    }
    func setActive(_ active: Bool) {
        isActive = active
        state = active ? .on : .off
        image = NSImage(systemSymbolName: active && symbol == "pin" ? "pin.fill" : symbol, accessibilityDescription: toolTip)
        contentTintColor = active ? Palette.accent : Palette.secondary
    }
}

@MainActor
final class TerminalTabView: NSView {
    let id: UUID
    let titleLabel = Palette.label("", size: 12)
    let indexLabel = Palette.label("", size: 9)
    private let dot = NSView()
    private let selectButton = NSButton()
    private var closeButton: ActionButton!
    private var tracking: NSTrackingArea?
    var isSelected = false

    init(id: UUID, select: @escaping () -> Void, close: @escaping () -> Void) {
        self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        selectButton.isBordered = false
        selectButton.title = ""
        selectButton.target = self
        selectButton.action = #selector(selectTab)
        selectHandler = select
        addSubview(selectButton)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        addSubview(dot)
        addSubview(titleLabel)
        addSubview(indexLabel)
        closeButton = ActionButton(symbol: "xmark", help: "Close tab (⌘W)", action: close)
        addSubview(closeButton)
        setAccessibilityRole(.group)
    }
    private var selectHandler: (() -> Void)?
    @objc private func selectTab() { selectHandler?() }
    override func mouseDown(with event: NSEvent) { selectHandler?() }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        selectButton.frame = bounds
        dot.frame = NSRect(x: 12, y: bounds.midY - 2.5, width: 5, height: 5)
        titleLabel.frame = NSRect(x: 25, y: bounds.midY - 8, width: bounds.width - 85, height: 17)
        indexLabel.frame = NSRect(x: bounds.width - 55, y: bounds.midY - 7, width: 24, height: 15)
        closeButton.frame = NSRect(x: bounds.width - 28, y: bounds.midY - 11, width: 23, height: 22)
    }
    func update(title: String, index: Int, selected: Bool, running: Bool, isLast: Bool) {
        isSelected = selected
        titleLabel.stringValue = title
        titleLabel.textColor = selected ? Palette.text : Palette.secondary
        indexLabel.stringValue = index < 8 ? "⌘\(index + 1)" : (isLast ? "⌘9" : "")
        indexLabel.textColor = Palette.secondary.withAlphaComponent(0.6)
        dot.layer?.backgroundColor = (running ? (selected ? Palette.accent : Palette.secondary) : NSColor.systemOrange).cgColor
        layer?.backgroundColor = (selected ? Palette.surface : NSColor.clear).cgColor
        closeButton.alphaValue = selected ? 1 : 0
        toolTip = title
        selectButton.setAccessibilityLabel("Select tab \(index + 1): \(title)")
    }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { closeButton.alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { closeButton.alphaValue = isSelected ? 1 : 0 }
}
