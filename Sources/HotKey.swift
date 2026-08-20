import AppKit
import Carbon.HIToolbox

/// Thin wrapper over Carbon's `RegisterEventHotKey`, which is still the only
/// way to get a system-wide shortcut without asking for Accessibility access.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false
    private let signature: OSType = 0x53574D54 // 'SWMT'

    private init() {}

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Swatch Monster: could not register hot key \(id) (OSStatus \(status)) — another app probably owns it")
            return
        }
        refs[id] = ref
        actions[id] = action
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
        actions[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        // A C callback can't capture context, so it routes through the singleton.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            DispatchQueue.main.async { HotKeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Shortcuts carried over from ColorSnapper 2 so muscle memory survives.
enum Shortcut {
    static let pickColor: UInt32 = 1
    static let openLibrary: UInt32 = 2

    static let carbonModifiers = UInt32(cmdKey | optionKey | controlKey)
    static let pickKeyCode = UInt32(kVK_ANSI_C)   // ⌃⌥⌘C
    static let libraryKeyCode = UInt32(kVK_ANSI_X) // ⌃⌥⌘X
}
