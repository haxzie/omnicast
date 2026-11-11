import AppKit
import Combine
import SwiftUI

/// What the droplet is showing. Mirrors `DictationController.Phase` but is kept
/// separate so the panel can also be driven with synthetic values for preview.
enum DropletPhase: Equatable {
    case hidden
    case recording
    case transcribing
    case done
    case failed(String)
}

@MainActor
final class DropletModel: ObservableObject {
    @Published var phase: DropletPhase = .hidden
    @Published var level: Double = 0
}

/// A drop of water rises through the bottom edge of the screen, settles, and
/// stretches open into a live amplitude meter while you speak.
struct DictationDroplet: View {
    @ObservedObject var model: DropletModel

    /// Shared by the shape and its contents so they move as one object.
    private static let openSpring = Animation.spring(response: 0.38, dampingFraction: 0.62)

    private var isOpen: Bool {
        switch model.phase {
        case .hidden: return false
        case .recording, .transcribing, .done, .failed: return true
        }
    }

    private var size: CGSize {
        switch model.phase {
        case .hidden: return CGSize(width: 20, height: 28)
        case .recording, .transcribing, .done: return CGSize(width: 104, height: 28)
        case .failed: return CGSize(width: 250, height: 34)
        }
    }

    /// Resting position above the bottom edge; tucked below the screen when hidden.
    private var offsetY: CGFloat { isOpen ? -20 : 48 }

    var body: some View {
        let shape = TeardropShape(morph: isOpen ? 1 : 0)

        return shape
            // Blurs whatever is behind it, then sits a dark tint on top so the
            // indicator reads the same over a light desktop or a dark one.
            .fill(.ultraThinMaterial)
            .overlay { shape.fill(.black.opacity(0.3)) }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .clear],
                        startPoint: .top, endPoint: .center))
            }
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.26), .white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom), lineWidth: 0.7)
            }
            .overlay {
                content
                    // The contents ride the same spring as the shape, so they
                    // pop open with the pill instead of fading in beside it.
                    .scaleEffect(isOpen ? 1 : 0.35)
                    .opacity(isOpen ? 1 : 0)
                    .animation(Self.openSpring, value: isOpen)
                    .animation(Self.openSpring, value: model.phase)
                    .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.5), radius: 11, y: 5)
            .offset(y: offsetY)
            // Rises fast and settles with a little wobble, like a drop of water.
            .animation(.spring(response: 0.42, dampingFraction: 0.58), value: offsetY)
            .animation(Self.openSpring, value: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording:
            // No frame: the wave fills the pill edge to edge and is clipped by
            // its shape, so there is no inset band of bare glass at the ends.
            SiriWaveView(level: model.level)
        case .transcribing:
            PulsingDots()
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 10.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
        }
    }
}

/// Three dots breathing while the model works.
private struct PulsingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = sin(time * 4 - Double(index) * 0.6) * 0.5 + 0.5
                    Circle()
                        .fill(.white.opacity(0.35 + phase * 0.55))
                        .frame(width: 4, height: 4)
                        .scaleEffect(0.8 + phase * 0.35)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Hosts the droplet at the bottom centre of whichever screen the user is on.
///
/// Click-through and non-activating: it floats over everything, including full
/// screen apps, without taking focus from whatever you are dictating into.
@MainActor
final class DropletPanel: NSPanel {
    private static let size = NSSize(width: 320, height: 130)

    init(model: DropletModel) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .screenSaver  // Above the menu bar, so the drop can fall from the very top.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Pin the materials to their dark variant: the indicator should look
        // the same whether the user is in light or dark mode.
        appearance = NSAppearance(named: .darkAqua)
        contentView = NSHostingView(rootView: DictationDroplet(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
        else {
            return
        }
        // Anchored to the physical bottom edge, not the visible frame, so the
        // drop appears to come up through the bottom of the display — above the
        // Dock rather than pushed off it.
        setFrameOrigin(
            NSPoint(x: screen.frame.midX - Self.size.width / 2, y: screen.frame.minY))
        orderFrontRegardless()
    }
}
