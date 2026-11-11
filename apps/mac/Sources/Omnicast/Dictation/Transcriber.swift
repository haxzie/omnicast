import AVFoundation
import Foundation
import Speech

struct Transcription {
    var text: String
    var language: String?
    var duration: TimeInterval
    var engine: String
}

protocol Transcriber: Sendable {
    var name: String { get }
    var isAvailable: Bool { get }
    func transcribe(audio url: URL, model: SpeechModel?, language: String) async throws -> Transcription
}

enum TranscriptionError: LocalizedError {
    case noModelInstalled
    case engineMissing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noModelInstalled:
            // Shown in the droplet, so it has to be short and say what to do.
            return "No speech model yet — open Models and download one."
        case .engineMissing(let hint):
            return hint
        case .failed(let message):
            return message
        }
    }
}

/// Runs a local `whisper.cpp` build against a downloaded ggml model.
///
/// Using the CLI rather than linking libwhisper keeps the app buildable with a
/// plain `swift build` and lets users upgrade whisper.cpp independently. The
/// binary is found via `OMNICAST_WHISPER_BIN`, a Homebrew install, or a copy
/// placed next to the models.
struct WhisperCLITranscriber: Transcriber {
    let name = "whisper.cpp"

    static let searchPaths: [String] = [
        ProcessInfo.processInfo.environment["OMNICAST_WHISPER_BIN"] ?? "",
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
        SQLiteDatabase.supportDirectory.appendingPathComponent("bin/whisper-cli").path,
    ]

    static var binaryURL: URL? {
        searchPaths
            .filter { !$0.isEmpty }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    var isAvailable: Bool { Self.binaryURL != nil }

    func transcribe(audio url: URL, model: SpeechModel?, language: String) async throws
        -> Transcription
    {
        guard let binary = Self.binaryURL else {
            throw TranscriptionError.engineMissing(
                "whisper.cpp was not found. Install it with `brew install whisper-cpp`, or point OMNICAST_WHISPER_BIN at your build."
            )
        }
        guard let model else { throw TranscriptionError.noModelInstalled }

        let modelPath = await ModelManager.shared.location(of: model).path
        let resolvedLanguage = language == "auto" ? (model.isMultilingual ? "auto" : "en") : language

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--model", modelPath,
            "--file", url.path,
            "--language", resolvedLanguage,
            "--no-timestamps",
            "--no-prints",
            "--threads", String(max(2, ProcessInfo.processInfo.activeProcessorCount - 2)),
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let started = Date()
        do {
            try process.run()
        } catch {
            throw TranscriptionError.failed(error.localizedDescription)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "whisper exited \(process.terminationStatus)"
            throw TranscriptionError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let text = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Transcription(
            text: Self.clean(text), language: resolvedLanguage,
            duration: Date().timeIntervalSince(started), engine: name)
    }

    /// whisper.cpp emits `[BLANK_AUDIO]` and similar markers for silence.
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: "\\[[A-Z_ ]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Apple's on-device recognizer. Always present, needs no download, and is the
/// fallback while a model is still downloading.
struct AppleSpeechTranscriber: Transcriber {
    let name = "Apple on-device"

    var isAvailable: Bool {
        SFSpeechRecognizer(locale: .current)?.supportsOnDeviceRecognition ?? false
    }

    /// macOS refuses on-device recognition outright when Siri and Dictation
    /// are switched off, and the system error says so without saying what to
    /// do about it.
    static let disabledHint =
        "Dictation is off in System Settings › Keyboard."

    static func mapped(_ error: Error) -> TranscriptionError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("disabled")
            || message.localizedCaseInsensitiveContains("not available")
        {
            return .engineMissing(disabledHint)
        }
        return .failed(message)
    }

    func transcribe(audio url: URL, model: SpeechModel?, language: String) async throws
        -> Transcription
    {
        let locale = language == "auto" ? Locale.current : Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.engineMissing("Speech recognition is unavailable for \(locale.identifier).")
        }

        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorized == .authorized else {
            throw TranscriptionError.engineMissing(
                "Omnicast needs Speech Recognition access in System Settings › Privacy & Security.")
        }

        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.engineMissing(Self.disabledHint)
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        // Non-negotiable: audio must not leave the machine.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let started = Date()
        let text: String = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    continuation.resume(throwing: Self.mapped(error))
                } else if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }

        return Transcription(
            text: text, language: locale.identifier, duration: Date().timeIntervalSince(started),
            engine: name)
    }
}

/// Picks whisper.cpp when it is set up, otherwise Apple's recognizer.
struct CompositeTranscriber: Transcriber {
    let name = "auto"
    private let whisper = WhisperCLITranscriber()
    private let apple = AppleSpeechTranscriber()

    var isAvailable: Bool { whisper.isAvailable || apple.isAvailable }

    var activeName: String { whisper.isAvailable ? whisper.name : apple.name }

    func transcribe(audio url: URL, model: SpeechModel?, language: String) async throws
        -> Transcription
    {
        if whisper.isAvailable, model != nil {
            do {
                return try await whisper.transcribe(audio: url, model: model, language: language)
            } catch {
                // A broken whisper install shouldn't lose the user's words, but
                // if the fallback can't help either, the whisper failure is the
                // one worth reporting.
                guard let fallback = try? await apple.transcribe(
                    audio: url, model: nil, language: language)
                else { throw error }
                return fallback
            }
        }

        // No model downloaded yet. Apple's recognizer can stand in, but only if
        // the user has Dictation switched on.
        do {
            return try await apple.transcribe(audio: url, model: nil, language: language)
        } catch {
            // whisper.cpp is sitting right there — downloading a model is the
            // fix, and a system error about Siri would only mislead.
            if whisper.isAvailable { throw TranscriptionError.noModelInstalled }
            throw error
        }
    }
}
