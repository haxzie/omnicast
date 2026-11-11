#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// The iOS voice waveform: a chromatic band whose four aberrated copies drift
// apart and glow. Ported from the GLSL original; `level` is the only addition,
// so the wave answers to the microphone instead of running on a timer alone.

constant float PI = 3.14159265359;
constant float AMPLITUDE  = 0.32;
constant float FREQ       = 1.1;
constant float ABER_FREQ  = 1.0;
constant float SPEED      = 2.4;
constant float WAVE_SCALE = 0.6;
constant float ABERRATION = 2.6;
constant float THICKNESS  = 3.0;
constant float INTENSITY  = 2.6;
constant float FALLOFF    = 0.42;
constant float EDGE_MASK  = 0.4;
constant float EDGE_INSET = 0.0;
constant float BAND_FILL  = 30000.0;
constant float BAND_THICK = 0.08;
constant float SOFTNESS   = 2.5;
constant float LOW_AMP    = 6.0;
constant float LOW_INT    = 1.5;
constant float MID_ABER   = 0.8;
constant float MID_ABAMP  = 0.05;
constant float MID_SOFT   = 0.4;
constant float HIGH_ABER  = 0.5;
constant float HIGH_ABAMP = 0.06;

static float3 spectral4(int s) {
    float x = float(s);
    return clamp(float3(abs(x - 3.0) - 1.0, 2.0 - abs(x - 2.0), 2.0 - abs(x - 4.0)), 0.0, 1.0);
}

[[ stitchable ]] half4 siriWave(
    float2 position, half4 currentColor, float2 size, float time, float level)
{
    float2 R = size;
    float aspect = R.x / max(R.y, 1.0);
    float2 p = (position + 0.5) * 2.0 / R - 1.0;
    p.x *= aspect;
    float yScreen = p.y;
    p /= max(WAVE_SCALE, 0.1);

    float loud = clamp(level, 0.0, 1.0);
    // Silence still shows a living line; speech drives it past full height.
    // Applied once, to amplitude only — folding it into the band weights too
    // made the response quadratic, which is why the wave barely moved.
    float gain = 0.16 + 1.15 * loud;

    float t = time;
    float low  = clamp(0.45 + 0.45 * sin(t * 0.8) * sin(t * 0.37 + 1.0), 0.0, 1.0);
    float mid  = clamp(0.40 + 0.40 * sin(t * 1.7 + 2.0) * sin(t * 0.53), 0.0, 1.0);
    float high = clamp(0.30 + 0.30 * sin(t * 2.9 + 4.0) * sin(t * 0.71 + 2.0), 0.0, 1.0);

    float drift = fmod(t, 20.0 * PI) * SPEED;

    float xN = p.x / max(aspect, 1.0);
    float env = cos(PI * 0.5 * min(abs(0.5 * xN), 1.0));
    env *= env;

    float A1 = (AMPLITUDE + 0.01 * low * LOW_AMP) * gain;
    float A2 = A1 + (mid * MID_ABAMP + high * HIGH_ABAMP) * gain;
    float AB = ABERRATION + mid * MID_ABER + high * HIGH_ABER;
    float th = 0.01 * THICKNESS;
    float inten = 0.01 * (INTENSITY + low * LOW_INT) * (0.75 + 0.45 * loud);
    float soft = 0.01 * max(0.0, SOFTNESS + mid * MID_SOFT);

    float yMain = A1 * env * sin(p.x * FREQ + drift);

    float bandFillTh = max(BAND_THICK, 1e-4);
    float bandAmt = 1e-4 * BAND_FILL * inten;
    float3 num = float3(0.0);
    float3 den = float3(0.0);

    for (int s = 0; s < 4; s++) {
        float3 hue = spectral4(s);
        den += hue;
        float ab = mix(-AB, AB, float(s) / 3.0);
        float yL = A2 * env * sin(p.x * ABER_FREQ + drift + ab);
        float d = abs(p.y - yL);
        float line = inten / (sqrt(d * d + soft * soft) + th);
        float lo = min(yMain, yL);
        float hi = max(yMain, yL);
        float dBand = max(0.0, max(p.y - hi, lo - p.y));
        float band = bandAmt / (dBand + bandFillTh);
        num += hue * (line + band);
    }

    float3 col = num / max(den, float3(1e-4));

    float dM = abs(p.y - yMain);
    col += 0.5 * inten / (sqrt(dM * dM + soft * soft) + th);

    col = pow(max(col, 0.0), float3(1.5));

    float emT = clamp((abs(yScreen) - 1.0 + EDGE_INSET) / (-max(EDGE_MASK, 1e-4)), 0.0, 1.0);
    float em = emT * emT * (3.0 - 2.0 * emT);
    float gauss = exp(-pow(xN * FALLOFF, 2.0));
    col *= em * gauss;

    // Carry the glow's own alpha rather than relying on an additive blend: a
    // blend mode composites against whatever SwiftUI decides the backdrop is,
    // which can isolate the layer and paint the glass solid black. Brightness
    // becomes opacity, so the dark parts of the shader are simply not there.
    float3 c = min(col, float3(1.8));
    float alpha = clamp(max(c.r, max(c.g, c.b)), 0.0, 1.0);
    return half4(half3(c), half(alpha)) * currentColor.a;
}
