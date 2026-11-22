import Carbon.HIToolbox

/// A system-wide keyboard shortcut using Carbon's RegisterEventHotKey. It works without
/// the Accessibility permission and fires even when AudioGrab isn't the front app.
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private let identifier: UInt32

    /// ⌥⌘R
    static let defaultKeyCode = UInt32(kVK_ANSI_R)
    static let defaultModifiers = UInt32(cmdKey | optionKey)
    static let defaultDisplay = "⌥⌘R"

    init?(keyCode: UInt32, modifiers: UInt32, identifier: UInt32 = 1, action: @escaping () -> Void) {
        self.identifier = identifier
        guard Self.installHandlerIfNeeded() else { return nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4147_5242), id: identifier) // 'AGRB'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr, hotKeyRef != nil else { return nil }
        Self.actions[identifier] = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.actions[identifier] = nil
    }

    private static func installHandlerIfNeeded() -> Bool {
        if handlerInstalled { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if result == noErr { GlobalHotKey.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
        handlerInstalled = status == noErr
        return handlerInstalled
    }
}
