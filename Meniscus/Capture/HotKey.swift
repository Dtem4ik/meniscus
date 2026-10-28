import Carbon.HIToolbox
import Foundation

/// A global keyboard shortcut. Registered with the Carbon hot key API, which works without
/// Accessibility access.
nonisolated struct HotKey: Codable, Equatable, Sendable {
    nonisolated struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
    }

    /// Virtual key code (layout independent position on the keyboard).
    var keyCode: UInt32
    var modifiers: Modifiers

    /// ⌃⌥Space: free in a default macOS setup.
    static let defaultCapture = HotKey(keyCode: UInt32(kVK_Space), modifiers: [.control, .option])

    /// A shortcut needs at least one of ⌘, ⌥ or ⌃, or it would swallow normal typing.
    var isValid: Bool { !modifiers.isDisjoint(with: [.command, .option, .control]) }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// Like the system shows shortcuts: ⌃⌥⇧⌘ then the key.
    var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        let key = Int(keyCode) == kVK_Space ? String(localized: "Space") : Self.keyNames[Int(keyCode)]
        return symbols + (key ?? "Key \(keyCode)")
    }

    /// Names for the ANSI layout; good enough to show a shortcut.
    static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_ANSI_Period: ".",
        kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_Grave: "`", kVK_ANSI_Backslash: "\\",
    ]
}

/// Registers global hot keys and calls back on the main actor when one is pressed.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    /// 'MNSC'
    private let signature: OSType = 0x4D4E_5343

    /// Returns an id for `unregister`, or `nil` if the shortcut is taken by another app.
    func register(_ hotKey: HotKey, action: @escaping () -> Void) -> UInt32? {
        installEventHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.carbonModifiers,
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == 0, let reference else { return nil }
        references[id] = reference
        handlers[id] = action
        return id
    }

    func unregister(_ id: UInt32) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        handlers[id] = nil
    }

    fileprivate func handle(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &eventHandler)
    }
}

/// Carbon delivers hot key events on the main thread.
private nonisolated func hotKeyEventHandler(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == 0 else { return status }
    let id = hotKeyID.id
    MainThread.run { HotKeyCenter.shared.handle(id: id) }
    return 0
}
