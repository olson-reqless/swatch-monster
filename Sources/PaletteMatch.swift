import AppKit
import Combine
import Foundation

// MARK: - Entries

struct PaletteEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let paletteName: String
    let swatch: Swatch
    /// Converted once at load time; a book can hold thousands of entries.
    let lab: (L: Double, a: Double, b: Double)

    init(name: String, paletteName: String, swatch: Swatch) {
        self.name = name
        self.paletteName = paletteName
        self.swatch = swatch
        self.lab = swatch.lab
    }

    static func == (lhs: PaletteEntry, rhs: PaletteEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PaletteMatch: Identifiable {
    var id: UUID { entry.id }
    let entry: PaletteEntry
    let deltaE: Double

    /// Plain-English reading of a ΔE2000 figure.
    var quality: String {
        switch deltaE {
        case ..<1:  return "exact"
        case ..<2:  return "very close"
        case ..<5:  return "close"
        case ..<10: return "loose"
        default:    return "poor"
        }
    }
}

// MARK: - Library

/// Loads swatch books from Application Support and finds the nearest named
/// color to a picked one. Ships with no color data of its own — see
/// `Palettes/README.txt`, written on first launch.
final class PaletteLibrary: ObservableObject {
    static let shared = PaletteLibrary()

    @Published private(set) var entries: [PaletteEntry] = []
    @Published private(set) var loadedPalettes: [String] = []

    private init() {
        reload()
    }

    var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Swatch Monster", isDirectory: true)
            .appendingPathComponent("Palettes", isDirectory: true)
    }

    func reload() {
        let fm = FileManager.default
        let folder = folderURL

        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        // Written whenever it's absent, not only when the folder is new, so a
        // deleted or outdated copy comes back.
        let readme = folder.appendingPathComponent("README.txt")
        if !fm.fileExists(atPath: readme.path) {
            writeReadme(in: folder)
        }

        var found: [PaletteEntry] = []
        var names: [String] = []

        let files = (try? fm.contentsOfDirectory(at: folder,
                                                 includingPropertiesForKeys: nil)) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let palette = url.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: url) else { continue }

            let parsed: [(String, Swatch)]
            switch url.pathExtension.lowercased() {
            case "ase": parsed = PaletteLibrary.parseASE(data)
            case "acb": parsed = PaletteLibrary.parseACB(data)
            case "csv": parsed = PaletteLibrary.parseCSV(data)
            default: continue
            }

            guard !parsed.isEmpty else { continue }
            names.append("\(palette) (\(parsed.count))")
            found.append(contentsOf: parsed.map {
                PaletteEntry(name: $0.0, paletteName: palette, swatch: $0.1)
            })
        }

        matchCache.removeAll()
        entries = found
        loadedPalettes = names
    }

    private var matchCache: [String: [PaletteMatch]] = [:]

    func nearest(to swatch: Swatch, limit: Int = 3) -> [PaletteMatch] {
        guard !entries.isEmpty else { return [] }

        let key = "\(swatch.hex)|\(limit)"
        if let cached = matchCache[key] { return cached }

        let target = swatch.lab
        let result = entries
            .map { PaletteMatch(entry: $0, deltaE: Swatch.deltaE2000(target, $0.lab)) }
            .sorted { $0.deltaE < $1.deltaE }
            .prefix(limit)
            .map { $0 }

        matchCache[key] = result
        return result
    }

    /// Copies the color books already installed by Adobe apps on this Mac into
    /// the palettes folder. Those are licensed to you as part of the Adobe
    /// install; nothing is downloaded and nothing is redistributed.
    @discardableResult
    func importAdobeBooks() -> Int {
        let fm = FileManager.default
        var sources = ["/Library/Application Support/Adobe/Color/Books"]

        let apps = (try? fm.contentsOfDirectory(atPath: "/Applications")) ?? []
        for app in apps where app.hasPrefix("Adobe") {
            sources.append("/Applications/\(app)/Presets/Color Books")
            sources.append("/Applications/\(app)/Presets.localized/en_US/Swatches/Color Books")
        }

        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var copied = 0
        for source in sources {
            let files = (try? fm.contentsOfDirectory(atPath: source)) ?? []
            for file in files where file.lowercased().hasSuffix(".acb") {
                let destination = folderURL.appendingPathComponent(file)
                guard !fm.fileExists(atPath: destination.path) else { continue }
                let origin = URL(fileURLWithPath: source).appendingPathComponent(file)
                if (try? fm.copyItem(at: origin, to: destination)) != nil { copied += 1 }
            }
        }

        reload()
        return copied
    }

    private func writeReadme(in folder: URL) {
        let text = """
        Swatch Monster — Palettes
        =========================

        Drop swatch books in this folder and Swatch Monster will name the
        nearest color to whatever you pick, scored with CIEDE2000.

        Supported files
        ---------------
          .acb   Adobe Color Book — the format Illustrator and Photoshop use
                 for their built-in Pantone books.
          .ase   Adobe Swatch Exchange — export from Illustrator via the
                 Swatches panel menu > Save Swatch Library as ASE.
          .csv   Two columns, no header:  name,hex     e.g.  Ocean Blue,#2b6cb0

        About Pantone
        -------------
        Swatch Monster ships with no Pantone data. Pantone's libraries are
        licensed, not public, so this app cannot redistribute them.

        Adobe also removed its bundled Pantone books from Creative Cloud in
        2022, so they are most likely not on this Mac either. To match against
        Pantone you have to supply the data from a source you are licensed
        for. Any of these work:

          - Pantone Connect (Adobe plugin or web app) — export swatches
            and save them as .ase.
          - An older pre-2022 Adobe install — copy its PANTONE*.acb files.
          - A physical guide plus a hand-built .csv.

        What does work immediately are the books Adobe still ships. Settings >
        Palettes > Import Adobe Books pulls in TRUMATCH, TOYO, DIC, HKS,
        FOCOLTONE and ANPA in one click.

        Matching is colorimetric, against sRGB values. Treat it as a starting
        point for specification, never as a substitute for a physical guide
        under controlled lighting.
        """
        try? text.write(to: folder.appendingPathComponent("README.txt"),
                        atomically: true, encoding: .utf8)
    }
}

