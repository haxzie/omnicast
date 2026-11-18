import AppKit
import Combine
import Foundation

/// Drives the press-to-talk flow: record → transcribe → insert → remember.
@MainActor
final class DictationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var level: Double = 0
    /// What has been recognised so far, while you are still speaking.
    @Published private(set) var liveText: String = ""

    private let recorder = AudioRecorder()
    private let store: DictationStore
    private let transcriber = CompositeTranscriber()
    private let live = LiveTranscriber()
    private var silence = SilenceDetector()
    private var silenceWatcher: Task<Void, Never>?
    private var levelObserver: AnyCancellable?
    private var targetApp: NSRunningApplication?
    private var resetTask: Task<Void, Never>?

    var engineName: String { transcriber.activeName }
    var isRecording: Bool { phase == .recording }

    init(store: DictationStore = .shared) {
        self.store = store
        levelObserver = recorder.$level.sink { [weak self] level in
            self?.level = level
            self?.silence.observe(level: level)
        }
    }

    func toggle() {
        if isRecording {
            Task { await stopAndTranscribe() }
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard phase != .recording, phase != .transcribing else { return }
        resetTask?.cancel()

        // Remember who had focus so the transcript lands back in the right app.
        targetApp = NSWorkspace.shared.frontmostApplication

        // Cleared before the engine starts, not after: `recorder.start()`
        // awaits a permission check and the audio engine coming up, and the
        // previous take's words would be on screen for all of it.
        liveText = ""

        do {
            _ = try await recorder.start()
            silence.reset()
            startLiveTranscription()
            startSilenceWatch()
            phase = .recording
            if Settings.shared.playDictationSounds { NSSound(named: "Tink")?.play() }
        } catch {
            phase = .failed(error.localizedDescription)
            scheduleReset(after: 4)
        }
    }

    /// Streams partial text into `liveText` while recording. Best effort: it
    /// needs whisper.cpp and a downloaded model, and when either is missing
    /// the display simply stays empty until the final transcript lands.
    private func startLiveTranscription() {
        let model = ModelManager.shared.activeModel
        let language = Settings.shared.dictationLanguage
        let buffer = recorder.buffer
        Task { [live] in
            await live.start(buffer: buffer, model: model, language: language) { text in
                Task { @MainActor [weak self] in
                    guard self?.isRecording == true else { return }
                    self?.liveText = text
                }
            }
        }
    }

    private func stopLiveTranscription() {
        Task { [live] in await live.stop() }
    }

    /// Ends the recording once you stop talking, so a hands-free take does
    /// not need a second keypress.
    private func startSilenceWatch() {
        silenceWatcher?.cancel()
        silenceWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                guard Settings.shared.autoStopOnSilence, self.isRecording,
                    self.silence.hasFallenSilent()
                else { continue }
                await self.stopAndTranscribe()
                return
            }
        }
    }

    private func stopSilenceWatch() {
        silenceWatcher?.cancel()
        silenceWatcher = nil
    }

    func cancel() {
        guard isRecording else { return }
        stopLiveTranscription()
        stopSilenceWatch()
        if let recording = recorder.stop() {
            try? FileManager.default.removeItem(at: recording.url)
        }
        liveText = ""
        phase = .idle
    }

    func stopAndTranscribe() async {
        guard isRecording, let recording = recorder.stop() else { return }
        stopLiveTranscription()
        stopSilenceWatch()
        if Settings.shared.playDictationSounds { NSSound(named: "Pop")?.play() }
        defer { try? FileManager.default.removeItem(at: recording.url) }

        // Under ~0.35 s is almost always a mis-tap.
        guard recording.duration > 0.35 else {
            liveText = ""
            phase = .idle
            return
        }

        phase = .transcribing
        let model = ModelManager.shared.activeModel
        let language = Settings.shared.dictationLanguage

        do {
            let result = try await transcriber.transcribe(
                audio: recording.url, model: model, language: language)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                liveText = ""
                phase = .idle
                return
            }

            let entry = DictationEntry(
                id: UUID().uuidString, text: text,
                durationMs: Int(recording.duration * 1000),
                transcribeMs: Int(result.duration * 1000),
                modelID: model?.id ?? result.engine,
                appName: targetApp?.localizedName, appBundleID: targetApp?.bundleIdentifier,
                language: result.language, createdAt: Date())

            let store = self.store
            Task.detached(priority: .utility) {
                store.insert(entry)
                await SyncClient.shared.pushPending()
            }
            if Settings.shared.autoPasteDictation {
                targetApp?.activate()
                TextInserter.paste(text)
            } else {
                TextInserter.copy(text)
            }
            // Straight out: the text is in the app you were typing into, so
            // leaving a copy floating over the screen is just something else
            // to wait for.
            liveText = ""
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
            scheduleReset(after: 5)
        }
    }

    /// Settings offers this; the recordings themselves are browsed from the
    /// launcher.
    func clearHistory() {
        store.deleteAll()
    }

    private func scheduleReset(after seconds: Double) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.phase = .idle
        }
    }
}
