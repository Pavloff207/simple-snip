import Carbon.HIToolbox

/// Registers one system-wide hotkey through Carbon, which needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    /// Returns false when the shortcut is already taken by another app or by macOS.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x534E_4950) /* 'SNIP' */, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in
                HotKeyCenter.shared.onPress?()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
