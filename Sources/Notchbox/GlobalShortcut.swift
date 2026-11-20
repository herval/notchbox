import AppKit
import Carbon

/// Carbon hot keys receive only this shortcut and need no keyboard-monitoring permission.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let callback: () -> Void
    private(set) var registered = false

    init(modifiers: UInt32 = UInt32(controlKey), callback: @escaping () -> Void) {
        self.callback = callback
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().callback()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return }
        let keyID = EventHotKeyID(signature: 0x4E544258, id: 1)
        registered = RegisterEventHotKey(UInt32(kVK_ANSI_Grave), modifiers, keyID,
                                         GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        registered = false
    }
}
