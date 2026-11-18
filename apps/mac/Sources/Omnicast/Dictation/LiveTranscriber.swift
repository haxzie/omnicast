import Foundation

/// Transcribes while you are still speaking.
///
/// whisper.cpp has no streaming mode we can drive without handing it the
/// microphone — which the recorder already owns — so this re-runs the same
/// one-shot transcription over everything captured so far, every
/// `interval` seconds. Re-reading the whole utterance each pass is a little
/// wasteful, but it lets the text correct itself as context arrives
/// ("to" becoming "two" once the next word lands), which transcribing only
/// the newest slice cannot do.
///
/// The final transcript is still produced by the normal path when you stop;
/// this only drives what you see while talking.
actor LiveTranscriber {
    /// A floor between passes, not a cadence. Transcribing a few seconds of
    /// audio takes about 0.2s, so passes run back to back and the text
    /// updates roughly three times a second. Sleeping a fixed interval first
    /// — as this used to — meant the first words only appeared after it, which
    /// for a short sentence is the end.
    static let floor: TimeInterval = 0.12
    /// Below this there is not enough audio for a useful guess.
    static let minimumAudio: TimeInterval = 0.4
    /// Live passes only look at the most recent stretch, so the cost of a
    /// pass stays flat however long you talk.
    static let window: TimeInterval = 24

    private let transcriber = WhisperCLITranscriber()
    private var task: Task<Void, Never>?

    /// True when live passes can run at all.
    var isSupported: Bool { transcriber.isAvailable }

    func start(buffer: PCMBuffer, model: SpeechModel?, language: String,
               onText: @escaping @Sendable (String) -> Void) {
        stop()
        guard transcriber.isAvailable, model != nil else { return }

        task = Task {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("omnicast-live-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: scratch) }

            while !Task.isCancelled {
                // Transcribe first, then pause — so the opening words show up
                // as soon as there is enough audio for them.
                guard buffer.duration >= Self.minimumAudio,
                    buffer.writeWAV(to: scratch, maxSeconds: Self.window)
                else {
                    try? await Task.sleep(for: .seconds(Self.floor))
                    continue
                }

                guard
                    let result = try? await transcriber.transcribe(
                        audio: scratch, model: model, language: language, fast: true)
                else {
                    try? await Task.sleep(for: .seconds(Self.floor))
                    continue
                }

                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled else { return }
                if !text.isEmpty { onText(text) }
                try? await Task.sleep(for: .seconds(Self.floor))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
