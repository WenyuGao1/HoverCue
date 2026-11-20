import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager: @unchecked Sendable {
    private var handlerReference: EventHandlerRef?
    private var hotKeyReferences: [EventHotKeyRef?] = []
    private let action: @MainActor @Sendable (UInt32) -> Void

    init(action: @escaping @MainActor @Sendable (UInt32) -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, pointer in
                guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
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
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(pointer).takeUnretainedValue()
                Task { @MainActor in manager.action(hotKeyID.id) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerReference
        )
        register(keyCode: UInt32(kVK_ANSI_C), id: 1)
        register(keyCode: UInt32(kVK_ANSI_O), id: 2)
    }

    deinit {
        for reference in hotKeyReferences.compactMap({ $0 }) { UnregisterEventHotKey(reference) }
        if let handlerReference { RemoveEventHandler(handlerReference) }
    }

    private func register(keyCode: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C444350), id: id) // LDCP
        RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        hotKeyReferences.append(reference)
    }
}
