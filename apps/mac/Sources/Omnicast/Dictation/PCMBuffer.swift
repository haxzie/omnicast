import Foundation

/// The 16 kHz mono samples captured so far, and a WAV of them on demand.
///
/// Live transcription needs the audio *while* it is still being recorded.
/// Reading the file the recorder is mid-way through writing is not safe — its
/// header still describes a shorter file — so the samples are also kept here
/// and written out as a complete WAV each time a pass is run.
final class PCMBuffer: @unchecked Sendable {
    static let sampleRate = 16_000

    private let lock = NSLock()
    private var samples: [Int16] = []

    func append(_ newSamples: UnsafePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        lock.withLock {
            samples.append(contentsOf: UnsafeBufferPointer(start: newSamples, count: count))
        }
    }

    func removeAll() {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
    }

    var count: Int { lock.withLock { samples.count } }

    var duration: TimeInterval { Double(count) / Double(Self.sampleRate) }

    func snapshot() -> [Int16] { lock.withLock { samples } }

    /// Writes the samples captured so far as a 16-bit mono WAV.
    ///
    /// `maxSeconds` keeps only the most recent audio. Live passes re-read the
    /// whole file each time, so without a cap a two-minute dictation would be
    /// re-transcribing two minutes every second and fall steadily further
    /// behind. The final transcript is produced from the full recording.
    @discardableResult
    func writeWAV(to url: URL, maxSeconds: TimeInterval? = nil) -> Bool {
        var pcm = snapshot()
        if let maxSeconds {
            let cap = Int(maxSeconds * Double(Self.sampleRate))
            if pcm.count > cap { pcm = Array(pcm.suffix(cap)) }
        }
        guard !pcm.isEmpty else { return false }
        var data = Data()
        data.append(Self.header(frameCount: pcm.count))
        pcm.withUnsafeBufferPointer { data.append(UnsafeRawBufferPointer($0).bindMemory(to: UInt8.self)) }
        return (try? data.write(to: url)) != nil
    }

    /// The canonical 44-byte RIFF/WAVE header for 16-bit mono PCM.
    static func header(frameCount: Int) -> Data {
        let byteCount = frameCount * 2
        var data = Data()
        func ascii(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        ascii("RIFF")
        u32(UInt32(36 + byteCount))
        ascii("WAVE")
        ascii("fmt ")
        u32(16)             // PCM header size
        u16(1)              // format: PCM
        u16(1)              // channels
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))  // byte rate
        u16(2)              // block align
        u16(16)             // bits per sample
        ascii("data")
        u32(UInt32(byteCount))
        return data
    }
}
