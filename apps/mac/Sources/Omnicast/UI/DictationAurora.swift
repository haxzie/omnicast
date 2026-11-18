import AppKit
import SwiftUI
import VoiceGlowKit

/// The aurora that rises from the bottom edge of the screen while you dictate.
///
/// Driven by `levelProvider` rather than VoiceGlowKit's own `VoiceMeter`: the
/// app already has the microphone open for dictation, and a second
/// `AVAudioEngine` on the same input would be a wasted tap — and a second
/// reason for the system's recording indicator to stay lit.
struct DictationAurora: View {
    @ObservedObject var model: DictationHUDModel

    /// A radial falloff centred on the bottom edge, where the glow rises
    /// from — this fades the sides.
    private var vanishingPoint: some View {
        GeometryReader { proxy in
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white.opacity(0.92), location: 0.40),
                    .init(color: .white.opacity(0.34), location: 0.74),
                    .init(color: .clear, location: 1),
                ]),
                center: .bottom,
                startRadius: 0,
                // Reaches clear by the left and right edges. Keyed to width
                // alone: a circle wide enough to fade the sides of a shallow
                // rect is still near-opaque at its top, which is what left a
                // hard edge up there.
                // 0.42, not 0.5: at half the width the fade only finishes
                // exactly at the bottom corners, so the glow's legs reach the
                // edge still faintly lit and read as sliced off. Finishing
                // early leaves clear margin on every side.
                endRadius: proxy.size.width * 0.42
            )
        }
    }

    /// And this fades the top, which the radial cannot reach.
    private var ceilingFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.82), location: 0.42),
                .init(color: .white.opacity(0.18), location: 0.78),
                .init(color: .clear, location: 1),
            ],
            startPoint: .bottom, endPoint: .top)
    }

    var body: some View {
        VoiceGlow(
            type: .mobile,
            levelProvider: { model.level },
            active: model.phase != .hidden,
            colorVariant: .colorful,
            theme: .dark,
            cornerRadius: 0
        ) {
            // Nothing to wrap — the glow is the whole point, so it wraps the
            // strip of screen it rises from.
            Color.clear
        }
        .mask { vanishingPoint }
        .mask { ceilingFade }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hosts the aurora across the bottom edge of whichever screen the user is on.
///
/// Click-through and non-activating, like the droplet, so it never takes focus
/// from whatever you are dictating into.
@MainActor
final class AuroraPanel: NSPanel {
    /// VoiceGlow's geometry is fixed in points — roughly a 170pt half-width
    /// ceiling — so shrinking the rect it wraps does not shrink the glow, it
    /// crops it into a visible rectangle. Render at the size it wants, then
    /// scale the whole thing down.
    /// Wider rect, uniform scale. A non-uniform `scaleEffect` silently
    /// flattens the shader's output to grey — measured at 0.02 peak
    /// saturation — so the width has to come from the geometry it is given,
    /// not from stretching the result.
    private static let naturalSize = CGSize(width: 820, height: 170)
    private static let scale: CGFloat = 0.34
    /// Room around the scaled glow so its soft edges fade out rather than
    /// meeting the window's border, which clips.
    private static let margin: CGFloat = 60

    private static var glowSize: CGSize {
        CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
    }
    private static var width: CGFloat { glowSize.width + margin * 2 }
    private static var height: CGFloat { glowSize.height + margin }

    init(model: DictationHUDModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        contentView = NSHostingView(
            rootView: DictationAurora(model: model)
                .frame(width: Self.naturalSize.width, height: Self.naturalSize.height)
                .scaleEffect(Self.scale, anchor: .bottom)
                .frame(width: Self.glowSize.width, height: Self.glowSize.height, alignment: .bottom)
                .frame(width: Self.width, height: Self.height, alignment: .bottom))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
        else { return }
        // Centred on the screen's bottom edge, over the Dock rather than
        // pushed above it.
        setFrame(
            NSRect(
                x: screen.frame.midX - Self.width / 2, y: screen.frame.minY,
                width: Self.width, height: Self.height),
            display: true)
        orderFrontRegardless()
    }
}
