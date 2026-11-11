import SwiftUI

/// The Siri voice waveform, drawn by the Metal shader in `SiriWave.metal`.
///
/// The shader returns the glow's own alpha, so the dark parts of the waveform
/// are transparent and the glass keeps showing through behind it.
struct SiriWaveView: View {
    var level: Double
    /// Lets the wave keep moving while it is not listening, at a low idle.
    var isLive: Bool = true

    /// Shader uniforms are `float`, and a float32 near 7.85e8 — which is what
    /// `timeIntervalSinceReferenceDate` is — steps in jumps of 1024 seconds.
    /// Passing absolute time therefore freezes the wave solid. Elapsed time
    /// from a per-view epoch keeps the value small enough to carry real
    /// sub-frame precision.
    @State private var epoch = Date()

    /// Wrapping keeps the value small over a long session. The seam is a tiny
    /// discontinuity once an hour, in a view that is on screen for seconds.
    private static let wrap: TimeInterval = 3600

    /// Seconds to hand the shader, small enough to survive float32.
    static func shaderTime(_ now: Date, since epoch: Date) -> Float {
        Float(now.timeIntervalSince(epoch).truncatingRemainder(dividingBy: wrap))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let elapsed = Self.shaderTime(timeline.date, since: epoch)
            GeometryReader { proxy in
                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.default.siriWave(
                            .float2(proxy.size),
                            .float(Double(elapsed)),
                            .float(isLive ? min(max(level, 0), 1) : 0)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
