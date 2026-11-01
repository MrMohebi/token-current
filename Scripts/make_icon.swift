// Code-native vector icon, rasterized into a standard macOS iconset at packaging time.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Scripts/make_icon.swift output.iconset")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not create icon bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = Double(pixels) / 1024
        context.cgContext.scaleBy(x: factor, y: factor)
        NSColor(red: 0.09, green: 0.12, blue: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 194, yRadius: 194).fill()
        func arrow(x: Double, up: Bool, color: NSColor) {
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 64
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let start = up ? 310.0 : 714.0
            let end = up ? 714.0 : 310.0
            path.move(to: NSPoint(x: x, y: start))
            path.line(to: NSPoint(x: x, y: end))
            path.move(to: NSPoint(x: x - 102, y: end + (up ? -102 : 102)))
            path.line(to: NSPoint(x: x, y: end))
            path.line(to: NSPoint(x: x + 102, y: end + (up ? -102 : 102)))
            path.stroke()
        }
        arrow(x: 363, up: true, color: NSColor(red: 0.35, green: 0.85, blue: 0.91, alpha: 1))
        arrow(x: 661, up: false, color: NSColor(red: 0.98, green: 0.74, blue: 0.36, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
        try png.write(to: destination.appending(path: "icon_\(size)x\(size)\(suffix).png"))
    }
}
