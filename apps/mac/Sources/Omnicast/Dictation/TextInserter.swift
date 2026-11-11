import AppKit
import Carbon.HIToolbox

/// Puts text where the user is typing.
///
/// Synthesising ⌘V is the only approach that works in every app (including
/// Electron and Terminal), at the cost of needing Accessibility permission.
@MainActor
enum TextInserter {
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func copy(_ text: String, suppressHistory: Bool = false) {
        if suppressHistory { AppEnvironment.shared.clipboardMonitor.suppressNextChange() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Copies `text` and sends ⌘V to the frontmost app, restoring whatever was
    /// on the pasteboard afterwards.
    static func paste(_ text: String) {
        guard hasAccessibilityPermission else {
            copy(text)
            requestAccessibilityPermission()
            return
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        copy(text, suppressHistory: true)

        // Give the frontmost app a beat to become key after the panel closes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCommandV()
            guard let previous else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AppEnvironment.shared.clipboardMonitor.suppressNextChange()
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
