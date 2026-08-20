import AppKit
import SwiftUI

/// The menu-bar panel: a large hero card with the color set in monospaced type,
/// contrast readouts, and labelled chips — deliberately not a dark dot grid.
struct PanelView: View {
    @EnvironmentObject var store: ColorStore
    @ObservedObject private var palettes = PaletteLibrary.shared
    @ObservedObject private var colorNames = ColorNames.shared
    @State private var showCopied = false

    private var current: Swatch {
        store.featured ?? Swatch(red: 0.42, green: 0.45, blue: 0.50)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            namesRow
            formatRow
            matchRow
            pairingsSection

            if !store.favorites.isEmpty {
                SwatchSection(title: "Pinned", swatches: store.favorites)
            }
            SwatchSection(title: "Recent", swatches: store.history)

            Divider()
            footer
        }
        .padding(18)
        .frame(width: 340)
    }

    // MARK: - Hero

    private var hero: some View {
        let swatch = current
        let onDark = swatch.relativeLuminance < 0.4

        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(swatch.color)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                Text(store.format.string(for: swatch))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(onDark ? Color.white : Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(14)
            }
            .frame(height: 104)
            .contentShape(Rectangle())
            .onTapGesture { copy(swatch) }
            .help("Click to copy")

            HStack(spacing: 8) {
                contrastPill("on white", swatch.contrastOnWhite)
                contrastPill("on black", swatch.contrastOnBlack)
                Spacer()
                if showCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if store.focused != nil {
                    Button("latest") { store.focus(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .help("Back to the most recent pick")
                }
            }
        }
    }

    private func contrastPill(_ label: String, _ ratio: Double) -> some View {
        let passes = ratio >= 4.5
        let tint = passes ? Color.green : Color.orange
        return HStack(spacing: 4) {
            Image(systemName: passes ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text("\(label) \(String(format: "%.1f", ratio))")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .help("WCAG \(Swatch.grade(ratio)) for body text")
    }

    // MARK: - Nearest named color

    @ViewBuilder
    private var matchRow: some View {
        if let match = palettes.nearest(to: current, limit: 1).first {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(match.entry.swatch.color)
                    .frame(width: 16, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                Text(match.entry.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("ΔE \(String(format: "%.1f", match.deltaE))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(match.entry.name, forType: .string)
            }
            .help("\(match.entry.paletteName) — \(match.quality) match. Click to copy the name.")
        }
    }

    // MARK: - Names

    @ViewBuilder
    private var namesRow: some View {
        let matches = colorNames.nearest(to: current, limit: 3)
        if let closest = matches.first {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(closest.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("ΔE \(String(format: "%.1f", closest.deltaE))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { copyName(closest.name) }
                .help("Click to copy “\(closest.name)”")

                if matches.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(matches.dropFirst()) { match in
                            Button {
                                copyName(match.name)
                            } label: {
                                Text(match.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule().fill(Color.primary.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Click to copy “\(match.name)”")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func copyName(_ name: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(name, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.25)) { showCopied = false }
        }
    }

    // MARK: - Pairings

    private var pairingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.showPairings.toggle()
            } label: {
                HStack {
                    Text("PAIRINGS")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: store.showPairings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if store.showPairings {
                ForEach(Harmony.allCases) { harmony in
                    pairingRow(harmony.label,
                               Pairings.set(harmony, from: current),
                               height: 26)
                }
                pairingRow("tones",
                           Pairings.ramp(from: current, steps: 9),
                           height: 22)
            }
        }
    }

    private func pairingRow(_ label: String,
                            _ swatches: [Swatch],
                            height: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { index, swatch in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(swatch.color)
                        .frame(height: height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { copy(swatch) }
                        .help(swatch.hex)
                        .contextMenu {
                            Button("Copy \(swatch.hex)") { store.copy(swatch) }
                            Button("Pin") { store.toggleFavorite(swatch) }
                        }
                }
            }
        }
    }

    // MARK: - Format

    private var formatRow: some View {
        HStack {
            Text("Format")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $store.format) {
                ForEach(ColorFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 175)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Sampler.shared.pick()
            } label: {
                Label("Pick Color", systemImage: "eyedropper.halffull")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                Button("Library") { LibraryWindowController.shared.show() }
                Spacer()
                Text("⌃⌥⌘C")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private func copy(_ swatch: Swatch) {
        store.copy(swatch)
        withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.25)) { showCopied = false }
        }
    }
}

// MARK: - Sections

struct SwatchSection: View {
    @EnvironmentObject var store: ColorStore
    let title: String
    let swatches: [Swatch]

    private let columns = [GridItem(.adaptive(minimum: 68), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                if !swatches.isEmpty {
                    Text("\(swatches.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            if swatches.isEmpty {
                Text("Nothing yet — press ⌃⌥⌘C to pick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(swatches.prefix(16)) { swatch in
                        SwatchChip(swatch: swatch)
                    }
                }
            }
        }
    }
}

struct SwatchChip: View {
    @EnvironmentObject var store: ColorStore
    let swatch: Swatch

    private var isFeatured: Bool { store.focused?.id == swatch.id }

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(swatch.color)
                .frame(height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isFeatured ? Color.accentColor
                                                 : Color.primary.opacity(0.12),
                                      lineWidth: isFeatured ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if store.isFavorite(swatch) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(swatch.relativeLuminance < 0.4 ? Color.white : Color.black)
                            .padding(3)
                    }
                }
            Text(String(swatch.hex.dropFirst()))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.focus(swatch)
            store.copy(swatch)
        }
        .help(swatch.hex)
        .contextMenu {
            Button(store.isFavorite(swatch) ? "Unpin" : "Pin") {
                store.toggleFavorite(swatch)
            }
            Divider()
            ForEach(ColorFormat.allCases) { format in
                Button("Copy \(format.label)") { store.copy(swatch, as: format) }
            }
            Divider()
            Button("Remove") { store.removeFromHistory(swatch) }
        }
    }
}
