// Renders the "lidless" wordmark beside the app icon, for README and website use.
// Usage: swift brand/make-wordmark.swift <icon.png> <out.png> <light|dark>
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let dark = args.count > 3 && args[3] == "dark"
let descriptor = NSFont.systemFont(ofSize: 76, weight: .semibold).fontDescriptor.withDesign(.rounded)!
let font = NSFont(descriptor: descriptor, size: 76)!
let text = NSAttributedString(string: "lidless", attributes: [
    .font: font,
    .foregroundColor: dark ? NSColor.white : NSColor(srgbRed: 0x0B / 255, green: 0x18 / 255, blue: 0x38 / 255, alpha: 1),
    .kern: -2.0,
])
let size = NSSize(width: ceil(140 + text.size().width + 4), height: 128)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
icon.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128))
text.draw(at: NSPoint(x: 140, y: (128 - text.size().height) / 2 + 4))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2])")
