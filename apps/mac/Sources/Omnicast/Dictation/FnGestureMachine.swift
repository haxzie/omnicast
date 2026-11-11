import Foundation

/// The press-and-hold / tap-to-latch gesture behind fn-key dictation.
///
/// Hold the key and dictation runs for as long as you hold it. Tap it and
/// dictation latches on, so you can talk hands-free until you tap again.
/// Kept free of AppKit so the behaviour can be tested directly.
struct FnGestureMachine: Equatable {
    enum State: Equatable {
        case idle
        /// The key is physically down.
        case holding
        /// The key was tapped and released; recording continues.
        case latched
    }

    enum Action: Equatable {
        case start
        /// Stop and transcribe.
        case finish
        /// Stop and throw the audio away.
        case cancel
        case none
    }

    /// A press shorter than this is a tap, not a hold.
    var tapThreshold: TimeInterval = 0.4

    private(set) var state: State = .idle
    private var pressedAt: TimeInterval = 0

    mutating func fnPressed(at time: TimeInterval) -> Action {
        switch state {
        case .idle:
            state = .holding
            pressedAt = time
            return .start
        case .latched:
            // Second tap ends a hands-free session.
            state = .idle
            return .finish
        case .holding:
            // Key repeat while already held.
            return .none
        }
    }

    mutating func fnReleased(at time: TimeInterval) -> Action {
        guard state == .holding else { return .none }
        if time - pressedAt < tapThreshold {
            state = .latched
            return .none
        }
        state = .idle
        return .finish
    }

    /// Any other key while the fn key is held means the user meant a chord
    /// (fn+F3, fn+arrow), not dictation. Escape always aborts.
    mutating func otherKeyPressed(isEscape: Bool) -> Action {
        switch state {
        case .holding:
            state = .idle
            return .cancel
        case .latched where isEscape:
            state = .idle
            return .cancel
        default:
            return .none
        }
    }

    mutating func reset() {
        state = .idle
    }
}
