import AppKit
import Carbon.HIToolbox

/// System-wide hot key via Carbon's RegisterEventHotKey. Works inside the App
/// Sandbox and needs no Accessibility permission (unlike CGEventTap).
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private let signature: OSType = 0x57495350 // 'WISP'

    private init() {}

    func register(_ hotKey: HotKey, action: @escaping @MainActor () -> Void) {
        unregister()
        self.action = action
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: signature, id: 1)
        let mods = Self.carbonModifiers(from: hotKey.modifierFlags)
        let status = RegisterEventHotKey(UInt32(hotKey.keyCode), mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            Log.warning("RegisterEventHotKey failed (\(status)) for \(hotKey.displayString)", .app)
        } else {
            Log.info("Global hot key registered: \(hotKey.displayString)", .app)
        }
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        action = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            Task { @MainActor in
                if id.signature == GlobalHotKeyManager.shared.signature { GlobalHotKeyManager.shared.action?() }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &handlerRef)
    }

    nonisolated static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }
}
