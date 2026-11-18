import AppKit
import SwiftUI

/// The Spotlight-style window.
///
/// A non-activating panel keeps the app underneath "frontmost" from the
/// system's point of view, which is what lets a paste land in the right place
/// the moment the panel closes.
final class LauncherPanel: NSPanel, NSWindowDelegate {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherView.panelWidth, height: 180),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false  // The SwiftUI glass draws its own.
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        delegate = self
    }

    // MARK: - Clicking away

    /// Losing key means the user went somewhere else — another app, another
    /// window — so the launcher gets out of the way.
    ///
    /// The check is deferred because key status also flickers while the app is
    /// activating, which is exactly when `present()` is still fighting to take
    /// it. By the time this runs, that race has settled one way or the other.
    func windowDidBecomeKey(_ notification: Notification) {
        hasHeldKey = true
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            switch Self.outcomeOnResign(
                visible: self.isVisible, key: self.isKeyWindow, dismissing: self.isDismissing,
                hasHeldKey: self.hasHeldKey,
                sincePresented: Date().timeIntervalSince(self.presentedAt))
            {
            case .ignore:
                break
            case .retakeKey:
                self.reassertKey(attemptsLeft: 4)
            case .dismiss:
                self.onDismissRequest?()
            }
        }
    }

    /// What a lost key status means, decided apart from any window so it can
    /// be tested without putting a panel on screen.
    enum ResignOutcome: Equatable {
        /// Nothing to do — the panel is gone, or has focus after all.
        case ignore
        /// A focus flicker to recover from.
        case retakeKey
        /// The user went somewhere else.
        case dismiss
    }

    /// Losing key within a moment of presenting is a flicker, not a decision.
    ///
    /// AppKit hands activation back to whatever app was in front as a
    /// menu-bar menu finishes tearing down, and an accessory app can have key
    /// taken off it just after winning it. Both look exactly like a click
    /// elsewhere, and both used to close the launcher the instant it opened.
    /// Nobody opens the launcher and clicks away inside `focusGrace`, so the
    /// benefit of the doubt goes to keeping it on screen.
    nonisolated static func outcomeOnResign(
        visible: Bool, key: Bool, dismissing: Bool, hasHeldKey: Bool,
        sincePresented: TimeInterval
    ) -> ResignOutcome {
        guard visible, !key, !dismissing, hasHeldKey else { return .ignore }
        return sincePresented < focusGrace ? .retakeKey : .dismiss
    }

    /// How long after presenting a lost key is treated as a flicker to be
    /// recovered from rather than as the user clicking away.
    nonisolated static let focusGrace: TimeInterval = 0.8

    /// Called when the panel decides it should go away — clicking outside, or
    /// the window's own cancel. The environment owns the exit animation, so it
    /// routes back through there rather than ordering out directly.
    var onDismissRequest: (() -> Void)?

    /// Required so the search field can take keystrokes from a borderless panel.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismissRequest?()
    }

    /// Set while a fade-out is in flight, so a re-open can cancel it.
    private var isDismissing = false
    /// Whether this presentation ever held focus. Without it, a panel that
    /// never managed to take key — activation can be refused — would read as
    /// "the user clicked away" and close itself the instant it appeared.
    private var hasHeldKey = false
    /// When this presentation went on screen, for the focus grace period.
    private var presentedAt = Date.distantPast

    func present() {
        // A dismiss still fading out would otherwise order this window back
        // out a moment after it appears — the fast ⌥Space-twice case.
        isDismissing = false
        hasHeldKey = false
        presentedAt = Date()

        positionOnActiveScreen()
        // The content animates itself in from a scaled-down, transparent
        // state, so the window itself is simply opaque the whole time.
        alphaValue = 1
        // Activate before taking key: an accessory app that orders a window
        // front first can have key status taken straight back off it.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        // Taking key can fail when the app is still mid-activation — reliably
        // so when a dismiss and an open land in the same run-loop turn, which
        // is what toggling the hot key twice in quick succession does. Without
        // this the panel is on screen with a caret in the field, but typing
        // goes to whatever app was in front.
        reassertKey(attemptsLeft: 4)
    }

    private func reassertKey(attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self, self.isVisible, !self.isDismissing else { return }
            guard !self.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKey()
            self.reassertKey(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Orders out once the content has finished animating away. The window
    /// stays put in the meantime so SwiftUI has something to draw into.
    func dismiss(after delay: TimeInterval = LauncherView.exitDuration) {
        guard isVisible else { return }
        isDismissing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isDismissing else { return }
            self.orderOut(nil)
        }
    }

    /// Resizes around a fixed top edge, so the search field never moves while
    /// results appear and disappear underneath it.
    func setContentHeight(_ height: CGFloat) {
        guard height > 1, abs(frame.height - height) > 0.5 else { return }
        var updated = frame
        updated.origin.y += updated.height - height
        updated.size.height = height
        setFrame(updated, display: true, animate: false)
    }

    /// Centred horizontally, a third of the way down — the position Spotlight
    /// trained everyone to look at.
    private func positionOnActiveScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                // The inset keeps the glass itself where it was before the
                // window grew a margin for its shadow.
                y: visible.maxY - visible.height * 0.28 - size.height + LauncherView.shadowInset))
    }
}
