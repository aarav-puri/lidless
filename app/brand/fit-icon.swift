// Fits icon artwork to Apple's macOS icon grid (an 824 pt rounded square centered on 1024), so macOS shows it
// full size instead of shrinking it into a grey container. Usage: swift brand/fit-icon.swift <in.png> <out.png>
import AppKit
import CoreImage
let a = CommandLine.arguments
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
let w = src.pixelsWide, h = src.pixelsHigh
// Bounding box of the opaque tile.
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where (src.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
// Trim a few pixels so the source's own rounded edge and rim never show at the new edge.
let inset = Int(Double(maxX - minX) * (CommandLine.arguments.count > 3 ? 0.06 : 0.02))
let crop = CGRect(x: minX + inset, y: minY + inset, width: maxX - minX - 2 * inset, height: maxY - minY - 2 * inset)
let cg = src.cgImage!.cropping(to: crop)!
let size: CGFloat = 1024, tile: CGFloat = CommandLine.arguments.count > 3 ? 1024 : 824, origin = (size - tile) / 2
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
// "full" (third argument): a full-bleed square for macOS 26+, which applies its own rounded mask.
if tile < size { let shape = NSBezierPath(roundedRect: NSRect(x: origin, y: origin, width: tile, height: tile), xRadius: 185.4, yRadius: 185.4); ctx.addPath(shape.cgPath); ctx.clip() }
// Fill the corners the crop removed with the tile's own edge color, then draw the artwork slightly oversized.
ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.12, blue: 0.33, alpha: 1)); ctx.fill(CGRect(x: origin, y: origin, width: tile, height: tile))
let over: CGFloat = 1.0, drawn = tile * over
ctx.draw(cg, in: CGRect(x: origin - (drawn - tile) / 2, y: origin - (drawn - tile) / 2, width: drawn, height: drawn))
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("Wrote \(a[2]) from tile \(crop)")
