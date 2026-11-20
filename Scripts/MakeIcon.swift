import AppKit

let output = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: output).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels) / 1024
        NSColor(srgbRed: 0.035, green: 0.043, blue: 0.043, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 44*s, y: 44*s, width: 936*s, height: 936*s), xRadius: 214*s, yRadius: 214*s).fill()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 306*s, y: 650*s))
        line.line(to: NSPoint(x: 460*s, y: 512*s))
        line.line(to: NSPoint(x: 306*s, y: 374*s))
        line.move(to: NSPoint(x: 528*s, y: 372*s))
        line.line(to: NSPoint(x: 720*s, y: 372*s))
        line.lineWidth = 57*s
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        NSColor(srgbRed: 0.64, green: 0.87, blue: 0.72, alpha: 1).setStroke()
        line.stroke()
        // The small inset at the top echoes the hardware notch.
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 384*s, y: 854*s, width: 256*s, height: 140*s), xRadius: 35*s, yRadius: 35*s).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output + "/AppIcon.icns"]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
