import AppKit
import SwiftUI

// MARK: - Swatch

/// A single picked color, stored in sRGB so hex values are stable no matter
/// which display it was sampled from.
struct Swatch: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1
    var pickedAt: Date = Date()
    /// Optional label, shown on exported cards. Decodes as nil for colors
    /// picked before this field existed.
    var name: String? = nil

    init(color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        red = Double(c.redComponent)
        green = Double(c.greenComponent)
        blue = Double(c.blueComponent)
        alpha = Double(c.alphaComponent)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green),
                blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    var color: Color { Color(nsColor) }

    /// 0–255 components, rounded once so every format agrees with the others.
    var bytes: (r: Int, g: Int, b: Int) {
        (Int((red * 255).rounded()),
         Int((green * 255).rounded()),
         Int((blue * 255).rounded()))
    }

    var hex: String {
        let b = bytes
        return String(format: "#%02x%02x%02x", b.r, b.g, b.b)
    }

    /// Hue 0–360, saturation and lightness 0–1.
    var hsl: (h: Double, s: Double, l: Double) {
        let maxV = max(red, green, blue)
        let minV = min(red, green, blue)
        let delta = maxV - minV
        let l = (maxV + minV) / 2

        guard delta > 0 else { return (0, 0, l) }

        let s = delta / (1 - abs(2 * l - 1))
        var h: Double
        switch maxV {
        case red:   h = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: h = ((blue - red) / delta) + 2
        default:    h = ((red - green) / delta) + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }
}

// MARK: - CMYK

extension Swatch {
    /// Converted through ColorSync using the Generic CMYK profile. That is a
    /// real colorimetric conversion, not the naive 1-max(r,g,b) formula — but
    /// it is *not* your press profile. Check against the actual output profile
    /// before sending anything to print.
    var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        if let converted = nsColor.usingColorSpace(.genericCMYK) {
            return (Double(converted.cyanComponent),
                    Double(converted.magentaComponent),
                    Double(converted.yellowComponent),
                    Double(converted.blackComponent))
        }
        let k = 1 - max(red, green, blue)
        guard k < 1 else { return (0, 0, 0, 1) }
        return ((1 - red - k) / (1 - k),
                (1 - green - k) / (1 - k),
                (1 - blue - k) / (1 - k),
                k)
    }
}

// MARK: - CIELAB and ΔE2000

