import AppKit
import Foundation

// A code-drawn icon: crisp geometry at every Dock/Finder size, no font dependency.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    let tile = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 24; shadow.set()
    NSColor(red: 0.48, green: 0.035, blue: 0.09, alpha: 1).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.58, green: 0.035, blue: 0.10, alpha: 1), NSColor(red: 1, green: 0.23, blue: 0.25, alpha: 1)])!.draw(in: tile, angle: 60)
    NSGraphicsContext.saveGraphicsState(); tile.addClip()
    let glow = NSBezierPath(ovalIn: NSRect(x: -300, y: 490, width: 1100, height: 760))
    NSColor.white.withAlphaComponent(0.075).setFill(); glow.fill()
    NSGraphicsContext.restoreGraphicsState()
    let rim = NSBezierPath(roundedRect: NSRect(x: 91, y: 91, width: 842, height: 842), xRadius: 189, yRadius: 189)
    NSColor.white.withAlphaComponent(0.22).setStroke(); rim.lineWidth = 3; rim.stroke()
    // Stacked video cards plus a download badge remain legible at Dock sizes.
    let back = NSBezierPath(roundedRect: NSRect(x: 230, y: 413, width: 550, height: 354), xRadius: 68, yRadius: 68)
    let rotate = AffineTransform(rotationByDegrees: 8); var transform = rotate
    transform.translate(x: 32, y: -50)
    back.transform(using: transform)
    NSColor.white.withAlphaComponent(0.15).setFill(); back.fill()
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow(); glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -16); glyphShadow.shadowBlurRadius = 24; glyphShadow.set()
    let front = NSBezierPath(roundedRect: NSRect(x: 213, y: 355, width: 558, height: 364), xRadius: 65, yRadius: 65)
    NSColor(red: 1, green: 0.96, blue: 0.96, alpha: 1).setFill(); front.fill()
    NSGraphicsContext.restoreGraphicsState()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 426, y: 623)); play.line(to: NSPoint(x: 426, y: 451)); play.line(to: NSPoint(x: 571, y: 537)); play.close()
    NSColor(red: 0.84, green: 0.10, blue: 0.16, alpha: 1).setFill(); play.fill()
    NSGraphicsContext.saveGraphicsState()
    glyphShadow.set()
    let badge = NSBezierPath(ovalIn: NSRect(x: 551, y: 205, width: 278, height: 278))
    NSColor(red: 0.17, green: 0.12, blue: 0.16, alpha: 1).setFill(); badge.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setStroke()
    let arrow = NSBezierPath(); arrow.lineWidth = 27; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 690, y: 407)); arrow.line(to: NSPoint(x: 690, y: 295)); arrow.stroke()
    let tip = NSBezierPath(); tip.lineWidth = 27; tip.lineCapStyle = .round; tip.lineJoinStyle = .round
    tip.move(to: NSPoint(x: 643, y: 338)); tip.line(to: NSPoint(x: 690, y: 291)); tip.line(to: NSPoint(x: 737, y: 338)); tip.stroke()
    let tray = NSBezierPath(); tray.lineWidth = 20; tray.lineCapStyle = .round
    tray.move(to: NSPoint(x: 649, y: 258)); tray.line(to: NSPoint(x: 731, y: 258)); tray.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: output.appendingPathComponent("Youtube-Downloader-Icon.png"))
print("Rendered icon assets to \(output.path)")
