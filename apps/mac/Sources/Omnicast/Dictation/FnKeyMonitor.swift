import AppKit
import Carbon.HIToolbox

/// Turns physical fn-key events into dictation gestures.
///
/// The fn key can't be registered as a Carbon hot key, so this watches
/// `flagsChanged` instead. That needs Accessibility permission; without it the
/// monitors install but never fire, which is why Settings surfaces the
/// permission next to the toggle.
@MainActor
final class FnKeyMonitor {
    private var machine = FnGestureMachine()
    private var monitors: [Any] = []
    private let perform: (FnGestureMachine.Action) -> Void

    /// `kVK_Function`. Arrow and F-keys also set `.function` in their modifier
    /// flags, so the key code is what distinguishes a real fn press.
    private static let fnKeyCode: UInt16 = UInt16(kVK_Function)

    var isRunning: Bool { !monitors.isEmpty }

    init(perform: @escaping (FnGestureMachine.Action) -> Void) {
        self.perform = perform
    }

    func start() {
        guard monitors.isEmpty else { return }

        // Global monitors see other apps; local ones fire when Omnicast's own
        // panel has focus. Both are needed for the key to work everywhere.
        add(NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        })
        add(NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlags(event)
            return event
        })
        add(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        })
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        machine.reset()
    }

    /// Keeps the gesture state in step when dictation ends some other way
    /// (menu bar item, launcher shortcut, a failure).
    func resetGesture() {
        machine.reset()
    }

    private func add(_ monitor: Any?) {
        guard let monitor else { return }
        monitors.append(monitor)
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == Self.fnKeyCode else { return }
        let time = event.timestamp
        let action =
            event.modifierFlags.contains(.function)
            ? machine.fnPressed(at: time)
            : machine.fnReleased(at: time)
        dispatch(action)
    }

    private func handleKeyDown(_ event: NSEvent) {
        dispatch(machine.otherKeyPressed(isEscape: event.keyCode == UInt16(kVK_Escape)))
    }

    private func dispatch(_ action: FnGestureMachine.Action) {
        guard action != .none else { return }
        perform(action)
    }
}
