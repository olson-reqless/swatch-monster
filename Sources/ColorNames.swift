import AppKit
import Combine
import Foundation

struct NamedColor: Identifiable {
    let id = UUID()
    let name: String
    let swatch: Swatch
    let deltaE: Double
}

/// Human-readable color names from meodai/color-names (MIT, © 2017 David Aerne),
/// the same list colornamer.robertcooper.me uses. Bundled as `colornames.csv`.
///
/// Kept separate from `PaletteLibrary` on purpose: these are evocative names, not
/// print references, and the two should never be mistaken for each other.
final class ColorNames: ObservableObject {
    static let shared = ColorNames()

    /// Published so the panel refreshes once the list finishes loading.
    @Published private(set) var count = 0

    private struct Entry {
        let name: String
        let swatch: Swatch
        let lab: (L: Double, a: Double, b: Double)
    }

    private var entries: [Entry] = []
    private var cache: [String: [NamedColor]] = [:]
    private var isLoading = false

    private init() {}

    /// 32k Lab conversions is too much for a menu-bar click, so it happens once
    /// off the main thread and the panel picks it up when it lands.
    func loadIfNeeded() {
        guard entries.isEmpty, !isLoading else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var parsed: [Entry] = []
            if let url = Bundle.main.url(forResource: "colornames", withExtension: "csv"),
               let data = try? Data(contentsOf: url) {
                // The CSV's "name,hex" header fails hex parsing and is skipped.
                parsed = PaletteLibrary.parseCSV(data).map {
                    Entry(name: $0.0, swatch: $0.1, lab: $0.1.lab)
                }
            } else {
                NSLog("Swatch Monster: colornames.csv missing from the bundle")
            }

            DispatchQueue.main.async {
                self.entries = parsed
                self.isLoading = false
                self.count = parsed.count
            }
        }
    }

    func nearest(to swatch: Swatch, limit: Int = 3) -> [NamedColor] {
        guard !entries.isEmpty else { return [] }

        let key = "\(swatch.hex)|\(limit)"
        if let cached = cache[key] { return cached }

        let target = swatch.lab

        // Partial selection rather than a full sort — 32k entries for a top 3.
        var best: [(index: Int, deltaE: Double)] = []
        var worstKept = Double.greatestFiniteMagnitude

        for (index, entry) in entries.enumerated() {
            let distance = Swatch.deltaE2000(target, entry.lab)
            if best.count < limit {
                best.append((index, distance))
                best.sort { $0.deltaE < $1.deltaE }
                worstKept = best[best.count - 1].deltaE
            } else if distance < worstKept {
                best[best.count - 1] = (index, distance)
                best.sort { $0.deltaE < $1.deltaE }
                worstKept = best[best.count - 1].deltaE
            }
        }

        let result = best.map {
            NamedColor(name: entries[$0.index].name,
                       swatch: entries[$0.index].swatch,
                       deltaE: $0.deltaE)
        }
        cache[key] = result
        return result
    }
}
