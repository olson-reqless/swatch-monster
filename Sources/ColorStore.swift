import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class ColorStore: ObservableObject {
    static let shared = ColorStore()

    @Published private(set) var history: [Swatch] = []
    @Published private(set) var favorites: [Swatch] = []
    @Published private(set) var lastCopied: String = ""

    /// A chip the user clicked, which the panel shows in place of the newest
    /// color. Cleared by the next pick so a fresh pick always wins.
    @Published private(set) var focused: Swatch?

    @Published var format: ColorFormat = .hex { didSet { persist() } }
    @Published var copyOnPick: Bool = true { didSet { persist() } }
    @Published var keepPickingUntilEscape: Bool = false { didSet { persist() } }

    /// Screen points per captured pixel in the loupe.
    @Published var loupeZoom: CGFloat = 8 { didSet { persist() } }
    /// Zoom used while Control is held.
    @Published var loupePreciseZoom: CGFloat = 24 { didSet { persist() } }
    /// Fall back to Apple's loupe (no zoom control, no permission needed).
    @Published var useSystemPicker: Bool = false { didSet { persist() } }
    /// Whether the pairings section in the panel is expanded.
    @Published var showPairings: Bool = true { didSet { persist() } }

    @Published var launchAtLogin: Bool = false {
        didSet {
            guard oldValue != launchAtLogin else { return }
            applyLaunchAtLogin()
        }
    }

    private let historyLimit = 48
    private let defaults = UserDefaults.standard

    private enum Key {
        static let history = "history"
        static let favorites = "favorites"
        static let format = "format"
        static let copyOnPick = "copyOnPick"
        static let keepPicking = "keepPickingUntilEscape"
        static let loupeZoom = "loupeZoom"
        static let loupePreciseZoom = "loupePreciseZoom"
        static let useSystemPicker = "useSystemPicker"
        static let showPairings = "showPairings"
    }

    private init() {
        load()
    }

    // MARK: - Picking

    var mostRecent: Swatch? { history.first }

    /// The color the panel should feature: a clicked chip, else the newest pick.
    var featured: Swatch? { focused.map { current($0) } ?? mostRecent }

    func focus(_ swatch: Swatch?) {
        focused = swatch
    }

    func record(_ color: NSColor) {
        let swatch = Swatch(color: color)

        // A new pick takes over the hero slot.
        focused = nil

        // Re-picking a color promotes it rather than duplicating it.
        history.removeAll { $0.hex == swatch.hex }
        history.insert(swatch, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }

        if copyOnPick { copy(swatch) }
        persist()
    }

    /// Saves an adjusted variant as its own history entry, leaving the source
    /// color untouched. Returns the stored swatch so the caller can select it.
    @discardableResult
    func addAdjusted(_ swatch: Swatch) -> Swatch {
        var fresh = swatch
        fresh.id = UUID()
        fresh.pickedAt = Date()
        fresh.name = nil

        history.removeAll { $0.hex == fresh.hex }
        history.insert(fresh, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
        persist()
        return fresh
    }

    // MARK: - Clipboard

    @discardableResult
    func copy(_ swatch: Swatch, as format: ColorFormat? = nil) -> String {
        let text = (format ?? self.format).string(for: swatch)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastCopied = text
        return text
    }

    // MARK: - Favorites

    func isFavorite(_ swatch: Swatch) -> Bool {
        favorites.contains { $0.hex == swatch.hex }
    }

    func toggleFavorite(_ swatch: Swatch) {
        if let index = favorites.firstIndex(where: { $0.hex == swatch.hex }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(swatch, at: 0)
        }
        persist()
    }

    // MARK: - Naming

    func name(for swatch: Swatch) -> String? {
        history.first { $0.id == swatch.id }?.name
            ?? favorites.first { $0.hex == swatch.hex }?.name
    }

    /// Keeps the label in step across history and pinned copies of one color.
    func rename(_ swatch: Swatch, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed

        if let index = history.firstIndex(where: { $0.id == swatch.id }) {
            history[index].name = value
        }
        if let index = favorites.firstIndex(where: { $0.hex == swatch.hex }) {
            favorites[index].name = value
        }
        persist()
    }

    /// The stored version of a swatch, so views don't render a stale copy.
    func current(_ swatch: Swatch) -> Swatch {
        history.first { $0.id == swatch.id }
            ?? favorites.first { $0.hex == swatch.hex }
            ?? swatch
    }

    func removeFromHistory(_ swatch: Swatch) {
        if focused?.id == swatch.id { focused = nil }
        history.removeAll { $0.id == swatch.id }
        persist()
    }

    func clearHistory() {
        focused = nil
        history.removeAll()
        persist()
    }

    // MARK: - Login item

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Swatch Monster: launch at login failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Key.history),
           let saved = try? decoder.decode([Swatch].self, from: data) {
            history = saved
        }
        if let data = defaults.data(forKey: Key.favorites),
           let saved = try? decoder.decode([Swatch].self, from: data) {
            favorites = saved
        }
        if let raw = defaults.string(forKey: Key.format),
           let saved = ColorFormat(rawValue: raw) {
            format = saved
        }
        copyOnPick = defaults.object(forKey: Key.copyOnPick) as? Bool ?? true
        keepPickingUntilEscape = defaults.bool(forKey: Key.keepPicking)
        loupeZoom = CGFloat(defaults.object(forKey: Key.loupeZoom) as? Double ?? 8)
        loupePreciseZoom = CGFloat(defaults.object(forKey: Key.loupePreciseZoom) as? Double ?? 24)
        useSystemPicker = defaults.bool(forKey: Key.useSystemPicker)
        showPairings = defaults.object(forKey: Key.showPairings) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: Key.history)
        }
        if let data = try? encoder.encode(favorites) {
            defaults.set(data, forKey: Key.favorites)
        }
        defaults.set(format.rawValue, forKey: Key.format)
        defaults.set(copyOnPick, forKey: Key.copyOnPick)
        defaults.set(keepPickingUntilEscape, forKey: Key.keepPicking)
        defaults.set(Double(loupeZoom), forKey: Key.loupeZoom)
        defaults.set(Double(loupePreciseZoom), forKey: Key.loupePreciseZoom)
        defaults.set(useSystemPicker, forKey: Key.useSystemPicker)
        defaults.set(showPairings, forKey: Key.showPairings)
    }
}
