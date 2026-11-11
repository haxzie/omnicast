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
        case inserted(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var history: [DictationEntry] = []
    @Published var level: Double = 0

    private let recorder = AudioRecorder()
    private let store: DictationStore
    private let transcriber = CompositeTranscriber()
    private var levelObserver: AnyCancellable?
    private var targetApp: NSRunningApplication?
    private var resetTask: Task<Void, Never>?

    var engineName: String { transcriber.activeName }
    var isRecording: Bool { phase == .recording }

    init(store: DictationStore = .shared) {
        self.store = store
        levelObserver = recorder.$level.sink { [weak self] in self?.level = $0 }
        reloadHistory()
    }

    func reloadHistory() {
        let store = self.store
        Task.detached(priority: .userInitiated) {
            let items = store.recent()
            await MainActor.run { self.history = items }
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

        do {
            _ = try await recorder.start()
            phase = .recording
            if Settings.shared.playDictationSounds { NSSound(named: "Tink")?.play() }
        } catch {
            phase = .failed(error.localizedDescription)
            scheduleReset(after: 4)
        }
    }

    func cancel() {
        guard isRecording else { return }
        if let recording = recorder.stop() {
            try? FileManager.default.removeItem(at: recording.url)
        }
        phase = .idle
    }

    func stopAndTranscribe() async {
        guard isRecording, let recording = recorder.stop() else { return }
        if Settings.shared.playDictationSounds { NSSound(named: "Pop")?.play() }
        defer { try? FileManager.default.removeItem(at: recording.url) }

        // Under ~0.35 s is almost always a mis-tap.
        guard recording.duration > 0.35 else {
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
            history.insert(entry, at: 0)

            if Settings.shared.autoPasteDictation {
                targetApp?.activate()
                TextInserter.paste(text)
            } else {
                TextInserter.copy(text)
            }
            phase = .inserted(text)
            // Just long enough to register the checkmark before the droplet retracts.
            scheduleReset(after: 0.8)
        } catch {
            phase = .failed(error.localizedDescription)
            scheduleReset(after: 5)
        }
    }

    func delete(_ entry: DictationEntry) {
        store.delete(id: entry.id)
        history.removeAll { $0.id == entry.id }
    }

    func clearHistory() {
        store.deleteAll()
        history = []
    }

    func stats() -> DictationStore.Stats { store.stats() }

    private func scheduleReset(after seconds: Double) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.phase = .idle
        }
    }
}
