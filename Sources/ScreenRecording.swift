import AppKit
import CoreGraphics

/// Screen Recording is what the zoom loupe depends on, and an ad-hoc signed app
/// loses the grant every time it is rebuilt. Surfacing the state stops that from
/// looking like a vanished feature.
enum ScreenRecording {

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Written on every launch so the current state can be checked from outside
    /// the app without digging through the unified log.
    static func recordStatusAtLaunch() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Swatch Monster", isDirectory: true)
        try? FileManager.default.createDirectory(at: base,
                                                 withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        let text = """
            launched: \(formatter.string(from: Date()))
            screenRecordingGranted: \(isGranted)
            loupe: \(isGranted ? "custom zoom loupe" : "system fallback — no Control zoom")
            """
        try? text.write(to: base.appendingPathComponent("diagnostics.txt"),
                        atomically: true, encoding: .utf8)
    }
}
