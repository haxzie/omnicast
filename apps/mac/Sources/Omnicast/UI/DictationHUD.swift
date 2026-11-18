import AppKit
import Combine
import SwiftUI

/// What the dictation display is showing.
enum DictationHUDPhase: Equatable {
    case hidden
    case recording
    case transcribing
    case failed(String)
}

@MainActor
final class DictationHUDModel: ObservableObject {
    @Published var phase: DictationHUDPhase = .hidden
    @Published var level: Double = 0
    /// The transcript so far, updated while you speak.
    @Published var text: String = ""
}

/// The words, as they are recognised, above the aurora.
///
/// Only the last three lines are kept and the top of the block fades out, so a
/// long sentence scrolls upward into nothing rather than growing a panel.
struct LiveTranscriptView: View {
    @ObservedObject var model: DictationHUDModel

    static let width: CGFloat = 470
    private static let lineLimit = 3
    /// Height of the three-line block. The text is bottom-aligned inside it,
    /// which is what keeps a single line clear of the fade.
    private static let blockHeight: CGFloat = 72

    var body: some View {
        Text(display)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.white.opacity(0.78))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            // Head truncation keeps the newest words: the sentence runs off
            // the top, not the bottom.
            .lineLimit(Self.lineLimit)
            .truncationMode(.head)
            .frame(width: Self.width, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            // A fixed three-line block, filled from the bottom up: one line
            // sits in the clear lower third, and only a third line reaches
            // the fade.
            .frame(width: Self.width, height: Self.blockHeight, alignment: .bottom)
            // Just enough to lift the glyphs off whatever is behind them. A
            // heavy shadow reads as a dark halo around every letter, which is
            // worse than the legibility it buys.
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.1), radius: 9)
            .mask { fade }
            // Leaves as deliberately as it arrived, rather than blinking out
            // when the window is ordered away.
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.97, anchor: .bottom)
            .blur(radius: isVisible ? 0 : 2)
            .animation(Self.appearance, value: isVisible)
            .animation(.easeOut(duration: 0.18), value: display)
            .accessibilityLabel(display)
    }

    /// Dissolves the oldest line only.
    ///
    /// The gradient reaches full strength a third of the way down — the
    /// height of one line — so it can only ever touch a third line. Running
    /// the fade across the whole block, as this did, dimmed the top of a
    /// lone line and made short phrases look half-erased.
    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.05), location: 0),
                .init(color: .white.opacity(0.42), location: 0.19),
                .init(color: .white, location: 0.33),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// Matches the window's order-out delay in `AppEnvironment`.
    static let appearanceDuration: TimeInterval = 0.2
    private static let appearance = Animation.easeOut(duration: appearanceDuration)

    private var isVisible: Bool { model.phase != .hidden }

    private var display: String {
        switch model.phase {
        case .failed(let message): return message
        case .recording, .transcribing, .hidden:
            return model.text
        }
    }
}

/// Hosts the transcript above the aurora, at the bottom of the active screen.
@MainActor
final class TranscriptPanel: NSPanel {
    /// Generous and fixed, so the text does not reflow as words arrive.
    private static let width = LiveTranscriptView.width + 80
    /// Three lines plus room for the fade.
    private static let height: CGFloat = 112
    /// Clears the aurora, which occupies the bottom of the screen.
    private static let bottomInset: CGFloat = 54

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
            rootView: LiveTranscriptView(model: model)
                .frame(width: Self.width, height: Self.height, alignment: .bottom))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
        else { return }
        setFrame(
            NSRect(
                x: screen.frame.midX - Self.width / 2,
                y: screen.frame.minY + Self.bottomInset,
                width: Self.width, height: Self.height),
            display: true)
        orderFrontRegardless()
    }
}
