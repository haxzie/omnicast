import AVFoundation
import Combine
import Foundation

/// Captures microphone audio into a 16 kHz mono WAV — the format every
/// Whisper-family model expects — and publishes a live level for the HUD.
@MainActor
final class AudioRecorder: ObservableObject {
    enum RecorderError: LocalizedError {
        case microphoneDenied
        case engineUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                return "Omnicast needs microphone access. Enable it in System Settings › Privacy & Security › Microphone."
            case .engineUnavailable(let reason):
                return "Could not start recording: \(reason)"
            }
        }
    }

    @Published private(set) var isRecording = false
    /// 0...1, smoothed, for the waveform.
    @Published private(set) var level: Double = 0

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var startedAt: Date?

    static let sampleRate: Double = 16_000

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// - Returns: the URL being written to.
    @discardableResult
    func start() async throws -> URL {
        guard !isRecording else { throw RecorderError.engineUnavailable("already recording") }
        guard await requestPermission() else { throw RecorderError.microphoneDenied }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnicast-\(UUID().uuidString).wav")

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw RecorderError.engineUnavailable("no input device")
        }

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1,
                interleaved: true)
        else { throw RecorderError.engineUnavailable("unsupported target format") }

        file = try AVAudioFile(
            forWriting: url, settings: targetFormat.settings, commonFormat: .pcmFormatInt16,
            interleaved: true)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            throw RecorderError.engineUnavailable(error.localizedDescription)
        }

        startedAt = Date()
        isRecording = true
        return url
    }

    struct Recording {
        let url: URL
        let duration: TimeInterval
    }

    func stop() -> Recording? {
        guard isRecording else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0

        guard let file else { return nil }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        self.file = nil
        converter = nil
        startedAt = nil
        return Recording(url: file.url, duration: duration)
    }

    /// Called on the audio thread.
    private nonisolated func handle(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        let loudness = Self.loudness(of: buffer)
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Instant attack, quick release: the wave should jump on a
            // syllable and fall back between words.
            self.level = max(loudness, self.level * 0.78)
        }

        Task { @MainActor [weak self] in
            guard let self, let file = self.file, let converter = self.converter else { return }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
            else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0 else { return }
            try? file.write(from: output)
        }
    }

    private nonisolated static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        return AudioLevel.normalized(rms: AudioLevel.rms(channel, count: count, stride: 2))
    }
}
