import AppKit
import Foundation
let dest = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]
try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
func render(_ pixels: Int, _ filename: String) throws {
    let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 215, yRadius: 215)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.37, alpha: 1), ending: NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.18, alpha: 1))!.draw(in: tile, angle: 90)
        NSColor(calibratedRed: 0.91, green: 0.99, blue: 0.97, alpha: 1).setStroke()
        let face = NSBezierPath(); face.lineWidth = 45; face.lineCapStyle = .round; face.lineJoinStyle = .round
        for x: CGFloat in [220, 400] {
            face.move(to: NSPoint(x: x, y: 415)); face.line(to: NSPoint(x: x, y: 665))
            face.move(to: NSPoint(x: x + 115, y: 665)); face.line(to: NSPoint(x: x, y: 540)); face.line(to: NSPoint(x: x + 115, y: 415))
        }
        face.stroke()
        NSColor(calibratedRed: 0.35, green: 0.9, blue: 0.79, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 345, y: 290, width: 95, height: 90)).fill()
        NSColor(calibratedRed: 0.35, green: 0.9, blue: 0.79, alpha: 1).setStroke()
        let waves = NSBezierPath(); waves.lineWidth = 43; waves.lineCapStyle = .round
        waves.move(to: NSPoint(x: 635, y: 445)); waves.curve(to: NSPoint(x: 635, y: 635), controlPoint1: NSPoint(x: 700, y: 490), controlPoint2: NSPoint(x: 700, y: 590))
        waves.move(to: NSPoint(x: 720, y: 380)); waves.curve(to: NSPoint(x: 720, y: 700), controlPoint1: NSPoint(x: 835, y: 470), controlPoint2: NSPoint(x: 835, y: 610))
        waves.stroke(); return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dest).appendingPathComponent(filename))
}
for size in sizes { try render(size, "icon_\(size)x\(size).png"); try render(size * 2, "icon_\(size)x\(size)@2x.png") }
