import AppKit
import Foundation

// MARK: - LCh

extension Swatch {
    /// Lab in polar form: lightness, chroma, hue angle. Rotating `h` here keeps
    /// perceived lightness and colourfulness fixed, which HSL rotation does not
    /// — an HSL "complement" of a yellow reads far brighter than the original.
    var lch: (L: Double, C: Double, h: Double) {
        let l = lab
        let chroma = sqrt(l.a * l.a + l.b * l.b)
        var hue = atan2(l.b, l.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (l.L, chroma, hue)
    }

    /// Builds a swatch from LCh, pulling chroma in until the colour fits in
    /// sRGB. Clamping the channels instead would shift the hue, which defeats
    /// the point of rotating in LCh to begin with.
    static func fromLCh(L: Double, C: Double, h: Double) -> Swatch {
        let radians = h * .pi / 180
        var chroma = max(0, C)

        for _ in 0..<28 {
            let a = chroma * cos(radians)
            let b = chroma * sin(radians)
            let rgb = srgbComponents(L: L, a: a, b: b)

            let tolerance = 0.002
            let fits = rgb.r >= -tolerance && rgb.r <= 1 + tolerance
                && rgb.g >= -tolerance && rgb.g <= 1 + tolerance
                && rgb.b >= -tolerance && rgb.b <= 1 + tolerance

            if fits || chroma < 0.01 {
                return fromLab(L: L, a: a, b: b)
            }
            chroma *= 0.93
        }
        return fromLab(L: L, a: 0, b: 0)
    }

    func rotated(by degrees: Double) -> Swatch {
        let c = lch
        return Swatch.fromLCh(L: c.L,
                              C: c.C,
                              h: (c.h + degrees).truncatingRemainder(dividingBy: 360))
    }
}

// MARK: - Adjustments

extension Swatch {
    /// Tint and shade. Positive `amount` (0…1) mixes toward white, negative
    /// toward black — a straight sRGB mix, which is what Sass `tint()`/`shade()`
    /// and most design tools mean by the term, so results line up with them.
    func tinted(by amount: Double) -> Swatch {
        let t = min(max(amount, -1), 1)
        let target: Double = t >= 0 ? 1 : 0
        let k = abs(t)
        func mix(_ v: Double) -> Double { v + (target - v) * k }
        var out = Swatch(red: mix(red), green: mix(green), blue: mix(blue))
        out.alpha = alpha
        return out
    }

    /// Scales LCh chroma by `1 + amount` (amount −1…1), holding perceived
    /// lightness and hue fixed. −1 gives the matching neutral grey; boosts are
    /// gamut-mapped by `fromLCh`, so they stop at the most vivid sRGB value
    /// instead of clipping a channel and shifting the hue.
    func saturated(by amount: Double) -> Swatch {
        let t = min(max(amount, -1), 1)
        let c = lch
        var out = Swatch.fromLCh(L: c.L, C: c.C * (1 + t), h: c.h)
        out.alpha = alpha
        return out
    }

    /// Saturation first, then tint, so the tint slider always ends exactly at
    /// white or black no matter how saturation is set.
    func adjusted(tint: Double, saturation: Double) -> Swatch {
        var out = self
        if saturation != 0 { out = out.saturated(by: saturation) }
        if tint != 0 { out = out.tinted(by: tint) }
        return out
    }
}

// MARK: - Harmonies

enum Harmony: String, CaseIterable, Identifiable {
    case complement
    case splitComplement
    case analogous
    case triad
    case tetrad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .complement:      return "complement"
        case .splitComplement: return "split"
        case .analogous:       return "analogous"
        case .triad:           return "triad"
        case .tetrad:          return "tetrad"
        }
    }

    /// Hue offsets in degrees, excluding the source colour itself.
    var offsets: [Double] {
        switch self {
        case .complement:      return [180]
        case .splitComplement: return [150, 210]
        case .analogous:       return [-30, 30]
        case .triad:           return [120, 240]
        case .tetrad:          return [90, 180, 270]
        }
    }
}

enum Pairings {

    /// The source colour first, then its partners.
    static func set(_ harmony: Harmony, from swatch: Swatch) -> [Swatch] {
        [swatch] + harmony.offsets.map { swatch.rotated(by: $0) }
    }

    /// A tone ramp at the source hue. Chroma tapers toward the light and dark
    /// ends — holding it flat makes the extremes look artificially neon, which
    /// is not how a hand-built ramp behaves.
    static func ramp(from swatch: Swatch, steps: Int = 9) -> [Swatch] {
        guard steps > 1 else { return [swatch] }
        let source = swatch.lch

        return (0..<steps).map { index in
            let t = Double(index) / Double(steps - 1)
            let lightness = 95 - t * 80
            let distance = abs((lightness - 55) / 45)
            let taper = 1 - pow(min(distance, 1), 1.8) * 0.5
            return Swatch.fromLCh(L: lightness,
                                  C: source.C * taper,
                                  h: source.h)
        }
    }
}
