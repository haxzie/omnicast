import AppKit
import Carbon.HIToolbox

/// A single global shortcut registered with the Carbon hot key API — the only
/// way to get a system-wide chord without Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    let handler: () -> Void

    fileprivate init(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.id = id
        self.handler = handler

        var hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        _ = hotKeyID
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    fileprivate static let signature: OSType = 0x4F4D4E43  // 'OMNC'

    private var hotKeys: [UInt32: HotKey] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private init() {}

    @discardableResult
    func register(shortcut: Shortcut, handler: @escaping () -> Void) -> UInt32 {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        hotKeys[id] = HotKey(
            id: id, keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers, handler: handler)
        return id
    }

    func unregister(_ id: UInt32) {
        hotKeys[id] = nil
    }

    fileprivate func fire(id: UInt32) {
        hotKeys[id]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { HotKeyManager.shared.fire(id: hotKeyID.id) }
                return noErr
            }, 1, &spec, nil, nil)
    }
}

/// A key chord, stored in preferences as a plain `keyCode`/`modifiers` pair.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags.rawValue`, translated to Carbon on registration.
    var modifiers: UInt

    static let launcher = Shortcut(
        keyCode: UInt32(kVK_Space), modifiers: NSEvent.ModifierFlags.option.rawValue)
    static let clipboard = Shortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let dictation = Shortcut(
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: NSEvent.ModifierFlags([.option, .shift]).rawValue)

    var carbonModifiers: UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts + Self.keyName(for: keyCode)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "esc"
        default:
            // Map through the current keyboard layout so non-QWERTY users see
            // the key they actually press.
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return "?" }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            return data.withUnsafeBytes { buffer -> String in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
                else { return "?" }
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4,
                    &length, &chars)
                guard status == noErr, length > 0 else { return "?" }
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
        }
    }
}
