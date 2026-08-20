import AppKit
import UniformTypeIdentifiers

/// Renders a swatch spec card. One drawing routine feeds both PNG and PDF, so
/// the two can't drift apart.
///
/// Derived values are labelled as derived on the card itself. A card is a
/// reference artifact, not a print specification.
enum SwatchCard {

    static let size = CGSize(width: 460, height: 620)

    // MARK: - Output

    static func pngData(for swatch: Swatch, scale: CGFloat = 2) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        // Setting the logical size makes AppKit handle the @2x mapping.
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        draw(swatch, in: context.cgContext)

        return rep.representation(using: .png, properties: [:])
    }

    static func pdfData(for swatch: Swatch) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(swatch, in: context)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()

        return data as Data
    }

    // MARK: - Save and copy

    static func suggestedFilename(for swatch: Swatch, extension ext: String) -> String {
        let base = swatch.name?.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let stem = (base?.isEmpty == false ? base! : String(swatch.hex.dropFirst()))
        return "\(stem).\(ext)"
    }

    static func export(_ swatch: Swatch, as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(
            for: swatch,
            extension: type == .pdf ? "pdf" : "png"
        )
        panel.message = "Export swatch card"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data = type == .pdf ? pdfData(for: swatch) : pngData(for: swatch)
        guard let data else {
            NSLog("Swatch Monster: could not render card for \(swatch.hex)")
            return
        }
        do {
            try data.write(to: url)
        } catch {
            NSLog("Swatch Monster: card export failed — \(error.localizedDescription)")
        }
    }

    /// PNG onto the pasteboard, which is how a card usually reaches Slack.
    static func copyToClipboard(_ swatch: Swatch) {
        guard let data = pngData(for: swatch),
              let image = NSImage(data: data) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([image])
    }

    // MARK: - Drawing

    private static let ink = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
    private static let muted = NSColor(srgbRed: 0.45, green: 0.46, blue: 0.50, alpha: 1)
    private static let hairline = NSColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1)

    private static func grade(_ ratio: Double) -> (String, NSColor) {
        if ratio >= 7 { return ("AAA", NSColor(srgbRed: 0.11, green: 0.55, blue: 0.30, alpha: 1)) }
        if ratio >= 4.5 { return ("AA", NSColor(srgbRed: 0.11, green: 0.55, blue: 0.30, alpha: 1)) }
        if ratio >= 3 { return ("AA Large", NSColor(srgbRed: 0.72, green: 0.48, blue: 0.05, alpha: 1)) }
        return ("Fail", NSColor(srgbRed: 0.75, green: 0.24, blue: 0.20, alpha: 1))
    }

    private static func write(_ string: String,
                             font: NSFont,
                             color: NSColor,
                             at point: CGPoint,
                             tracking: CGFloat = 0) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if tracking != 0 { attributes[.kern] = tracking }
        NSAttributedString(string: string, attributes: attributes).draw(at: point)
    }

    private static func measure(_ string: String, font: NSFont) -> CGSize {
        NSAttributedString(string: string, attributes: [.font: font]).size()
    }

    private static func draw(_ swatch: Swatch, in context: CGContext) {
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // Color field
        let fieldHeight: CGFloat = 250
        let field = CGRect(x: 0, y: size.height - fieldHeight,
                           width: size.width, height: fieldHeight)
        context.setFillColor(swatch.nsColor.cgColor)
        context.fill(field)

        let fieldInk: NSColor = swatch.relativeLuminance < 0.4 ? .white : .black

        if let name = swatch.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            write(name.uppercased(),
                  font: .systemFont(ofSize: 11, weight: .semibold),
                  color: fieldInk.withAlphaComponent(0.75),
                  at: CGPoint(x: 32, y: field.minY + 18),
                  tracking: 1.4)
        }
        write(swatch.hex.uppercased(),
              font: .monospacedSystemFont(ofSize: 40, weight: .bold),
              color: fieldInk,
              at: CGPoint(x: 30, y: field.minY + 38))

        var y = field.minY - 42

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        write("Picked \(formatter.string(from: swatch.pickedAt))",
              font: .systemFont(ofSize: 12),
              color: muted,
              at: CGPoint(x: 32, y: y))
        y -= 22

        func rule(at yy: CGFloat) {
            context.setStrokeColor(hairline.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 32, y: yy))
            context.addLine(to: CGPoint(x: size.width - 32, y: yy))
            context.strokePath()
        }
        rule(at: y)
        y -= 28

        let bytes = swatch.bytes
        let hsl = swatch.hsl
        let cmyk = swatch.cmyk
        let lab = swatch.lab

        let rows: [(String, String)] = [
            ("RGB", "\(bytes.r), \(bytes.g), \(bytes.b)"),
            ("HSL", "\(Int(hsl.h.rounded()))°, \(Int((hsl.s * 100).rounded()))%, \(Int((hsl.l * 100).rounded()))%"),
            ("LAB", String(format: "%.1f, %.1f, %.1f", lab.L, lab.a, lab.b)),
            ("CMYK — derived", "\(Int((cmyk.c * 100).rounded())) \(Int((cmyk.m * 100).rounded())) "
                + "\(Int((cmyk.y * 100).rounded())) \(Int((cmyk.k * 100).rounded()))"),
        ]

        for (label, value) in rows {
            write(label, font: .systemFont(ofSize: 11, weight: .medium),
                  color: muted, at: CGPoint(x: 32, y: y))
            write(value, font: .monospacedSystemFont(ofSize: 13, weight: .medium),
                  color: ink, at: CGPoint(x: 176, y: y - 1))
            y -= 30
        }

        y -= 2
        rule(at: y)
        y -= 26

        write("CONTRAST", font: .systemFont(ofSize: 9, weight: .semibold),
              color: muted, at: CGPoint(x: 32, y: y), tracking: 1.2)
        y -= 26

        for (label, ratio) in [("on white", swatch.contrastOnWhite),
                               ("on black", swatch.contrastOnBlack)] {
            let (tag, tint) = grade(ratio)
            write(label, font: .systemFont(ofSize: 11, weight: .medium),
                  color: muted, at: CGPoint(x: 32, y: y))
            write(String(format: "%.2f", ratio),
                  font: .monospacedSystemFont(ofSize: 13, weight: .medium),
                  color: ink, at: CGPoint(x: 176, y: y - 1))

            let tagFont = NSFont.systemFont(ofSize: 10, weight: .bold)
            let pill = CGRect(x: 242, y: y - 3,
                              width: measure(tag, font: tagFont).width + 14, height: 19)
            context.setFillColor(tint.withAlphaComponent(0.13).cgColor)
            context.addPath(CGPath(roundedRect: pill, cornerWidth: 5, cornerHeight: 5,
                                   transform: nil))
            context.fillPath()
            write(tag, font: tagFont, color: tint,
                  at: CGPoint(x: pill.minX + 7, y: pill.minY + 4))
            y -= 28
        }

        // Nearest named color, flagged so it can't be read as a specification.
        if let match = PaletteLibrary.shared.nearest(to: swatch, limit: 1).first {
            y -= 4
            write("≈ \(match.entry.name)  ΔE \(String(format: "%.1f", match.deltaE))"
                  + "   · reference only, not a print spec",
                  font: .systemFont(ofSize: 10),
                  color: muted,
                  at: CGPoint(x: 32, y: y))
        }

        write("SWATCH MONSTER",
              font: .systemFont(ofSize: 8, weight: .medium),
              color: hairline.blended(withFraction: 0.35, of: muted) ?? muted,
              at: CGPoint(x: 32, y: 22), tracking: 1.0)
    }
}
