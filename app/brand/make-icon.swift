// Draws the Lidless icon layer: a frosted white "l" with a navy glass cloud resting against it.
// Usage: swift brand/make-icon.swift <layer.png> <preview.png>
import AppKit
let S: CGFloat = 1024
func render(_ path: String, tile: Bool) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    if tile {
        let r = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        r.addClip()
        NSGradient(colors: [NSColor(srgbRed: 0.12, green: 0.23, blue: 0.54, alpha: 1), NSColor(srgbRed: 0.03, green: 0.08, blue: 0.24, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)
    }
    // The "l": a tall rounded stem.
    let stem = NSBezierPath(roundedRect: NSRect(x: 372, y: 250, width: 168, height: 540), xRadius: 84, yRadius: 84)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor(white: 0, alpha: 0.35).cgColor)
    NSColor(white: 1, alpha: 0.94).setFill(); stem.fill()
    ctx.restoreGState()
    ctx.saveGState(); stem.addClip()
    NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(srgbRed: 0.84, green: 0.89, blue: 0.98, alpha: 1)])!
        .draw(in: stem.bounds, angle: -90)
    ctx.restoreGState()
    // Specular rim on the stem.
    NSColor(white: 1, alpha: 0.9).setStroke(); stem.lineWidth = 4; stem.stroke()

    // The cloud: three circles and a base, in navy glass, with a thin bright rim around the outside only.
    func cloudPath(_ i: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.appendOval(in: NSRect(x: 470, y: 300, width: 170, height: 170).insetBy(dx: i, dy: i))
        p.appendOval(in: NSRect(x: 560, y: 340, width: 210, height: 210).insetBy(dx: i, dy: i))
        p.appendOval(in: NSRect(x: 690, y: 300, width: 150, height: 150).insetBy(dx: i, dy: i))
        p.append(NSBezierPath(roundedRect: NSRect(x: 470, y: 300, width: 370, height: 120).insetBy(dx: i, dy: i), xRadius: 60 - i, yRadius: 60 - i))
        p.windingRule = .nonZero
        return p
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor(white: 0, alpha: 0.4).cgColor)
    NSColor(srgbRed: 0.72, green: 0.82, blue: 1, alpha: 1).setFill(); cloudPath(0).fill()
    ctx.restoreGState()
    ctx.saveGState(); cloudPath(4).addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.62, blue: 1, alpha: 1), NSColor(srgbRed: 0.10, green: 0.24, blue: 0.66, alpha: 1)])!
        .draw(in: NSRect(x: 470, y: 300, width: 370, height: 250), angle: -90)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(CommandLine.arguments[1], tile: false)
render(CommandLine.arguments[2], tile: true)
