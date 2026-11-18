import Foundation

/// Decides when you have stopped talking.
///
/// Deliberately will not fire until it has heard speech at least once: a
/// pause *before* you start is someone collecting their thoughts, not the end
/// of a sentence, and cutting that off would be worse than waiting.
struct SilenceDetector {
    /// Room tone reads under 0.05 on the level curve and ordinary speech well
    /// over 0.6, so this sits clear of both.
    static let voiceThreshold: Double = 0.14
    /// Generous on purpose — long enough to take a breath mid-sentence.
    static let defaultTimeout: TimeInterval = 2.2

    var threshold: Double = SilenceDetector.voiceThreshold
    var timeout: TimeInterval = SilenceDetector.defaultTimeout

    private(set) var lastVoiceAt: Date?

    /// True once speech has been heard, so a lull counts as an ending.
    var hasHeardVoice: Bool { lastVoiceAt != nil }

    mutating func observe(level: Double, at now: Date = Date()) {
        if level >= threshold { lastVoiceAt = now }
    }

    func hasFallenSilent(at now: Date = Date()) -> Bool {
        guard let lastVoiceAt else { return false }
        return now.timeIntervalSince(lastVoiceAt) >= timeout
    }

    mutating func reset() {
        lastVoiceAt = nil
    }
}
