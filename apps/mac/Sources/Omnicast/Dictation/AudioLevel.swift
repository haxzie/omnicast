import Foundation

/// Turns microphone RMS into the 0...1 level the waveform is drawn from.
///
/// Pulled out of the recorder so the response curve can be tested directly:
/// "the wave barely moves when I talk" is a property of this function, not of
/// the shader.
enum AudioLevel {
    /// Below this is room tone. A built-in mic in a quiet room idles around
    /// -60 dBFS, so the floor sits just above that.
    static let floorDB: Float = -52
    /// Ordinary speech at arm's length peaks near -15 dBFS; anything at or
    /// above this reads as full scale.
    static let ceilingDB: Float = -12

    /// Expands the quiet end. A linear dB map leaves normal speech sitting at
    /// a third of the range, which is what makes a meter look unresponsive.
    static let expansion: Float = 0.65

    static func normalized(rms: Float) -> Double {
        let decibels = 20 * log10(max(rms, 1e-7))
        let position = (decibels - floorDB) / (ceilingDB - floorDB)
        return Double(pow(min(max(position, 0), 1), expansion))
    }

    /// Root mean square of a buffer of samples.
    static func rms(_ samples: UnsafePointer<Float>, count: Int, stride: Int = 1) -> Float {
        guard count > 0 else { return 0 }
        var sum: Float = 0
        var taken = 0
        var index = 0
        while index < count {
            let sample = samples[index]
            sum += sample * sample
            taken += 1
            index += stride
        }
        guard taken > 0 else { return 0 }
        return sqrt(sum / Float(taken))
    }
}