// MARK: - Parsers

private struct ByteReader {
    let data: Data
    var offset = 0

    var remaining: Int { data.count - offset }

    mutating func uint8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func uint16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return (b0 << 8) | b1
    }

    mutating func uint32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value = (value << 8) | UInt32(data[data.startIndex + offset + i])
        }
        offset += 4
        return value
    }

    mutating func float32() -> Float? {
        guard let bits = uint32() else { return nil }
        return Float(bitPattern: bits)
    }

    mutating func ascii(_ count: Int) -> String? {
        guard remaining >= count else { return nil }
        let range = (data.startIndex + offset)..<(data.startIndex + offset + count)
        offset += count
        return String(data: data[range], encoding: .ascii)
    }

    /// UTF-16 big-endian run of `count` code units, trailing NUL trimmed.
    mutating func utf16BE(_ count: Int) -> String? {
        let bytes = count * 2
        guard remaining >= bytes else { return nil }
        let range = (data.startIndex + offset)..<(data.startIndex + offset + bytes)
        offset += bytes
        let string = String(data: data[range], encoding: .utf16BigEndian)
        return string?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .trimmingCharacters(in: .whitespaces)
    }

    mutating func skip(_ count: Int) { offset = min(offset + count, data.count) }
}

extension PaletteLibrary {

    // MARK: CSV

