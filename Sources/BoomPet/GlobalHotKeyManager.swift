import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager {
    enum Action: UInt32 {
        case history = 1
        case ocr = 2
        case sticky = 3
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                DispatchQueue.main.async {
                    manager.handlers[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit {
        hotKeyRefs.forEach { _ = UnregisterEventHotKey($0) }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerDefaults(
        onHistory: @escaping () -> Void,
        onOCR: @escaping () -> Void,
        onSticky: @escaping () -> Void
    ) {
        handlers[Action.history.rawValue] = onHistory
        handlers[Action.ocr.rawValue] = onOCR
        handlers[Action.sticky.rawValue] = onSticky

        register(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey),
            action: .history
        )
        register(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(optionKey),
            action: .ocr
        )
        register(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(optionKey),
            action: .sticky
        )
    }

    private func register(
        keyCode: UInt32,
        modifiers: UInt32,
        action: Action
    ) {
        var ref: EventHotKeyRef?
        let signature: OSType = 0x4250_4554 // BPET
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        if RegisterEventHotKey(
            keyCode,
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        ) == noErr, let ref {
            hotKeyRefs.append(ref)
        }
    }
}
