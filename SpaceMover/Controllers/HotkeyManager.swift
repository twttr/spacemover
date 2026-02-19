import Carbon
import Cocoa

enum HotkeyAction {
    case moveSpaceLeft
    case moveSpaceRight
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let hotkeySignature = OSType(0x53504D56)

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []

    var onAction: ((HotkeyAction) -> Void)?

    private init() {}

    func registerHotkeys() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
                _ = HotkeyManager.handleHotKeyEvent(event)
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else { return }

        registerHotkey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey), id: 1)
        registerHotkey(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey), id: 2)
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        let hotKeyID = EventHotKeyID(signature: Self.hotkeySignature, id: id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }

    private nonisolated static func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        let action: HotkeyAction = hotKeyID.id == 1 ? .moveSpaceLeft : .moveSpaceRight
        Task { @MainActor in
            HotkeyManager.shared.onAction?(action)
        }
        return noErr
    }

    func cleanup() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        onAction = nil
    }
}