    static func parseCSV(_ data: Data) -> [(String, Swatch)] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [(String, Swatch)] = []

        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            guard let swatch = swatchFromHex(parts[1]) else { continue }
            out.append((parts[0], swatch))
        }
        return out
    }

    static func swatchFromHex(_ raw: String) -> Swatch? {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Swatch(red: Double((value >> 16) & 0xFF) / 255,
                      green: Double((value >> 8) & 0xFF) / 255,
                      blue: Double(value & 0xFF) / 255)
    }

    // MARK: ASE (Adobe Swatch Exchange)

    static func parseASE(_ data: Data) -> [(String, Swatch)] {
        var reader = ByteReader(data: data)
        guard reader.ascii(4) == "ASEF" else { return [] }
        reader.skip(4) // version major/minor
        guard let blockCount = reader.uint32() else { return [] }

        var out: [(String, Swatch)] = []

        for _ in 0..<blockCount {
            guard let type = reader.uint16(), let length = reader.uint32() else { break }
            let blockEnd = reader.offset + Int(length)

            // 0x0001 is a color entry; 0xC001/0xC002 are group markers.
            if type == 0x0001 {
                if let nameLength = reader.uint16(),
                   let name = reader.utf16BE(Int(nameLength)),
                   let model = reader.ascii(4),
                   let swatch = readColor(model: model, reader: &reader),
                   !name.isEmpty {
                    out.append((name, swatch))
                }
            }

            reader.offset = min(blockEnd, data.count)
        }
        return out
    }

    private static func readColor(model: String, reader: inout ByteReader) -> Swatch? {
        switch model.trimmingCharacters(in: .whitespaces) {
        case "RGB":
            guard let r = reader.float32(), let g = reader.float32(),
                  let b = reader.float32() else { return nil }
            return Swatch(red: Double(r), green: Double(g), blue: Double(b))

        case "CMYK":
            guard let c = reader.float32(), let m = reader.float32(),
                  let y = reader.float32(), let k = reader.float32() else { return nil }
            let color = NSColor(deviceCyan: CGFloat(c), magenta: CGFloat(m),
                                yellow: CGFloat(y), black: CGFloat(k), alpha: 1)
            return Swatch(color: color.usingColorSpace(.sRGB) ?? color)

        case "LAB":
            guard let l = reader.float32(), let a = reader.float32(),
                  let b = reader.float32() else { return nil }
            // ASE stores L as 0–1.
            return Swatch.fromLab(L: Double(l) * 100, a: Double(a), b: Double(b))

        case "Gray":
            guard let g = reader.float32() else { return nil }
            return Swatch(red: Double(g), green: Double(g), blue: Double(g))

        default:
            return nil
        }
    }

    // MARK: ACB (Adobe Color Book)

    /// Adobe stores book names as ZStrings — `$$$/colorbook/HKSK/postfix= K`,
    /// where everything after the first `=` is the fallback text we want.
    static func resolveZString(_ raw: String) -> String {
        guard raw.hasPrefix("$$$/"), let equals = raw.firstIndex(of: "=") else {
            return raw
        }
        return String(raw[raw.index(after: equals)...])
    }

    static func parseACB(_ data: Data) -> [(String, Swatch)] {
        var reader = ByteReader(data: data)
        guard reader.ascii(4) == "8BCB" else { return [] }
        reader.skip(2) // version
        reader.skip(2) // book identifier

        // title, prefix, suffix, description
        var prefix = "", suffix = ""
        for index in 0..<4 {
            guard let length = reader.uint32(),
                  let string = reader.utf16BE(Int(length)) else { return [] }
            if index == 1 { prefix = resolveZString(string) }
            if index == 2 { suffix = resolveZString(string) }
        }

        guard let colorCount = reader.uint16() else { return [] }
        reader.skip(2) // page size
        reader.skip(2) // page selector offset
        guard let colorSpace = reader.uint16() else { return [] }

        var out: [(String, Swatch)] = []

        for _ in 0..<colorCount {
            guard let nameLength = reader.uint32(),
                  let rawName = reader.utf16BE(Int(nameLength)),
                  let code = reader.ascii(6) else { break }

            let swatch: Swatch?
            switch colorSpace {
            case 0: // RGB, one byte per channel
                guard let r = reader.uint8(), let g = reader.uint8(),
                      let b = reader.uint8() else { return out }
                swatch = Swatch(red: Double(r) / 255,
                                green: Double(g) / 255,
                                blue: Double(b) / 255)

            case 2: // CMYK, stored inverted
                guard let c = reader.uint8(), let m = reader.uint8(),
                      let y = reader.uint8(), let k = reader.uint8() else { return out }
                let color = NSColor(deviceCyan: CGFloat(255 - c) / 255,
                                    magenta: CGFloat(255 - m) / 255,
                                    yellow: CGFloat(255 - y) / 255,
                                    black: CGFloat(255 - k) / 255,
                                    alpha: 1)
                swatch = Swatch(color: color.usingColorSpace(.sRGB) ?? color)

            case 7: // Lab
                guard let l = reader.uint8(), let a = reader.uint8(),
                      let b = reader.uint8() else { return out }
                swatch = Swatch.fromLab(L: Double(l) * 100 / 255,
                                        a: Double(Int(a) - 128),
                                        b: Double(Int(b) - 128))

            default:
                return out
            }

            guard let swatch else { continue }
            let full = (prefix + resolveZString(rawName) + suffix)
                .trimmingCharacters(in: .whitespaces)
            let display = full.isEmpty
                ? code.trimmingCharacters(in: .whitespaces)
                : full
            out.append((display, swatch))
        }

        return out
    }
}
