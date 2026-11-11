import AppKit
import SwiftUI

/// The Spotlight-style window.
///
/// A non-activating panel keeps the app underneath "frontmost" from the
/// system's point of view, which is what lets a paste land in the right place
/// the moment the panel closes.
final class LauncherPanel: NSPanel {
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
    }

    /// Required so the search field can take keystrokes from a borderless panel.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func present() {
        positionOnActiveScreen()
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
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
