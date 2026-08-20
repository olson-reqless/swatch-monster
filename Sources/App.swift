import AppKit
import SwiftUI

@main
struct SwatchMonsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = ColorStore.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            Image(systemName: "eyedropper.halffull")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no main menu.
        NSApp.setActivationPolicy(.accessory)

        // 32k names, parsed off the main thread while the user gets oriented.
        ColorNames.shared.loadIfNeeded()

        // Ad-hoc signing means a rebuild changes the app's identity and macOS
        // silently drops Screen Recording, which disables the zoom loupe. Record
        // it at launch so the cause is visible instead of looking like a lost
        // feature.
        ScreenRecording.recordStatusAtLaunch()

        HotKeyCenter.shared.register(id: Shortcut.pickColor,
                                     keyCode: Shortcut.pickKeyCode,
                                     modifiers: Shortcut.carbonModifiers) {
            Sampler.shared.pick()
        }

        HotKeyCenter.shared.register(id: Shortcut.openLibrary,
                                     keyCode: Shortcut.libraryKeyCode,
                                     modifiers: Shortcut.carbonModifiers) {
            LibraryWindowController.shared.toggle()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
