// Renders a placeholder app icon: three fanned swatch chips on a dark squircle.
// Run via tools/makeicon.sh. Swap in your own artwork whenever you like.
import AppKit
import Foundation

let size: CGFloat = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Squircle background, inset the way macOS icons are.
let inset: CGFloat = 92
let bg = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 200, cornerHeight: 200, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1).cgColor,
        NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])
ctx.restoreGState()

// Three chips fanned from a shared pivot near the base, like a swatch fan.
struct Chip { let color: NSColor; let angle: CGFloat }
let chips = [
    Chip(color: NSColor(srgbRed: 0.29, green: 0.62, blue: 0.94, alpha: 1), angle: -22),
    Chip(color: NSColor(srgbRed: 0.98, green: 0.76, blue: 0.29, alpha: 1), angle: 0),
    Chip(color: NSColor(srgbRed: 0.96, green: 0.42, blue: 0.44, alpha: 1), angle: 22),
]

let chipW: CGFloat = 264
let chipH: CGFloat = 396
let pivotY: CGFloat = 306

for chip in chips {
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: pivotY)
    ctx.rotate(by: chip.angle * .pi / 180)

    let rect = CGRect(x: -chipW / 2, y: 0, width: chipW, height: chipH)
    let path = CGPath(roundedRect: rect, cornerWidth: 46, cornerHeight: 46, transform: nil)

    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(chip.color.cgColor)
    ctx.fillPath()

    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.setLineWidth(5)
    ctx.strokePath()

    ctx.restoreGState()
}

NSGraphicsContext.restoreGraphicsState()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
