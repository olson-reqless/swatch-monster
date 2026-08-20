import AppKit

/// Routes a pick request to either the custom zoom loupe or Apple's system
/// sampler, and feeds the result back into the store.
final class Sampler {
    static let shared = Sampler()

    private var systemSampler: NSColorSampler?
    private var usingLoupe = false

    private init() {}

    var isPicking: Bool { systemSampler != nil || usingLoupe }

    func pick() {
        // Ignore a second hot-key press while a picker is already up.
        guard !isPicking else { return }

        // Dismiss the menu-bar panel so it isn't fighting the picker for focus.
        NSApp.keyWindow?.close()

        if ColorStore.shared.useSystemPicker {
            showSystemSampler()
        } else {
            usingLoupe = true
            LoupeController.shared.pick { [weak self] color in
                self?.usingLoupe = false
                self?.handle(color)
            }
        }
    }

    private func showSystemSampler() {
        let sampler = NSColorSampler()
        systemSampler = sampler
        sampler.show { [weak self] color in
            self?.systemSampler = nil
            self?.handle(color)
        }
    }

    private func handle(_ color: NSColor?) {
        guard let color else { return } // user pressed Escape
        ColorStore.shared.record(color)

        if ColorStore.shared.keepPickingUntilEscape {
            DispatchQueue.main.async { [weak self] in self?.pick() }
        }
    }
}