extension Swatch {
    /// CIELAB under a D65 white point, matching sRGB's own reference white.
    var lab: (L: Double, a: Double, b: Double) {
        func linear(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), bl = linear(blue)

        let x = (r * 0.4124564 + g * 0.3575761 + bl * 0.1804375) / 0.95047
        let y = (r * 0.2126729 + g * 0.7151522 + bl * 0.0721750)
        let z = (r * 0.0193339 + g * 0.1191920 + bl * 0.9503041) / 1.08883

        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Gamma-encoded sRGB for a Lab colour, deliberately NOT clamped — callers
    /// doing gamut mapping need to see that a value fell outside 0...1.
    static func srgbComponents(L: Double, a: Double, b: Double)
        -> (r: Double, g: Double, b: Double) {
        let fy = (L + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200

        func finv(_ t: Double) -> Double {
            let cubed = t * t * t
            return cubed > 0.008856 ? cubed : (t - 16.0 / 116.0) / 7.787
        }
        let x = 0.95047 * finv(fx)
        let y = finv(fy)
        let z = 1.08883 * finv(fz)

        func gamma(_ v: Double) -> Double {
            v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return (gamma(x * 3.2404542 + y * -1.5371385 + z * -0.4985314),
                gamma(x * -0.9692660 + y * 1.8760108 + z * 0.0415560),
                gamma(x * 0.0556434 + y * -0.2040259 + z * 1.0572252))
    }

    /// Builds a swatch from CIELAB — used when a palette file stores Lab,
    /// which Pantone books normally do.
    static func fromLab(L: Double, a: Double, b: Double) -> Swatch {
        let c = srgbComponents(L: L, a: a, b: b)
        func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
        return Swatch(red: clamp(c.r), green: clamp(c.g), blue: clamp(c.b))
    }

    /// CIEDE2000. Roughly: under 1.0 is imperceptible, under 2.0 is a close
    /// match, over 5.0 is a visibly different color.
    func deltaE(to other: Swatch) -> Double {
        Swatch.deltaE2000(lab, other.lab)
    }

    /// Takes Lab directly so callers matching against a large book can convert
    /// each entry once instead of on every comparison.
    static func deltaE2000(_ l1: (L: Double, a: Double, b: Double),
                           _ l2: (L: Double, a: Double, b: Double)) -> Double {
        let kL = 1.0, kC = 1.0, kH = 1.0
        let deg = Double.pi / 180

        let c1 = sqrt(l1.a * l1.a + l1.b * l1.b)
        let c2 = sqrt(l2.a * l2.a + l2.b * l2.b)
        let cBar = (c1 + c2) / 2
        let cBar7 = pow(cBar, 7)
        let g = 0.5 * (1 - sqrt(cBar7 / (cBar7 + pow(25.0, 7))))

        let a1p = (1 + g) * l1.a
        let a2p = (1 + g) * l2.a
        let c1p = sqrt(a1p * a1p + l1.b * l1.b)
        let c2p = sqrt(a2p * a2p + l2.b * l2.b)

        func hue(_ ap: Double, _ bp: Double) -> Double {
            if ap == 0 && bp == 0 { return 0 }
            var h = atan2(bp, ap) / deg
            if h < 0 { h += 360 }
            return h
        }
        let h1p = hue(a1p, l1.b)
        let h2p = hue(a2p, l2.b)

        let dLp = l2.L - l1.L
        let dCp = c2p - c1p

        var dhp = 0.0
        if c1p * c2p != 0 {
            dhp = h2p - h1p
            if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        }
        let dHp = 2 * sqrt(c1p * c2p) * sin(dhp * deg / 2)

        let lBarP = (l1.L + l2.L) / 2
        let cBarP = (c1p + c2p) / 2

        var hBarP: Double
        if c1p * c2p == 0 {
            hBarP = h1p + h2p
        } else if abs(h1p - h2p) <= 180 {
            hBarP = (h1p + h2p) / 2
        } else if h1p + h2p < 360 {
            hBarP = (h1p + h2p + 360) / 2
        } else {
            hBarP = (h1p + h2p - 360) / 2
        }

        let t = 1
            - 0.17 * cos((hBarP - 30) * deg)
            + 0.24 * cos((2 * hBarP) * deg)
            + 0.32 * cos((3 * hBarP + 6) * deg)
            - 0.20 * cos((4 * hBarP - 63) * deg)

        let dTheta = 30 * exp(-pow((hBarP - 275) / 25, 2))
        let cBarP7 = pow(cBarP, 7)
        let rC = 2 * sqrt(cBarP7 / (cBarP7 + pow(25.0, 7)))

        let sL = 1 + (0.015 * pow(lBarP - 50, 2)) / sqrt(20 + pow(lBarP - 50, 2))
        let sC = 1 + 0.045 * cBarP
        let sH = 1 + 0.015 * cBarP * t
        let rT = -sin(2 * dTheta * deg) * rC

        let termL = dLp / (kL * sL)
        let termC = dCp / (kC * sC)
        let termH = dHp / (kH * sH)

        return sqrt(termL * termL + termC * termC + termH * termH
                    + rT * termC * termH)
    }
}

// MARK: - Contrast (WCAG 2.1)

extension Swatch {
    var relativeLuminance: Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrast(against other: Swatch) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    var contrastOnWhite: Double { (1.05) / (relativeLuminance + 0.05) }
    var contrastOnBlack: Double { (relativeLuminance + 0.05) / 0.05 }

    /// The WCAG grade this ratio earns for normal body text.
    static func grade(_ ratio: Double) -> String {
        switch ratio {
        case 7...:   return "AAA"
        case 4.5...: return "AA"
        case 3...:   return "AA Large"
        default:     return "Fail"
        }
    }
}

// MARK: - Output formats

enum ColorFormat: String, CaseIterable, Codable, Identifiable {
    case hex
    case hexUppercase
    case rgb
    case rgba
    case hsl
    case cmyk
    case swiftUI
    case nsColor
    case uiColor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hex:          return "Hex"
        case .hexUppercase: return "Hex (uppercase)"
        case .rgb:          return "RGB"
        case .rgba:         return "RGBA"
        case .hsl:          return "HSL"
        case .cmyk:         return "CMYK"
        case .swiftUI:      return "SwiftUI Color"
        case .nsColor:      return "NSColor"
        case .uiColor:      return "UIColor"
        }
    }

    func string(for s: Swatch) -> String {
        let b = s.bytes
        func f(_ v: Double) -> String { String(format: "%.3f", v) }

        switch self {
        case .hex:
            return s.hex
        case .hexUppercase:
            return s.hex.uppercased()
        case .rgb:
            return "rgb(\(b.r), \(b.g), \(b.b))"
        case .rgba:
            return "rgba(\(b.r), \(b.g), \(b.b), \(f(s.alpha)))"
        case .hsl:
            let c = s.hsl
            return "hsl(\(Int(c.h.rounded())), \(Int((c.s * 100).rounded()))%, \(Int((c.l * 100).rounded()))%)"
        case .cmyk:
            let k = s.cmyk
            return "cmyk(\(Int((k.c * 100).rounded()))%, \(Int((k.m * 100).rounded()))%, \(Int((k.y * 100).rounded()))%, \(Int((k.k * 100).rounded()))%)"
        case .swiftUI:
            return "Color(red: \(f(s.red)), green: \(f(s.green)), blue: \(f(s.blue)))"
        case .nsColor:
            return "NSColor(srgbRed: \(f(s.red)), green: \(f(s.green)), blue: \(f(s.blue)), alpha: \(f(s.alpha)))"
        case .uiColor:
            return "UIColor(red: \(f(s.red)), green: \(f(s.green)), blue: \(f(s.blue)), alpha: \(f(s.alpha)))"
        }
    }
}
