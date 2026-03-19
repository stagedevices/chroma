#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float  time;
    float  exposure;
    float  beatPhase;   // 0..1
    float  rms;
    float  aspect;
    uint   strobeGuard; // 1/0
};

struct VSOut { float4 pos [[position]]; float2 uv; };

vertex VSOut vertex_fullscreen(uint vid [[vertex_id]]) {
    // Full-screen triangle (no vertex buffer)
    float2 pos;
    pos.x = (vid == 2) ?  3.0 : -1.0;
    pos.y = (vid == 1) ?  3.0 : -1.0;

    VSOut o;
    o.pos = float4(pos, 0, 1);
    // Map to 0..1 UV; lightly correct for aspect in fragment
    o.uv  = 0.5 * (pos + 1.0);
    return o;
}

float pulse(float phase) {
    // Triangle wave 0..1 over the beat (hard pulse near phase 0)
    float x = abs(fract(phase) * 2.0 - 1.0);
    return 1.0 - x;
}

float3 palette(float t) {
    // Smooth aurora-ish palette
    float3 a = float3(0.5, 0.5, 0.5);
    float3 b = float3(0.5, 0.5, 0.5);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}
// Add this helper above fragment_main
inline float triLobe(float2 p, float t) {
    // Three axes 120° apart
    const float2 a0 = float2(1.0, 0.0);
    const float2 a1 = float2(-0.5, 0.8660254);
    const float2 a2 = float2(-0.5, -0.8660254);

    // Soft cos gradients along each axis, averaged
    float g0 = 0.5 + 0.5 * cos(6.28318 * (dot(p, a0) * 0.6 + t * 0.06));
    float g1 = 0.5 + 0.5 * cos(6.28318 * (dot(p, a1) * 0.6 + t * 0.06));
    float g2 = 0.5 + 0.5 * cos(6.28318 * (dot(p, a2) * 0.6 + t * 0.06));
    return (g0 + g1 + g2) / 3.0;
}

fragment float4 fragment_main(VSOut in [[stage_in]],
                              constant Uniforms& u [[buffer(0)]]) {
    // Aspect-corrected UV
    float2 uv = in.uv * float2(u.aspect, 1.0);
    uv -= float2(0.5 * u.aspect, 0.5);

    // Base field: moving radial rings + subtle drift
    float r = length(uv);
    float rings = 0.5 + 0.5 * cos(10.0 * r - u.time * 1.3);

    // Beat + RMS drive brightness
    float beat = /* existing pulse() or keep from your file */ (1.0 - abs(fract(u.beatPhase) * 2.0 - 1.0));
    float energy = clamp(u.rms * 6.0, 0.0, 1.5);

    // Palette over angle + time
    float ang = atan2(uv.y, uv.x);
    float hueT = (ang / 6.28318) + u.time * 0.05;
    float3 base = /* existing palette() */ (float3(0.5) + float3(0.5) * cos(6.28318 * (float3(1.0) * hueT + float3(0.00, 0.33, 0.67))));
    base *= (0.6 + 0.4 * rings);

    // 💜 Triangle gradient (rev-0 look)
    float tri = triLobe(uv * 1.1, u.time);
    float3 triColor = mix(float3(0.95, 0.65, 1.00), float3(0.60, 0.80, 1.00), tri);

    // Blend the two fields
    float triMix = 0.35;                   // tweak feel; 0.25..0.45 looks nice
    float3 color = mix(base, triColor, triMix);

    // Exposure + modulation
    float brightness = u.exposure * (0.65 + 0.35 * beat + 0.5 * energy);
    if (u.strobeGuard == 1) brightness = min(brightness, 0.85);

    color *= brightness;
    return float4(color, 1.0);
}
