import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The ⌃⌥⌘X window: every saved color, and every format for the selected one.
struct LibraryView: View {
    @EnvironmentObject var store: ColorStore
    @ObservedObject private var palettes = PaletteLibrary.shared
    @State private var tab = 0
    @State private var selected: Swatch?
    /// −1…1. Positive tints toward white, negative shades toward black.
    @State private var tint: Double = 0
    /// −1…1. Scales LCh chroma; −1 is fully desaturated.
    @State private var saturation: Double = 0

    /// Resolved against the store each render so a rename shows immediately.
    private var active: Swatch? {
        guard let selected else { return store.mostRecent }
        return store.current(selected)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Colors").tag(0)
                Text("Settings").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(12)

            Divider()

            if tab == 0 {
                colorsTab
            } else {
                SettingsView()
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        // Sliders belong to the color they were moved on; a new selection
        // starts from zero rather than inheriting someone else's adjustment.
        .onChange(of: active?.id) { resetAdjustments() }
    }

    private var colorsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let swatch = active {
                    detail(swatch)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "eyedropper.halffull")
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                        Text("No colors yet")
                            .font(.headline)
                        Text("Press ⌃⌥⌘C anywhere to pick one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }

                if !store.favorites.isEmpty {
                    grid("Pinned", store.favorites)
                }
                if !store.history.isEmpty {
                    grid("History", store.history)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Detail

    private func detail(_ swatch: Swatch) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(swatch.color)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                Text(swatch.hex.uppercased())
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(swatch.relativeLuminance < 0.4 ? Color.white : Color.black)
                    .padding(18)
            }
            .frame(height: 132)

            HStack(spacing: 10) {
                ratio("on white", swatch.contrastOnWhite)
                ratio("on black", swatch.contrastOnBlack)
                Spacer()
                Button(store.isFavorite(swatch) ? "Unpin" : "Pin") {
                    store.toggleFavorite(swatch)
                }
            }

            HStack(spacing: 8) {
                TextField("Name (optional)", text: nameBinding(for: swatch))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 210)

                Spacer()

                Button {
                    SwatchCard.copyToClipboard(swatch)
                } label: {
                    Label("Copy Card", systemImage: "doc.on.doc")
                }
                .help("Copy the card as a PNG image")

                Menu("Export Card…") {
                    Button("PNG…") { SwatchCard.export(swatch, as: .png) }
                    Button("PDF…") { SwatchCard.export(swatch, as: .pdf) }
                }
                .fixedSize()
            }

            adjust(swatch)

            if !palettes.entries.isEmpty {
                matches(for: swatch)
            }

            VStack(spacing: 0) {
                ForEach(Array(ColorFormat.allCases.enumerated()), id: \.element) { index, format in
                    HStack(spacing: 10) {
                        Text(format.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 128, alignment: .leading)
                        Text(format.string(for: swatch))
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            store.copy(swatch, as: format)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Adjust

    private var isAdjusted: Bool { tint != 0 || saturation != 0 }

    private func resetAdjustments() {
        tint = 0
        saturation = 0
    }

    private func adjust(_ swatch: Swatch) -> some View {
        let result = swatch.adjusted(tint: tint, saturation: saturation)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ADJUST")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                if isAdjusted {
                    Button("Reset", action: resetAdjustments)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            // Before / after, side by side.
            HStack(spacing: 0) {
                Rectangle().fill(swatch.color)
                Rectangle().fill(result.color)
                    .overlay(alignment: .bottomTrailing) {
                        Text(result.hex.uppercased())
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(result.relativeLuminance < 0.4 ? Color.white : Color.black)
                            .padding(8)
                    }
            }
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            slider("Tint", value: $tint,
                   minLabel: "shade", maxLabel: "tint")
            slider("Saturation", value: $saturation,
                   minLabel: "grey", maxLabel: "vivid")

            HStack(spacing: 8) {
                Spacer()
                Button {
                    store.copy(result)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy the adjusted color in your default format")

                Button {
                    let saved = store.addAdjusted(result)
                    selected = saved
                } label: {
                    Label("Save as New Color", systemImage: "plus")
                }
                .help("Add the adjusted color to History; the original stays as it is")
            }
            .disabled(!isAdjusted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func slider(_ title: String, value: Binding<Double>,
                        minLabel: String, maxLabel: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(signedPercent(value.wrappedValue))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: -1...1, step: 0.01) {
                Text(title)
            } minimumValueLabel: {
                Text(minLabel).font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(maxLabel).font(.caption2).foregroundStyle(.secondary)
            }
            .labelsHidden()
        }
    }

    private func signedPercent(_ v: Double) -> String {
        let p = Int((v * 100).rounded())
        return p > 0 ? "+\(p)%" : "\(p)%"
    }

    private func nameBinding(for swatch: Swatch) -> Binding<String> {
        Binding(
            get: { store.name(for: swatch) ?? "" },
            set: { store.rename(swatch, to: $0) }
        )
    }

    private func matches(for swatch: Swatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEAREST NAMED COLORS")
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)

            ForEach(palettes.nearest(to: swatch, limit: 3)) { match in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(match.entry.swatch.color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(match.entry.name)
                            .font(.callout.weight(.medium))
                        Text(match.entry.paletteName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("ΔE \(String(format: "%.1f", match.deltaE)) · \(match.quality)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.setString(match.entry.name, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy name")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }

    private func ratio(_ label: String, _ value: Double) -> some View {
        let passes = value >= 4.5
        let tint = passes ? Color.green : Color.orange
        return HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text("\(label) \(String(format: "%.2f", value)) · \(Swatch.grade(value))")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Grids

    private func grid(_ title: String, _ swatches: [Swatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                if title == "History" {
                    Button("Clear") { store.clearHistory() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                ForEach(swatches) { swatch in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(swatch.color)
                            .frame(height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(active?.id == swatch.id
                                                  ? Color.accentColor
                                                  : Color.primary.opacity(0.12),
                                                  lineWidth: active?.id == swatch.id ? 2 : 1)
                            )
                        Text(String(swatch.hex.dropFirst()))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selected = swatch }
                    .help(swatch.hex)
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: ColorStore
    @ObservedObject private var palettes = PaletteLibrary.shared
    @ObservedObject private var colorNames = ColorNames.shared
    @State private var importNote: String?

    private var colorNamesSummary: String {
        colorNames.count == 0
            ? "loading…"
            : "\(colorNames.count) names loaded"
    }

    var body: some View {
        Form {
            Section {
                if !store.useSystemPicker {
                    HStack {
                        Label(
                            ScreenRecording.isGranted
                                ? "Screen Recording granted"
                                : "Screen Recording needed — zoom disabled",
                            systemImage: ScreenRecording.isGranted
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(ScreenRecording.isGranted ? .green : .orange)
                        Spacer()
                        if !ScreenRecording.isGranted {
                            Button("Open Settings") {
                                ScreenRecording.openSystemSettings()
                            }
                        }
                    }
                }

                Toggle("Use the macOS system loupe", isOn: $store.useSystemPicker)

                if !store.useSystemPicker {
                    HStack {
                        Text("Zoom")
                        Spacer()
                        Text("\(Int(store.loupeZoom))×")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.loupeZoom, in: 4...48, step: 2)

                    HStack {
                        Text("Zoom while holding Control")
                        Spacer()
                        Text("\(Int(store.loupePreciseZoom))×")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.loupePreciseZoom, in: 4...48, step: 2)
                }
            } header: {
                Text("Loupe")
            } footer: {
                Text(store.useSystemPicker
                     ? "Apple's loupe needs no permission but offers no zoom control."
                     : "Hold Control while picking for precise zoom and a larger crosshair. Scroll to trim zoom, arrow keys nudge one pixel, Escape cancels. Needs Screen Recording permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Picking") {
                Toggle("Copy to clipboard on pick", isOn: $store.copyOnPick)
                Toggle("Keep picking until Escape", isOn: $store.keepPickingUntilEscape)
                Picker("Default format", selection: $store.format) {
                    ForEach(ColorFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                LabeledContent("Pick color", value: "⌃⌥⌘C")
                LabeledContent("Open library", value: "⌃⌥⌘X")
            }

            Section {
                if palettes.loadedPalettes.isEmpty {
                    Text("No swatch books loaded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(palettes.loadedPalettes, id: \.self) { name in
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Import Adobe Books") {
                        let count = palettes.importAdobeBooks()
                        importNote = count == 0
                            ? "Nothing new found"
                            : "Imported \(count) book\(count == 1 ? "" : "s")"
                    }
                    Button("Reload") {
                        palettes.reload()
                        importNote = nil
                    }
                    Button("Open Folder") {
                        NSWorkspace.shared.open(palettes.folderURL)
                    }
                    if let note = importNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Palettes")
            } footer: {
                Text("Pantone data is licensed and isn't bundled — and Adobe dropped its Pantone books in 2022, so importing brings in TRUMATCH, TOYO, DIC, HKS and FOCOLTONE. Add Pantone yourself as .ase or .csv.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Color names",
                               value: colorNamesSummary)
            } header: {
                Text("Credits")
            } footer: {
                Text("Color names from meodai/color-names — MIT licence, © 2017 David Aerne. Bundled with the app; the full licence ships in Resources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Clear history", role: .destructive) { store.clearHistory() }
            } footer: {
                Text("Shortcuts match the ones you had in ColorSnapper 2. They're fixed in this version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Window

/// A plain NSWindow hosting SwiftUI — an accessory app can't reliably drive a
/// SwiftUI `Settings` scene from a global hot key, so this stays explicit.
final class LibraryWindowController {
    static let shared = LibraryWindowController()

    private var window: NSWindow?

    private init() {}

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if window == nil {
            let hosting = NSHostingView(
                rootView: LibraryView().environmentObject(ColorStore.shared)
            )
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Swatch Monster"
            win.titlebarAppearsTransparent = true
            win.isReleasedWhenClosed = false
            win.contentView = hosting
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
