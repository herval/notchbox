import AppKit

/// Renders this app's own views for visual QA, without reading the desktop.
@MainActor
enum ViewPreview {
    static func render(controller: AppController) async {
        // Keep the panel visible if another app takes focus during the export.
        if !controller.isPinned { controller.togglePin() }
        let output = ProcessInfo.processInfo.environment["NOTCHBOX_PREVIEW_PATH"] ?? "/tmp/notchbox-preview.png"
        let working = FileManager.default.currentDirectoryPath
        let inside = NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.minY + 30)
        controller.pointerLocation = { inside }
        guard let first = controller.selectedSession else { exit(1) }
        first.terminal.suspendsRenderingWhenNotVisible = false
        first.terminal.send(txt: "printf 'PREVIEW_%s\\n' 'READY'\r")
        guard await wait({ text(first).contains("PREVIEW_READY") }) else { exit(1) }
        first.terminal.send(txt: "cd \(quote(working)); clear\r")
        try? await Task.sleep(for: .milliseconds(250))
        controller.addSession(directory: working)
        controller.select(first.id)
        first.terminal.send(txt: "pwd\r")
        try? await Task.sleep(for: .milliseconds(150))
        first.terminal.send(txt: "ls\r")
        try? await Task.sleep(for: .milliseconds(500))
        first.terminal.isHidden = true
        first.terminal.isHidden = false
        first.terminal.requestRedraw()
        try? await Task.sleep(for: .milliseconds(150))
        guard let view = controller.panel.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let terminalBitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(first.terminal.bounds.width * 2), pixelsHigh: Int(first.terminal.bounds.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let terminalGraphics = NSGraphicsContext(bitmapImageRep: terminalBitmap),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // AppKit's subtree cache omits SwiftTerm's retained drawing. Ask the actual
        // terminal view to draw into its own context, then composite that same view.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = terminalGraphics
        terminalGraphics.cgContext.scaleBy(x: 2, y: 2)
        first.terminal.draw(first.terminal.bounds)
        NSGraphicsContext.restoreGraphicsState()
        if let terminalImage = terminalBitmap.cgImage {
            let position = view.convert(first.terminal.bounds, from: first.terminal)
            let rectangle = NSRect(x: position.minX, y: view.bounds.height - position.maxY,
                                   width: position.width, height: position.height)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            graphics.cgContext.concatenate(graphics.cgContext.ctm.inverted())
            graphics.cgContext.scaleBy(x: scale, y: scale)
            graphics.cgContext.draw(terminalImage, in: rectangle)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: output)); print("View exported to \(output)") }
        catch { print("View export failed: \(error)"); exit(1) }
        controller.selection.ids.forEach { controller.close($0) }
        NSApp.terminate(nil)
    }
    private static func text(_ session: TerminalSession) -> String {
        String(data: session.terminal.getBufferAsData(), encoding: .utf8) ?? ""
    }
    private static func wait(_ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        return condition()
    }
    private static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
