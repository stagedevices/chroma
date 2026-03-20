#include <metal_stdlib>
using namespace metal;

constant uint kMaxSpectralRings = 48;
constant uint kMaxAttackParticles = 128;
constant uint kMaxPrismImpulses = 32;
constant uint kMaxTunnelShapes = 64;
constant uint kMaxFractalPulses = 32;
constant uint kMaxRiemannAccents = 24;
constant float kPi = 3.14159265358979323846;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct RendererFrameUniforms {
    float time;
    float intensity;
    float scale;
    float motion;
    float diffusion;
    float blackFloor;
    uint modeIndex;
    uint padding;
    float2 resolution;
    float2 centerOffset;

    float ringDecay;
    float featureAmplitude;
    float lowBandEnergy;
    float midBandEnergy;
    float highBandEnergy;
    float attackStrength;
    uint ringCount;
    uint shimmerSampleCount;
    float burstDensity;
    float trailDecay;
    float lensSheen;
    uint particleCount;
    uint attackTrailSampleCount;
    float prismFacetDensity;
    float prismDispersion;
    uint prismFacetSampleCount;
    uint prismDispersionSampleCount;
    uint prismImpulseCount;
    uint prismBlackout;
    float tunnelShapeScale;
    float tunnelDepthSpeed;
    float tunnelReleaseTail;
    uint tunnelVariant;
    uint tunnelShapeCount;
    uint tunnelTrailSampleCount;
    uint tunnelDispersionSampleCount;
    uint tunnelBlackout;
    float fractalDetail;
    float fractalFlowRate;
    float fractalAttackBloom;
    uint fractalPaletteVariant;
    uint fractalOrbitSampleCount;
    uint fractalTrapSampleCount;
    uint fractalPulseCount;
    uint fractalBlackout;
    float fractalFlowPhase;
    float riemannDetail;
    float riemannFlowRate;
    float riemannZeroBloom;
    uint riemannPaletteVariant;
    uint riemannTermCount;
    uint riemannTrapSampleCount;
    uint riemannAccentCount;
    uint riemannBlackout;
    float riemannFlowPhase;
    float2 riemannCameraCenter;
    float riemannCameraZoom;
    float riemannCameraHeading;
    uint fractalPadding0;
    uint fractalPadding1;
    uint fractalPadding2;
    uint noImageInSilence;
    float colorShiftHue;
    float colorShiftSaturation;
    uint colorShiftBlackout;
    float pitchConfidence;
    int stablePitchClass;
    float stablePitchCents;
    uint padding1;
    uint attackIDLow;
    uint attackIDHigh;
    uint padding2;
    uint padding3;
};

struct SpectralRingData {
    float4 positionRadiusWidthIntensity;
    float4 hueDecaySectorActive;
};

struct AttackParticleData {
    float4 positionSizeIntensity;
    float4 velocityHueTrail;
};

struct PrismImpulseData {
    float4 positionRadiusIntensity;
    float4 directionHueDecay;
};

struct TunnelShapeData {
    float4 positionDepthScaleEnvelope;
    float4 forwardHueVariantSeed;
    float4 axisDecaySustainRelease;
};

struct FractalPulseData {
    float4 positionRadiusIntensity;
    float4 hueDecaySeedSector;
};

struct RiemannAccentData {
    float4 positionWidthIntensity;
    float4 directionLengthHueSeed;
    float4 decaySeedSectorActive;
};

vertex VertexOut renderer_fullscreen_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

float2 centeredPoint(float2 uv, float2 resolution, float2 centerOffset) {
    float2 safeResolution = max(resolution, float2(1.0, 1.0));
    float aspect = safeResolution.x / safeResolution.y;
    return float2((uv.x - 0.5) * aspect, uv.y - 0.5) - centerOffset;
}

float wrappedAngleDelta(float a, float b) {
    float delta = a - b;
    return atan2(sin(delta), cos(delta));
}

float3 spectralPalette(float phase) {
    float3 c0 = float3(0.08, 0.32, 0.98);
    float3 c1 = float3(0.12, 0.90, 0.80);
    float3 c2 = float3(0.96, 0.42, 0.98);

    float t0 = smoothstep(0.0, 0.45, phase);
    float t1 = smoothstep(0.45, 1.0, phase);
    float3 blend01 = mix(c0, c1, t0);
    return mix(blend01, c2, t1 * 0.65);
}

float3 fractalPaletteColor(float phase, uint variant) {
    float3 c0;
    float3 c1;
    float3 c2;

    switch (variant % 8u) {
    case 0u:
        c0 = float3(0.02, 0.08, 0.30);
        c1 = float3(0.12, 0.76, 0.88);
        c2 = float3(0.68, 0.94, 1.00);
        break;
    case 1u:
        c0 = float3(0.08, 0.02, 0.18);
        c1 = float3(0.94, 0.22, 0.18);
        c2 = float3(1.00, 0.78, 0.22);
        break;
    case 2u:
        c0 = float3(0.01, 0.05, 0.08);
        c1 = float3(0.05, 0.44, 0.62);
        c2 = float3(0.60, 0.90, 0.94);
        break;
    case 3u:
        c0 = float3(0.10, 0.03, 0.16);
        c1 = float3(0.62, 0.08, 0.94);
        c2 = float3(0.95, 0.42, 1.00);
        break;
    case 4u:
        c0 = float3(0.10, 0.01, 0.06);
        c1 = float3(0.88, 0.08, 0.30);
        c2 = float3(1.00, 0.42, 0.10);
        break;
    case 5u:
        c0 = float3(0.03, 0.04, 0.10);
        c1 = float3(0.16, 0.66, 0.90);
        c2 = float3(0.90, 0.96, 1.00);
        break;
    case 6u:
        c0 = float3(0.02, 0.02, 0.02);
        c1 = float3(0.36, 0.36, 0.36);
        c2 = float3(0.88, 0.88, 0.88);
        break;
    default:
        c0 = float3(0.05, 0.04, 0.14);
        c1 = float3(0.20, 0.58, 0.96);
        c2 = float3(0.92, 0.36, 0.96);
        break;
    }

    float t0 = smoothstep(0.0, 0.48, phase);
    float t1 = smoothstep(0.48, 1.0, phase);
    float3 blend01 = mix(c0, c1, t0);
    return mix(blend01, c2, t1 * 0.68);
}

float hash12(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

float sdBox2D(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sdDiamond2D(float2 p, float2 b) {
    p = abs(p);
    return (p.x + p.y) - b.x;
}

float sdSlab2D(float2 p, float width, float height) {
    float outer = sdBox2D(p, float2(width, height));
    float inner = sdBox2D(p, float2(width * 0.55, height * 0.55));
    return max(outer, -inner);
}

float3 hsvToRgb(float3 c) {
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

float2 complexMul(float2 a, float2 b) {
    return float2((a.x * b.x) - (a.y * b.y), (a.x * b.y) + (a.y * b.x));
}

float2 complexDiv(float2 a, float2 b) {
    float denom = max(dot(b, b), 1e-8);
    return float2(((a.x * b.x) + (a.y * b.y)) / denom, ((a.y * b.x) - (a.x * b.y)) / denom);
}

float2 complexExp(float2 z) {
    float e = exp(z.x);
    return float2(e * cos(z.y), e * sin(z.y));
}

float2 complexLog(float2 z) {
    float magnitudeSq = max(dot(z, z), 1e-12);
    return float2(0.5 * log(magnitudeSq), atan2(z.y, z.x));
}

float2 complexPow(float2 base, float2 exponent) {
    float2 logBase = complexLog(base);
    return complexExp(complexMul(exponent, logBase));
}

float2 complexSin(float2 z) {
    float sinReal = sin(z.x);
    float cosReal = cos(z.x);
    float sinhImag = sinh(z.y);
    float coshImag = cosh(z.y);
    return float2(sinReal * coshImag, cosReal * sinhImag);
}

float2 complexPowReal(float base, float2 exponent) {
    float clampedBase = max(base, 1e-6);
    float logBase = log(clampedBase);
    return complexExp(exponent * logBase);
}

float2 complexGammaLanczosPositive(float2 z) {
    constexpr float g = 7.0;
    constexpr float sqrtTwoPi = 2.5066282746310002;
    constexpr float coeffs[9] = {
        0.9999999999998099,
        676.5203681218851,
        -1259.1392167224028,
        771.3234287776531,
        -176.6150291621406,
        12.507343278686905,
        -0.13857109526572012,
        0.000009984369578019572,
        0.00000015056327351493116
    };

    float2 zMinusOne = z - float2(1.0, 0.0);
    float2 series = float2(coeffs[0], 0.0);

    for (uint index = 1u; index < 9u; index += 1u) {
        float2 denom = zMinusOne + float2(float(index), 0.0);
        series += complexDiv(float2(coeffs[index], 0.0), denom);
    }

    float2 t = zMinusOne + float2(g + 0.5, 0.0);
    float2 power = complexPow(t, zMinusOne + float2(0.5, 0.0));
    float2 decay = complexExp(-t);
    return complexMul(float2(sqrtTwoPi, 0.0), complexMul(series, complexMul(power, decay)));
}

float2 complexGammaLanczos(float2 z) {
    if (z.x < 0.5) {
        float2 oneMinusZ = float2(1.0 - z.x, -z.y);
        float2 sinPiZ = complexSin(z * kPi);
        float2 gammaReflected = complexGammaLanczosPositive(oneMinusZ);
        return complexDiv(float2(kPi, 0.0), complexMul(sinPiZ, gammaReflected));
    }
    return complexGammaLanczosPositive(z);
}

float2 riemannEtaApprox(float2 s, uint termCount);

float2 riemannZetaEtaBranch(float2 s, uint termCount) {
    float2 eta = riemannEtaApprox(s, termCount);
    float2 oneMinusS = float2(1.0 - s.x, -s.y);
    float2 twoPow = complexPowReal(2.0, oneMinusS);
    float2 denom = float2(1.0 - twoPow.x, -twoPow.y);
    return complexDiv(eta, denom);
}

float2 riemannEtaApprox(float2 s, uint termCount) {
    uint terms = clamp(termCount, 2u, 64u);
    float2 sum = float2(0.0);
    for (uint n = 1u; n <= 64u; n += 1u) {
        if (n > terms) { break; }
        float2 nPow = complexPowReal(float(n), s);
        float2 inv = complexDiv(float2(1.0, 0.0), nPow);
        float sign = (n % 2u == 0u) ? -1.0 : 1.0;
        sum += inv * sign;
    }
    return sum;
}

float2 riemannZetaApprox(float2 s, uint termCount) {
    float2 etaBranch = riemannZetaEtaBranch(s, termCount);

    float2 reflected = float2(1.0 - s.x, -s.y);
    float2 reflectedZeta = riemannZetaEtaBranch(reflected, termCount);

    float2 twoPow = complexPowReal(2.0, s);
    float2 piPow = complexPowReal(kPi, float2(s.x - 1.0, s.y));
    float2 sinTerm = complexSin(float2(0.5 * kPi * s.x, 0.5 * kPi * s.y));
    float2 gammaTerm = complexGammaLanczos(float2(1.0 - s.x, -s.y));
    float2 chi = complexMul(complexMul(twoPow, piPow), complexMul(sinTerm, gammaTerm));

    float2 functionalBranch = complexMul(chi, reflectedZeta);
    if (!isfinite(functionalBranch.x) || !isfinite(functionalBranch.y)) {
        return etaBranch;
    }

    // Blend in log-magnitude + wrapped-phase space to suppress branch seams.
    float etaWeight = smoothstep(-0.40, 0.70, s.x);
    float functionalMag = max(length(functionalBranch), 1e-9);
    float etaMag = max(length(etaBranch), 1e-9);
    float blendedMag = exp(mix(log(functionalMag), log(etaMag), etaWeight));
    float functionalPhase = atan2(functionalBranch.y, functionalBranch.x);
    float etaPhase = atan2(etaBranch.y, etaBranch.x);
    float phaseDelta = atan2(sin(etaPhase - functionalPhase), cos(etaPhase - functionalPhase));
    float blendedPhase = functionalPhase + phaseDelta * etaWeight;
    float2 blended = float2(cos(blendedPhase), sin(blendedPhase)) * blendedMag;
    if (!isfinite(blended.x) || !isfinite(blended.y)) {
        return etaWeight >= 0.5 ? etaBranch : functionalBranch;
    }
    return blended;
}

fragment float4 renderer_radial_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.modeIndex == 0u) {
        if (uniforms.colorShiftBlackout > 0u) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        float hue = fract(uniforms.colorShiftHue);
        float saturation = clamp(uniforms.colorShiftSaturation, 0.0, 1.0);
        float value = 0.86;
        float3 color = hsvToRgb(float3(hue, saturation, value));
        return float4(color, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);

    float time = uniforms.time;
    float intensity = uniforms.intensity;
    float scale = max(uniforms.scale, 0.0001);
    float motion = uniforms.motion;
    float diffusion = uniforms.diffusion;
    float blackFloor = uniforms.blackFloor;

    float radius = length(point);
    float angle = atan2(point.y, point.x);
    float waveTime = time * (0.22 + (motion * 1.85));

    float halo = exp(-radius * mix(7.0, 2.1, scale));
    float spokes = 0.5 + 0.5 * sin((angle * mix(4.0, 10.0, motion)) + (waveTime * 1.7));
    float orbit = 0.5 + 0.5 * sin((radius * mix(10.0, 28.0, diffusion)) - (waveTime * 2.1));
    float shell = smoothstep(0.72, 0.04, radius + (orbit * 0.09));
    float flare = pow(max(0.0, 1.0 - radius * mix(2.8, 1.2, scale)), mix(2.4, 0.9, intensity / 1.5));

    float energy = halo * mix(0.45, 1.1, intensity / 1.5);
    energy += shell * spokes * 0.42;
    energy += flare * 0.36;
    energy = max(0.0, energy - (blackFloor * 0.12));

    float3 paletteA = float3(0.04, 0.36, 0.82);
    float3 paletteB = float3(0.10, 0.78, 0.88);
    float3 paletteC = float3(0.62, 0.14, 0.92);
    float palettePhase = 0.5 + 0.5 * sin((angle * 1.8) + waveTime + (radius * 9.0));
    float3 color = mix(paletteA, paletteB, palettePhase);
    color = mix(color, paletteC, orbit * motion * 0.72);
    color *= energy;

    float vignette = smoothstep(1.28, 0.16, radius);
    color *= vignette;
    color += float3(0.012, 0.012, 0.016);

    return float4(color, 1.0);
}

fragment float4 renderer_feedback_contour_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> cameraTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.colorShiftBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float huePhase = fract(uniforms.colorShiftHue) * (kPi * 2.0);
    float t = uniforms.time * (0.24 + (uniforms.motion * 1.8));
    float low = clamp(uniforms.lowBandEnergy, 0.0, 1.0);
    float mid = clamp(uniforms.midBandEnergy, 0.0, 1.0);
    float high = clamp(uniforms.highBandEnergy, 0.0, 1.0);

    float3 cameraCenter = cameraTexture.sample(linearSampler, float2(0.5, 0.5)).rgb;
    float cameraLuma = dot(cameraCenter, float3(0.299, 0.587, 0.114));

    float2 centerA = float2(sin(t * 0.71 + huePhase), cos(t * 0.52 - huePhase)) * (0.25 + low * 0.20);
    float2 centerB = float2(cos(t * 0.44 - huePhase * 0.5), sin(t * 0.84 + huePhase * 0.3)) * (0.32 + mid * 0.18);
    float2 centerC = float2(sin(-t * 0.93 + huePhase * 0.2), cos(t * 0.63 + huePhase * 0.8)) * (0.39 + high * 0.16);

    float blobA = smoothstep(0.34, 0.02, length(point - centerA));
    float blobB = smoothstep(0.28, 0.02, length(point - centerB));
    float blobC = smoothstep(0.24, 0.02, length(point - centerC));
    float blobs = clamp((blobA * 0.62) + (blobB * 0.58) + (blobC * 0.54), 0.0, 1.0);

    float bandFreq = mix(4.0, 14.0, clamp(uniforms.scale, 0.0, 1.0));
    float bandA = 0.5 + (0.5 * sin((point.x * bandFreq) + (point.y * bandFreq * 0.72) + (t * 1.6) + huePhase));
    float bandB = 0.5 + (0.5 * sin((length(point) * (8.0 + uniforms.diffusion * 14.0)) - (t * 1.3) + huePhase * 0.42));
    float banding = mix(bandA, bandB, 0.44 + (high * 0.28));

    float seed = max(blobs, banding * (0.30 + uniforms.diffusion * 0.42));
    seed = clamp(seed + (uniforms.attackStrength * 0.12) + (cameraLuma * 0.08), 0.0, 1.0);
    return float4(seed, seed, seed, 1.0);
}

fragment float4 renderer_feedback_evolve_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> historyTexture [[texture(0)]],
    texture2d<float> contourTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 centered = in.uv - 0.5;
    float spin = 0.0010 + (uniforms.attackStrength * 0.0034);
    float c = cos(spin);
    float s = sin(spin);
    float2 rotated = float2((centered.x * c) - (centered.y * s), (centered.x * s) + (centered.y * c));
    float zoom = 1.005 + (uniforms.motion * 0.014);
    float2 warpedUV = (rotated / zoom) + 0.5;

    float2 texel = 1.0 / max(uniforms.resolution, float2(1.0, 1.0));
    float history = historyTexture.sample(linearSampler, warpedUV).r;
    float blur = 0.0;
    blur += historyTexture.sample(linearSampler, warpedUV + float2(texel.x, 0.0)).r;
    blur += historyTexture.sample(linearSampler, warpedUV + float2(-texel.x, 0.0)).r;
    blur += historyTexture.sample(linearSampler, warpedUV + float2(0.0, texel.y)).r;
    blur += historyTexture.sample(linearSampler, warpedUV + float2(0.0, -texel.y)).r;
    blur *= 0.25;

    float contour = contourTexture.sample(linearSampler, in.uv).r;
    float decay = 0.90 + ((1.0 - uniforms.blackFloor) * 0.06);
    float injection = contour * (0.40 + (uniforms.attackStrength * 0.35));
    float evolved = max(mix(history, blur, 0.24), injection);
    evolved = clamp((evolved * decay) + (contour * 0.06), 0.0, 1.0);
    return float4(evolved, evolved, evolved, 1.0);
}

fragment float4 renderer_feedback_present_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> feedbackTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.colorShiftBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float field = feedbackTexture.sample(linearSampler, uv).r;
    float2 texel = 1.0 / max(uniforms.resolution, float2(1.0, 1.0));
    float gradX = feedbackTexture.sample(linearSampler, uv + float2(texel.x, 0.0)).r
        - feedbackTexture.sample(linearSampler, uv + float2(-texel.x, 0.0)).r;
    float gradY = feedbackTexture.sample(linearSampler, uv + float2(0.0, texel.y)).r
        - feedbackTexture.sample(linearSampler, uv + float2(0.0, -texel.y)).r;
    float gradient = min(length(float2(gradX, gradY)) * 3.5, 1.0);

    float hue = fract(uniforms.colorShiftHue);
    float saturation = clamp(uniforms.colorShiftSaturation, 0.0, 1.0);
    float hueB = fract(hue + 0.08 + (uniforms.midBandEnergy * 0.12) - (uniforms.lowBandEnergy * 0.05));
    float hueC = fract(hue - 0.09 + (uniforms.highBandEnergy * 0.15));

    float3 colorA = hsvToRgb(float3(hue, saturation, 0.92));
    float3 colorB = hsvToRgb(float3(hueB, clamp(saturation * 0.92, 0.0, 1.0), 0.96));
    float3 colorC = hsvToRgb(float3(hueC, clamp(saturation * 0.86, 0.0, 1.0), 0.88));

    float blend = smoothstep(0.12, 0.92, field);
    float ribbon = 0.5 + (0.5 * sin((field * (12.0 + uniforms.scale * 20.0)) + (uniforms.time * (0.6 + uniforms.motion * 2.0))));
    float3 color = mix(colorA, colorB, blend);
    color = mix(color, colorC, ribbon * (0.22 + uniforms.diffusion * 0.38));

    float edgeGlow = smoothstep(0.08, 0.35, gradient) * (0.14 + uniforms.attackStrength * 0.16);
    color += edgeGlow;

    float value = smoothstep(0.04, 0.98, field);
    color *= mix(0.28, 1.0, value);
    color = max(color - (uniforms.blackFloor * 0.18), float3(0.0));
    return float4(color, 1.0);
}

fragment float4 renderer_spectral_ring_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device SpectralRingData* rings [[buffer(1)]]
) {
    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);

    float3 color = float3(0.0);
    float energy = 0.0;
    uint ringCount = min(uniforms.ringCount, kMaxSpectralRings);

    for (uint index = 0; index < ringCount; index += 1) {
        SpectralRingData ring = rings[index];
        float2 ringCenter = ring.positionRadiusWidthIntensity.xy;
        float ringRadius = ring.positionRadiusWidthIntensity.z;
        float ringWidth = max(ring.positionRadiusWidthIntensity.w, 0.002);
        float ringIntensity = max(ring.hueDecaySectorActive.w, 0.0);
        if (ringIntensity <= 0.0001) {
            continue;
        }

        float hueShift = ring.hueDecaySectorActive.x;
        float sector = ring.hueDecaySectorActive.z;

        float2 fromCenter = point - ringCenter;
        float distToShell = abs(length(fromCenter) - ringRadius);
        float shell = exp(-pow(distToShell / ringWidth, 2.0) * 3.2);

        float ringAngle = atan2(fromCenter.y, fromCenter.x);
        float sectorAngle = ((sector + 0.5) / 12.0) * (2.0 * kPi);
        float arcDelta = abs(wrappedAngleDelta(ringAngle, sectorAngle));
        float arcMask = smoothstep(1.1, 0.22, arcDelta);

        float localEnergy = shell * mix(0.46, 1.0, arcMask) * ringIntensity;
        energy += localEnergy;

        float3 ringColor = spectralPalette(fract(hueShift + (shell * 0.16) + (uniforms.time * 0.03)));
        color += ringColor * localEnergy;
    }

    float ambience = (0.010 + uniforms.featureAmplitude * 0.010) * (0.58 + uniforms.ringDecay * 0.42);
    color += float3(0.02, 0.04, 0.06) * ambience;

    return float4(color, max(energy, ambience));
}

fragment float4 renderer_spectral_lens_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> ringField [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;

    float ringEnergy = ringField.sample(linearSampler, uv).a;
    float split = (0.0012 + (uniforms.motion * 0.012)) * (0.55 + (uniforms.attackStrength * 0.45));

    float2 gradOffset = float2(1.0 / max(uniforms.resolution.x, 1.0), 1.0 / max(uniforms.resolution.y, 1.0));
    float gx0 = ringField.sample(linearSampler, uv - float2(gradOffset.x, 0.0)).a;
    float gx1 = ringField.sample(linearSampler, uv + float2(gradOffset.x, 0.0)).a;
    float gy0 = ringField.sample(linearSampler, uv - float2(0.0, gradOffset.y)).a;
    float gy1 = ringField.sample(linearSampler, uv + float2(0.0, gradOffset.y)).a;
    float2 gradient = float2(gx1 - gx0, gy1 - gy0);

    float2 lensWarp = gradient * (0.016 + (ringEnergy * 0.032));
    float2 splitVec = float2(split, split * 0.5);

    float r = ringField.sample(linearSampler, uv + lensWarp + splitVec).r;
    float g = ringField.sample(linearSampler, uv + lensWarp).g;
    float b = ringField.sample(linearSampler, uv + lensWarp - splitVec).b;

    float3 color = float3(r, g, b);
    color += float3(0.5, 0.6, 0.8) * ringEnergy * 0.12;

    return float4(color, 1.0);
}

fragment float4 renderer_spectral_shimmer_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> lensField [[texture(0)]],
    texture2d<float> ringField [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float pointLength = max(length(point), 0.0001);
    float2 rayDir = point / pointLength;

    uint sampleCount = clamp(uniforms.shimmerSampleCount, 4u, 16u);
    float3 shimmer = float3(0.0);

    for (uint index = 0; index < 16; index += 1) {
        if (index >= sampleCount) {
            break;
        }

        float t = (float(index) + 1.0) / float(sampleCount);
        float2 offset = rayDir * t * (0.02 + uniforms.motion * 0.08);

        float3 lensSample = lensField.sample(linearSampler, uv - offset).rgb;
        float ringEnergy = ringField.sample(linearSampler, uv - (offset * 0.6)).a;

        float weight = (1.0 - t) * (0.7 + (ringEnergy * 0.8));
        shimmer += lensSample * weight;
    }

    float angle = atan2(point.y, point.x);
    float lenticular = 0.5 + 0.5 * sin((angle * 12.0) + (uniforms.time * 2.6));
    shimmer *= mix(0.16, 0.62, lenticular);

    return float4(shimmer, 1.0);
}

fragment float4 renderer_spectral_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> ringField [[texture(0)]],
    texture2d<float> lensField [[texture(1)]],
    texture2d<float> shimmerField [[texture(2)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float3 ring = ringField.sample(linearSampler, uv).rgb;
    float3 lens = lensField.sample(linearSampler, uv).rgb;
    float3 shimmer = shimmerField.sample(linearSampler, uv).rgb;

    float3 composed = (ring * 0.55) + (lens * 1.15) + (shimmer * 0.85);

    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * 0.28) + (point.x * 3.2) + (point.y * 2.3));
    float3 ambient = mix(float3(0.0030, 0.0046, 0.0068), float3(0.012, 0.018, 0.024), ambientPhase);

    if (uniforms.noImageInSilence > 0u) {
        float silenceOpen = smoothstep(0.05, 0.18, uniforms.featureAmplitude);
        composed *= mix(0.08, 1.0, silenceOpen);
        ambient *= mix(0.04, 1.0, silenceOpen);
    }

    composed += ambient;
    composed = max(composed - (uniforms.blackFloor * 0.11), float3(0.0));

    float vignette = smoothstep(1.42, 0.14, radius);
    composed *= vignette;

    return float4(composed, 1.0);
}

fragment float4 renderer_attack_particle_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device AttackParticleData* particles [[buffer(1)]]
) {
    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float3 color = float3(0.0);
    float energy = 0.0;
    uint particleCount = min(uniforms.particleCount, kMaxAttackParticles);

    for (uint index = 0; index < particleCount; index += 1) {
        AttackParticleData particle = particles[index];
        float2 position = particle.positionSizeIntensity.xy;
        float size = max(particle.positionSizeIntensity.z, 0.003);
        float intensity = max(particle.positionSizeIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float2 velocity = particle.velocityHueTrail.xy;
        float velocityLength = max(length(velocity), 0.0001);
        float2 dir = velocity / velocityLength;
        float2 tangent = float2(-dir.y, dir.x);
        float hue = particle.velocityHueTrail.z;
        float trail = clamp(particle.velocityHueTrail.w, 0.0, 1.0);

        float2 delta = point - position;
        float along = dot(delta, dir);
        float across = dot(delta, tangent);

        float sigmaAlong = size * mix(2.2, 8.6, trail);
        float sigmaAcross = size * mix(1.8, 0.9, trail);
        float streak = exp(-((along * along) / max(sigmaAlong * sigmaAlong, 1e-5) +
                             (across * across) / max(sigmaAcross * sigmaAcross, 1e-5)) * 1.7);
        float core = exp(-(dot(delta, delta) / max(size * size, 1e-5)) * 2.4);
        float localEnergy = (core * 0.78 + streak * 0.56) * intensity;

        float phase = fract(hue + (core * 0.14) + (uniforms.time * 0.05));
        float3 particleColor = spectralPalette(phase);
        color += particleColor * localEnergy;
        energy += localEnergy;
    }

    float idleSheen = (0.004 + (uniforms.featureAmplitude * 0.010)) * (0.65 + (uniforms.lensSheen * 0.35));
    color += float3(0.015, 0.020, 0.030) * idleSheen;
    return float4(color, max(energy, idleSheen));
}

fragment float4 renderer_attack_trail_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> particleField [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float pointLength = max(length(point), 0.0001);
    float2 rayDir = point / pointLength;
    float2 tangent = float2(-rayDir.y, rayDir.x);

    uint sampleCount = clamp(uniforms.attackTrailSampleCount, 4u, 14u);
    float3 trail = float3(0.0);

    for (uint index = 0; index < 16; index += 1) {
        if (index >= sampleCount) {
            break;
        }

        float t = (float(index) + 1.0) / float(sampleCount);
        float radialStep = t * (0.018 + uniforms.trailDecay * 0.085);
        float sheenOffset = (0.001 + uniforms.lensSheen * 0.012) * (0.5 + t);

        float3 sampleA = particleField.sample(linearSampler, uv - (rayDir * radialStep) + (tangent * sheenOffset)).rgb;
        float3 sampleB = particleField.sample(linearSampler, uv - (rayDir * radialStep) - (tangent * sheenOffset)).rgb;
        float weight = (1.0 - t) * (0.5 + uniforms.lensSheen * 1.0);

        trail += (sampleA + sampleB) * (0.5 * weight);
    }

    float angle = atan2(point.y, point.x);
    float lenticular = 0.5 + 0.5 * sin((angle * 14.0) + (uniforms.time * 3.1));
    trail *= mix(0.16, 0.95, lenticular) * mix(0.45, 1.15, uniforms.lensSheen);

    return float4(trail, 1.0);
}

fragment float4 renderer_attack_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> particleField [[texture(0)]],
    texture2d<float> trailField [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float3 particle = particleField.sample(linearSampler, uv).rgb;
    float3 trail = trailField.sample(linearSampler, uv).rgb;
    float3 composed = (particle * 1.06) + (trail * mix(0.70, 1.28, uniforms.lensSheen));

    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * 0.33) + (point.x * 2.8) + (point.y * 2.1));
    float3 ambient = mix(float3(0.0022, 0.0032, 0.0048), float3(0.008, 0.012, 0.018), ambientPhase);

    if (uniforms.noImageInSilence > 0u) {
        float silenceOpen = smoothstep(0.05, 0.18, uniforms.featureAmplitude);
        composed *= mix(0.07, 1.0, silenceOpen);
        ambient *= mix(0.05, 1.0, silenceOpen);
    }

    composed += ambient;
    composed = max(composed - (uniforms.blackFloor * 0.12), float3(0.0));

    float vignette = smoothstep(1.42, 0.14, radius);
    composed *= vignette;
    return float4(composed, 1.0);
}

fragment float4 renderer_prism_facet_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.prismBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float density = mix(2.4, 13.5, clamp(uniforms.prismFacetDensity, 0.0, 1.0));
    float flowTime = uniforms.time * (0.16 + (uniforms.motion * 1.7));
    uint sampleCount = clamp(uniforms.prismFacetSampleCount, 4u, 20u);

    float3 color = float3(0.0);
    float energy = 0.0;
    for (uint index = 0; index < 20; index += 1) {
        if (index >= sampleCount) {
            break;
        }

        float t = (float(index) + 0.5) / float(sampleCount);
        float2 warp = float2(
            sin((uv.y + (t * 1.7)) * density + flowTime * (0.8 + t)),
            cos((uv.x - (t * 1.5)) * density + flowTime * (1.1 + (t * 0.9)))
        ) * (0.045 + uniforms.diffusion * 0.13);

        float2 cell = (point + warp) * density;
        float2 edgeDist = abs(fract(cell) - 0.5);
        float ridge = exp(-pow(min(edgeDist.x, edgeDist.y) * (11.0 + (uniforms.prismFacetDensity * 20.0)), 2.0));
        float causticPhase = 0.5 + 0.5 * sin(dot(cell, float2(0.8, 1.3)) + flowTime * (0.9 + t));
        float localEnergy = ridge * mix(0.36, 1.0, causticPhase);
        float weight = (1.0 - (t * 0.5)) / float(sampleCount);
        localEnergy *= weight;

        float hue = fract((t * 0.42) + (uniforms.prismDispersion * 0.18) + dot(cell, float2(0.018, 0.027)));
        color += spectralPalette(hue) * localEnergy;
        energy += localEnergy;
    }

    color += float3(0.003, 0.006, 0.010) * (0.35 + uniforms.featureAmplitude * 0.65);
    return float4(color, energy);
}

fragment float4 renderer_prism_dispersion_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> facetField [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float facetEnergy = facetField.sample(linearSampler, uv).a;
    float split = (0.0008 + (uniforms.prismDispersion * 0.0075)) * (0.55 + (uniforms.attackStrength * 0.45));
    float2 texel = 1.0 / max(uniforms.resolution, float2(1.0, 1.0));

    float gx0 = facetField.sample(linearSampler, uv - float2(texel.x, 0.0)).a;
    float gx1 = facetField.sample(linearSampler, uv + float2(texel.x, 0.0)).a;
    float gy0 = facetField.sample(linearSampler, uv - float2(0.0, texel.y)).a;
    float gy1 = facetField.sample(linearSampler, uv + float2(0.0, texel.y)).a;
    float2 gradient = float2(gx1 - gx0, gy1 - gy0);
    float2 bend = gradient * (0.010 + (facetEnergy * 0.034));
    float2 splitVec = float2(split, split * 0.45);

    float r = facetField.sample(linearSampler, uv + bend + splitVec).r;
    float g = facetField.sample(linearSampler, uv + bend).g;
    float b = facetField.sample(linearSampler, uv + bend - splitVec).b;
    float3 color = float3(r, g, b);
    color += spectralPalette(fract((uv.x * 0.23) + (uv.y * 0.17) + uniforms.time * 0.02)) * facetEnergy * 0.08;
    return float4(color, max(facetEnergy, 0.001));
}

fragment float4 renderer_prism_attack_accents_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device PrismImpulseData* impulses [[buffer(1)]],
    texture2d<float> facetField [[texture(0)]],
    texture2d<float> dispersionField [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    uint impulseCount = min(uniforms.prismImpulseCount, kMaxPrismImpulses);

    float3 color = float3(0.0);
    float energy = 0.0;

    for (uint index = 0; index < impulseCount; index += 1) {
        PrismImpulseData impulse = impulses[index];
        float2 position = impulse.positionRadiusIntensity.xy;
        float radius = max(impulse.positionRadiusIntensity.z, 0.004);
        float intensity = max(impulse.positionRadiusIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float2 direction = impulse.directionHueDecay.xy;
        float directionLength = max(length(direction), 0.0001);
        float2 dir = direction / directionLength;
        float2 tangent = float2(-dir.y, dir.x);
        float hue = impulse.directionHueDecay.z;
        float decay = impulse.directionHueDecay.w;

        float2 delta = point - position;
        float along = dot(delta, dir);
        float across = dot(delta, tangent);

        float shard = exp(-((across * across) / max(radius * radius * 0.45, 1e-5))) *
            exp(-(max(along, 0.0) * max(along, 0.0)) / max(radius * radius * 7.8, 1e-5));
        float halo = exp(-(dot(delta, delta) / max(radius * radius * 1.6, 1e-5)));
        float localEnergy = (shard * 0.90 + halo * 0.32) * intensity * (0.55 + (decay * 0.45));

        float3 impulseColor = spectralPalette(fract(hue + (along * 0.20) + (uniforms.time * 0.05)));
        color += impulseColor * localEnergy;
        energy += localEnergy;
    }

    float3 facet = facetField.sample(linearSampler, uv).rgb;
    float3 dispersion = dispersionField.sample(linearSampler, uv).rgb;
    color += (facet * 0.06) + (dispersion * (0.14 + uniforms.prismDispersion * 0.16));
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_prism_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> facetField [[texture(0)]],
    texture2d<float> dispersionField [[texture(1)]],
    texture2d<float> accentField [[texture(2)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.prismBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float4 facet = facetField.sample(linearSampler, uv);
    float4 dispersion = dispersionField.sample(linearSampler, uv);
    float4 accents = accentField.sample(linearSampler, uv);

    float3 composed = (facet.rgb * 0.52) + (dispersion.rgb * 1.08) + (accents.rgb * 1.10);
    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * 0.24) + (point.x * 2.7) + (point.y * 3.2));
    float3 ambient = mix(float3(0.0015, 0.0024, 0.0040), float3(0.008, 0.012, 0.016), ambientPhase);
    composed += ambient;
    composed = max(composed - (uniforms.blackFloor * 0.12), float3(0.0));

    float vignette = smoothstep(1.55, 0.14, radius);
    composed *= vignette;
    return float4(composed, 1.0);
}

fragment float4 renderer_tunnel_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.tunnelBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float squareRadius = max(abs(point.x), abs(point.y));
    float centerRadius = length(point);
    float invDepth = 1.0 / max(squareRadius + 0.10, 0.10);
    float depthTime = uniforms.time * (0.45 + (uniforms.tunnelDepthSpeed * 2.40));
    float depthPhase = invDepth + depthTime;

    float ringDensity = mix(0.30, 0.72, clamp(uniforms.tunnelShapeScale, 0.0, 1.0));
    float ringSlice = abs(fract(depthPhase * ringDensity) - 0.5);
    float ringShell = exp(-pow(ringSlice * mix(22.0, 54.0, uniforms.tunnelShapeScale), 2.0));

    float2 latticeUV = point * invDepth;
    float latticeScale = mix(2.8, 9.5, clamp(uniforms.tunnelShapeScale, 0.0, 1.0));
    float2 latticeCell = abs(fract((latticeUV * latticeScale) + float2(depthPhase * 0.14, depthPhase * 0.11)) - 0.5);
    float latticeLines = exp(-pow(min(latticeCell.x, latticeCell.y) * mix(18.0, 42.0, uniforms.tunnelShapeScale), 2.0));

    float3 laneNoise = float3(
        sin((latticeUV.x * 2.6) + depthPhase * 0.18),
        sin((latticeUV.y * 2.1) - depthPhase * 0.14),
        sin(((latticeUV.x + latticeUV.y) * 1.7) + depthPhase * 0.11)
    );
    float flow = 0.5 + (0.5 * dot(laneNoise, float3(0.37, 0.33, 0.30)));
    float fog = exp(-squareRadius * mix(3.6, 1.5, uniforms.tunnelShapeScale));
    float wallMask = smoothstep(1.34, 0.10, squareRadius);
    float centerWell = exp(-pow(centerRadius * 9.0, 2.0));

    float energy = ((ringShell * 0.24) + (latticeLines * 0.30) + (fog * 0.10)) * wallMask;
    energy *= mix(0.62, 0.94, flow);
    energy = max(0.0, energy - (centerWell * 0.18));

    float hue = fract((latticeUV.x * 0.07) + (latticeUV.y * 0.05) + (depthPhase * 0.03));
    float3 prism = spectralPalette(hue);
    float3 baseA = float3(0.004, 0.008, 0.016);
    float3 baseB = float3(0.016, 0.028, 0.050);
    float3 base = mix(baseA, baseB, fog);
    float3 color = (base * (0.26 + (0.42 * fog))) + (prism * energy * 0.34);
    color += float3(0.0010, 0.0018, 0.0030) * (0.12 + (uniforms.featureAmplitude * 0.58));
    if (!isfinite(color.x) || !isfinite(color.y) || !isfinite(color.z) || !isfinite(energy)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return float4(clamp(color, float3(0.0), float3(6.0)), 1.0);
}

fragment float4 renderer_tunnel_shapes_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device TunnelShapeData* shapes [[buffer(1)]],
    texture2d<float> tunnelField [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.tunnelBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float3 color = float3(0.0);
    float energy = 0.0;
    uint shapeCount = min(uniforms.tunnelShapeCount, kMaxTunnelShapes);

    for (uint index = 0; index < shapeCount; index += 1) {
        TunnelShapeData shape = shapes[index];
        float2 lane = shape.positionDepthScaleEnvelope.xy;
        float depth = max(shape.positionDepthScaleEnvelope.z, 0.08);
        float scale = max(shape.positionDepthScaleEnvelope.w, 0.001);
        float envelope = max(shape.forwardHueVariantSeed.w, 0.0);
        if (envelope <= 0.0001) {
            continue;
        }

        float perspective = 1.0 / (0.35 + depth);
        float2 projected = lane * perspective;
        float size = scale * perspective * mix(0.95, 2.10, uniforms.tunnelShapeScale);
        float2 local = (point - projected) / max(size, 0.0001);

        float axisAngle = atan2(shape.axisDecaySustainRelease.y, shape.axisDecaySustainRelease.x);
        float axisRotation = axisAngle + (shape.axisDecaySustainRelease.z * 0.35) + (uniforms.time * 0.08);
        float c = cos(axisRotation);
        float s = sin(axisRotation);
        float2 rotated = float2((local.x * c) - (local.y * s), (local.x * s) + (local.y * c));

        float variant = shape.forwardHueVariantSeed.z;
        float distance;
        if (variant < 0.5) {
            distance = sdBox2D(rotated, float2(0.62, 0.38));
        } else if (variant < 1.5) {
            distance = sdDiamond2D(rotated, float2(0.88, 0.88));
        } else {
            distance = sdSlab2D(rotated, 0.68, 0.28);
        }

        float edgeGlow = exp(-pow(max(distance, 0.0) * 2.6, 2.0));
        float core = smoothstep(0.34, -0.46, distance) * 1.05;
        float outline = smoothstep(0.24, 0.0, abs(distance)) * 1.30;
        float releaseMix = shape.axisDecaySustainRelease.w;
        float releaseDamp = mix(1.0, 0.20, releaseMix);
        float depthFade = smoothstep(9.0, 0.08, depth);
        float localEnergy = (edgeGlow + core + outline) * envelope * releaseDamp * depthFade;
        localEnergy *= (1.55 + (uniforms.attackStrength * 1.20));

        float hue = fract(shape.forwardHueVariantSeed.y + (shape.forwardHueVariantSeed.x * 0.03) + (local.x * 0.06));
        float3 shapeColor = spectralPalette(hue);
        float3 energizedColor = mix(shapeColor, float3(1.0), 0.26);
        color += energizedColor * localEnergy;
        energy += localEnergy;
    }

    float3 field = tunnelField.sample(linearSampler, in.uv).rgb;
    color += field * 0.20;
    if (!isfinite(color.x) || !isfinite(color.y) || !isfinite(color.z) || !isfinite(energy)) {
        return float4(clamp(field, float3(0.0), float3(4.0)), 1.0);
    }
    return float4(clamp(color, float3(0.0), float3(2.4)), 1.0);
}

fragment float4 renderer_tunnel_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> tunnelField [[texture(0)]],
    texture2d<float> shapeField [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.tunnelBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float squareRadius = max(abs(point.x), abs(point.y));

    float3 field = tunnelField.sample(linearSampler, uv).rgb;
    float3 shapes = shapeField.sample(linearSampler, uv).rgb;
    float2 toVanishing = normalize((-point) + float2(1e-4, 1e-4));
    float2 tangent = float2(-toVanishing.y, toVanishing.x);

    uint sampleCount = clamp(uniforms.tunnelTrailSampleCount, 3u, 12u);
    uint dispersionSamples = clamp(uniforms.tunnelDispersionSampleCount, 3u, 12u);
    float3 trails = float3(0.0);
    for (uint index = 0; index < 12; index += 1) {
        if (index >= sampleCount) { break; }
        float t = (float(index) + 1.0) / float(sampleCount);
        float2 offset = toVanishing * t * (0.012 + uniforms.tunnelDepthSpeed * 0.060);
        trails += shapeField.sample(linearSampler, uv - offset).rgb * (1.0 - t);
    }

    float3 split = float3(0.0);
    for (uint index = 0; index < 12; index += 1) {
        if (index >= dispersionSamples) { break; }
        float t = (float(index) + 1.0) / float(dispersionSamples);
        float spread = t * (0.0008 + uniforms.tunnelReleaseTail * 0.0065);
        float3 rgb;
        rgb.r = shapeField.sample(linearSampler, uv + (tangent * spread)).r;
        rgb.g = shapeField.sample(linearSampler, uv).g;
        rgb.b = shapeField.sample(linearSampler, uv - (tangent * spread)).b;
        split += rgb * (1.0 - t);
    }

    float3 composed = (field * 0.35) + (shapes * 2.55) + (trails * 1.35) + (split * 1.12);
    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * 0.30) + (point.x * 2.6) + (point.y * 2.1));
    float3 ambient = mix(float3(0.0012, 0.0018, 0.0030), float3(0.0065, 0.0105, 0.0140), ambientPhase);
    composed += ambient;
    composed = max(composed - (uniforms.blackFloor * 0.14), float3(0.0));

    float vignette = smoothstep(1.62, 0.12, squareRadius);
    composed *= vignette;
    if (!isfinite(composed.x) || !isfinite(composed.y) || !isfinite(composed.z)) {
        return float4(clamp(field, float3(0.0), float3(3.0)), 1.0);
    }
    return float4(clamp(composed, float3(0.0), float3(1.8)), 1.0);
}

fragment float4 renderer_fractal_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.fractalBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float detail = clamp(uniforms.fractalDetail, 0.0, 1.0);
    float flowRate = clamp(uniforms.fractalFlowRate, 0.0, 1.0);
    float flow = fract(uniforms.fractalFlowPhase + (uniforms.time * (0.03 + (flowRate * 0.24))));
    float pitchPhase = 0.0;
    if (uniforms.pitchConfidence > 0.6 && uniforms.stablePitchClass >= 0) {
        pitchPhase = (float(uniforms.stablePitchClass) / 12.0) + (clamp(uniforms.stablePitchCents, -50.0, 50.0) / 50.0) * 0.08;
    }

    float cAngle = (flow * (2.0 * kPi)) + (pitchPhase * 0.45);
    float cMagnitude = mix(0.48, 0.82, detail) + (uniforms.featureAmplitude * 0.08);
    float2 c = float2(cos(cAngle), sin(cAngle)) * cMagnitude;
    c += float2(sin(flow * 3.2), cos(flow * 2.6)) * (0.04 + uniforms.motion * 0.07);

    float zoom = mix(0.92, 2.45, detail);
    float2 z = point * zoom;
    z += float2(
        sin((point.y * 2.0) + flow * 4.2),
        cos((point.x * 1.8) - flow * 3.7)
    ) * (0.02 + (uniforms.diffusion * 0.08));

    uint orbitSamples = clamp(uniforms.fractalOrbitSampleCount, 12u, 64u);
    uint trapSamples = clamp(uniforms.fractalTrapSampleCount, 4u, 16u);

    float trapLine = 1e6;
    float trapRing = 1e6;
    float trapCross = 1e6;
    float escape = 0.0;

    for (uint index = 0; index < 64; index += 1) {
        if (index >= orbitSamples) {
            break;
        }

        float2 z2 = float2((z.x * z.x) - (z.y * z.y), (2.0 * z.x * z.y)) + c;
        z = z2;

        float ringTarget = 0.75 + (0.35 * sin(flow * 6.0 + float(index) * 0.09));
        float line = abs((z.x * 0.68) + (z.y * 0.32));
        float ring = abs(length(z) - ringTarget);
        float cross = min(abs(z.x), abs(z.y));

        trapLine = min(trapLine, line);
        trapRing = min(trapRing, ring);
        trapCross = min(trapCross, cross);

        if (dot(z, z) > 24.0) {
            escape = float(index) / float(max(orbitSamples, 1u));
            break;
        }
    }

    float trapLineEnergy = exp(-trapLine * mix(16.0, 34.0, detail));
    float trapRingEnergy = exp(-trapRing * mix(18.0, 40.0, detail));
    float trapCrossEnergy = exp(-trapCross * mix(22.0, 52.0, detail));

    float trapBlend = 0.0;
    for (uint index = 0; index < 16; index += 1) {
        if (index >= trapSamples) {
            break;
        }
        float t = (float(index) + 1.0) / float(trapSamples);
        trapBlend += (trapLineEnergy * (1.0 - t)) + (trapRingEnergy * t * 0.8) + (trapCrossEnergy * 0.6);
    }
    trapBlend /= float(max(trapSamples, 1u));

    float3 color = fractalPaletteColor(fract(flow + (trapRing * 0.28) + (escape * 0.36)), uniforms.fractalPaletteVariant);
    float3 accentColor = fractalPaletteColor(fract(flow + 0.35 + trapLine * 0.24), uniforms.fractalPaletteVariant);

    float energy = trapBlend * (0.55 + (uniforms.featureAmplitude * 0.45));
    energy += trapRingEnergy * (0.18 + uniforms.attackStrength * 0.28);
    energy = max(energy - (uniforms.blackFloor * 0.07), 0.0);

    float3 fieldColor = (color * energy * 0.92) + (accentColor * trapCrossEnergy * 0.28);
    fieldColor += float3(0.0018, 0.0026, 0.0042) * (0.25 + (uniforms.featureAmplitude * 0.75));
    return float4(fieldColor, max(energy, 0.0001));
}

fragment float4 renderer_fractal_accents_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device FractalPulseData* pulses [[buffer(1)]],
    texture2d<float> fieldTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.fractalBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    uint pulseCount = min(uniforms.fractalPulseCount, kMaxFractalPulses);
    float3 color = float3(0.0);
    float energy = 0.0;

    for (uint index = 0; index < pulseCount; index += 1) {
        FractalPulseData pulse = pulses[index];
        float2 position = pulse.positionRadiusIntensity.xy;
        float radius = max(pulse.positionRadiusIntensity.z, 0.003);
        float intensity = max(pulse.positionRadiusIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float hue = pulse.hueDecaySeedSector.x;
        float decay = pulse.hueDecaySeedSector.y;
        float seed = pulse.hueDecaySeedSector.z;
        float2 delta = point - position;
        float dist = length(delta);
        float ring = exp(-pow(abs(dist - radius) / max(radius * 0.24, 0.006), 2.0) * 2.6);
        float halo = exp(-(dist * dist) / max(radius * radius * 1.9, 1e-5));
        float shard = exp(-pow(abs(delta.x * 0.72 - delta.y * 0.35) / max(radius * 0.55, 0.01), 2.0));
        float localEnergy = (ring * 0.90 + halo * 0.30 + shard * 0.34) * intensity * (0.54 + decay * 0.46);
        localEnergy *= 0.52 + (uniforms.fractalAttackBloom * 0.48);

        float3 pulseColor = fractalPaletteColor(fract(hue + (seed * 0.18) + dist * 0.22), uniforms.fractalPaletteVariant);
        color += pulseColor * localEnergy;
        energy += localEnergy;
    }

    float3 field = fieldTexture.sample(linearSampler, in.uv).rgb;
    color += field * 0.14;
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_fractal_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> fieldTexture [[texture(0)]],
    texture2d<float> accentTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.fractalBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float3 field = fieldTexture.sample(linearSampler, uv).rgb;
    float3 accents = accentTexture.sample(linearSampler, uv).rgb;
    float3 composed = (field * 0.86) + (accents * (0.94 + uniforms.fractalAttackBloom * 0.52));

    float ambientPhase = 0.5 + 0.5 * sin((uniforms.time * (0.20 + uniforms.fractalFlowRate * 0.24)) + (point.x * 2.3) + (point.y * 2.7));
    float3 ambientA = fractalPaletteColor(fract(uniforms.fractalFlowPhase + 0.12), uniforms.fractalPaletteVariant) * 0.005;
    float3 ambientB = fractalPaletteColor(fract(uniforms.fractalFlowPhase + 0.48), uniforms.fractalPaletteVariant) * 0.010;
    composed += mix(ambientA, ambientB, ambientPhase);

    composed = max(composed - (uniforms.blackFloor * 0.13), float3(0.0));
    float vignette = smoothstep(1.58, 0.10, radius);
    composed *= vignette;
    return float4(composed, 1.0);
}

float riemannContourLine(float coordinate, float lineCount, float width) {
    float wrapped = abs(fract(coordinate * lineCount) - 0.5);
    float threshold = 0.5 - clamp(width, 0.001, 0.49);
    return 1.0 - smoothstep(threshold, 0.5, wrapped);
}

float3 riemannPaletteBankColor(float phase, uint bank) {
    float3 low;
    float3 mid;
    float3 high;
    if (bank == 0u) {
        low = float3(0.05, 0.12, 0.30);
        mid = float3(0.08, 0.78, 0.88);
        high = float3(0.96, 0.32, 0.80);
    } else {
        low = float3(0.06, 0.08, 0.12);
        mid = float3(0.96, 0.58, 0.16);
        high = float3(0.42, 0.90, 0.34);
    }

    float3 tri = 0.5 + 0.5 * cos((phase + float3(0.0, 0.33, 0.67)) * (2.0 * kPi));
    float3 blend = mix(low, mid, tri);
    return mix(blend, high, tri.z * 0.55);
}

fragment float4 renderer_riemann_field_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]]
) {
    if (uniforms.riemannBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    float detail = clamp(uniforms.riemannDetail, 0.0, 1.0);
    float flowRate = clamp(uniforms.riemannFlowRate, 0.0, 1.0);
    float flow = fract(uniforms.riemannFlowPhase);

    float heading = uniforms.riemannCameraHeading;
    if (uniforms.pitchConfidence > 0.6 && uniforms.stablePitchClass >= 0) {
        float pitchPhase = (float(uniforms.stablePitchClass) / 12.0) + (clamp(uniforms.stablePitchCents, -50.0, 50.0) / 50.0) * 0.10;
        heading += pitchPhase * uniforms.pitchConfidence * 0.20;
    }

    float sinR = sin(heading);
    float cosR = cos(heading);
    float2 rotated = float2(
        (point.x * cosR) - (point.y * sinR),
        (point.x * sinR) + (point.y * cosR)
    );

    // Keep the field mapping faithful: camera motion drives navigation; pixel warp does not distort the set.
    float2 p = rotated * 2.0;
    float zoom = clamp(uniforms.riemannCameraZoom, 1e-9, 4.2);
    float2 c = float2(
        uniforms.riemannCameraCenter.x + (p.x * (3.05 * zoom)),
        uniforms.riemannCameraCenter.y + (p.y * (2.05 * zoom))
    );

    float zoomBoost = max(-log2(max(zoom, 1e-9)), 0.0);
    uint maxIter = clamp(
        (uniforms.riemannTermCount * 2u) +
            uint(34.0 + detail * 120.0 + zoomBoost * (18.0 + detail * 18.0)),
        72u,
        960u
    );
    float2 z = float2(0.0, 0.0);
    float2 dz = float2(0.0, 0.0);
    uint escapeIter = maxIter;
    float escapeMag2 = 0.0;

    for (uint index = 0u; index < 1024u; index += 1u) {
        if (index >= maxIter) {
            break;
        }

        float2 dzNext = float2(
            (2.0 * z.x * dz.x) - (2.0 * z.y * dz.y) + 1.0,
            (2.0 * z.x * dz.y) + (2.0 * z.y * dz.x)
        );
        dz = dzNext;

        float x = (z.x * z.x) - (z.y * z.y) + c.x;
        float y = (2.0 * z.x * z.y) + c.y;
        z = float2(x, y);

        float m2 = dot(z, z);
        if (m2 > 256.0) {
            escapeIter = index;
            escapeMag2 = m2;
            break;
        }
    }

    bool escaped = escapeIter < maxIter;
    float smoothIter = float(maxIter);
    if (escaped) {
        float logEscape = log(max(escapeMag2, 1.000001));
        float nu = log(max(logEscape / log(2.0), 1e-9)) / log(2.0);
        smoothIter = float(escapeIter) + 1.0 - clamp(nu, 0.0, 8.0);
    }

    float iterNorm = clamp(smoothIter / float(maxIter), 0.0, 1.0);
    float phase = escaped ? atan2(z.y, z.x) : atan2(c.y, c.x);
    float phaseNormalized = fract((phase / (2.0 * kPi)) + 1.0);
    float magnitude = max(length(z), 1e-7);
    float logMagnitude = log(max(magnitude, 1.000001));
    float derivative = max(length(dz), 1e-6);
    float distanceEstimate = escaped ? (0.5 * log(max(magnitude, 1.000001)) * magnitude / derivative) : 0.0;
    float boundaryEnergy = escaped ? clamp(exp(-distanceEstimate * (22.0 + detail * 30.0)), 0.0, 1.0) : 0.0;

    float argumentLines = riemannContourLine(
        phaseNormalized + (flow * 0.04),
        8.0 + (float(uniforms.riemannTrapSampleCount) * 0.55) + (detail * 6.0),
        0.10
    );
    float equipotentialLines = riemannContourLine(
        (logMagnitude * (0.86 + detail * 0.44)) + (flow * 0.22),
        6.0 + (float(uniforms.riemannTrapSampleCount) * 0.30),
        0.09
    );
    float contourEnergy = max(argumentLines, equipotentialLines);
    float topologyMask = clamp((argumentLines * 0.62) + (equipotentialLines * 0.72) + (contourEnergy * 0.22), 0.0, 1.0);
    float boundaryMask = clamp(pow(boundaryEnergy, 0.78) * (0.68 + contourEnergy * 0.32), 0.0, 1.0);

    float streamField = sin(
        (phase * (4.6 + detail * 2.8)) +
        (logMagnitude * (6.4 + flowRate * 4.0)) +
        (flow * 10.0) +
        (p.x * 3.2)
    );
    float streamMask = pow(max(0.0, streamField * 0.5 + 0.5), 4.0) * (0.45 + boundaryEnergy * 0.55);

    float2 particleGrid = floor((c + float2(160.0, 160.0)) * (0.55 + detail * 1.10));
    float particleSeed = hash12(particleGrid + float2(float(uniforms.riemannPaletteVariant) * 2.7, floor(flow * 53.0)));
    float trap = exp(-pow(length(z - float2(-0.7436439, 0.1318259)) * (4.4 + detail * 2.4), 2.0));
    float particleMask = smoothstep(0.9925, 1.0, particleSeed) * (0.18 + trap * 0.82) * (0.25 + contourEnergy * 0.75);

    uint style = uniforms.riemannPaletteVariant % 8u;
    uint family = style / 2u;
    uint bank = style % 2u;
    float palettePhase = fract(phaseNormalized + (flow * 0.018) + ((1.0 - iterNorm) * 0.08));
    float3 baseDomain = riemannPaletteBankColor(palettePhase, bank);
    float3 boundaryColor = riemannPaletteBankColor(fract(palettePhase + 0.5), bank);
    float3 streamColor = riemannPaletteBankColor(fract(palettePhase + 0.16), bank);
    float3 particleColor = riemannPaletteBankColor(fract(palettePhase + 0.34), bank);

    float value = escaped ? (0.06 + pow(1.0 - iterNorm, 0.46) * 0.88) : 0.002;
    value = clamp(value + boundaryMask * 0.10, 0.0, 1.0);
    float saturation = clamp(0.30 + contourEnergy * 0.42 + boundaryMask * 0.18, 0.10, 1.0);

    float3 color = baseDomain;
    switch (family) {
    case 0u: // topology
        color = baseDomain * (0.30 + topologyMask * 0.96);
        color += boundaryColor * boundaryMask * 0.18;
        color += float3(1.0) * (argumentLines * 0.08 + equipotentialLines * 0.06);
        break;
    case 1u: // streams
        color = baseDomain * 0.22;
        color += streamColor * (0.22 + streamMask * 1.05);
        color += boundaryColor * boundaryMask * 0.24;
        break;
    case 2u: // boundaries
        color = baseDomain * 0.15;
        color += boundaryColor * pow(boundaryMask, 0.78) * 1.15;
        color += streamColor * streamMask * 0.16;
        break;
    default: // particles
        color = baseDomain * 0.10;
        color += particleColor * particleMask * (1.35 + uniforms.attackStrength * 0.25);
        color += boundaryColor * boundaryMask * 0.20;
        break;
    }

    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(luma), color, saturation);
    color *= value + 0.08;
    color = max(color - (uniforms.blackFloor * 0.050), float3(0.0));
    return float4(color, max(value, 0.0001));
}

fragment float4 renderer_riemann_accents_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    const device RiemannAccentData* accents [[buffer(1)]],
    texture2d<float> fieldTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.riemannBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 point = centeredPoint(in.uv, uniforms.resolution, uniforms.centerOffset);
    uint accentCount = min(uniforms.riemannAccentCount, kMaxRiemannAccents);
    float3 color = float3(0.0);
    float energy = 0.0;

    for (uint index = 0; index < accentCount; index += 1) {
        RiemannAccentData accent = accents[index];
        float2 position = accent.positionWidthIntensity.xy;
        float width = max(accent.positionWidthIntensity.z, 0.003);
        float intensity = max(accent.positionWidthIntensity.w, 0.0);
        if (intensity <= 0.0001) {
            continue;
        }

        float2 direction = accent.directionLengthHueSeed.xy;
        float dirLength = max(length(direction), 0.0001);
        float2 dir = direction / dirLength;
        float lengthSpan = max(accent.directionLengthHueSeed.z, 0.01);
        float hue = accent.directionLengthHueSeed.w;
        float decay = accent.decaySeedSectorActive.x;
        float seed = accent.decaySeedSectorActive.y;
        float2 tangent = float2(-dir.y, dir.x);
        float2 delta = point - position;
        float along = dot(delta, dir);
        float across = dot(delta, tangent);

        float contourStreak = exp(-pow(across / max(width, 0.0012), 2.0)) * exp(-pow(along / max(lengthSpan, 0.01), 2.0));
        float contourRing = exp(-pow(abs(length(delta) - lengthSpan) / max(width * 0.72, 0.0012), 2.0));
        float localEnergy = (contourStreak * 0.76 + contourRing * 0.24) * intensity * (0.16 + decay * 0.14);
        localEnergy *= 0.14 + uniforms.riemannZeroBloom * 0.18;

        uint bank = uniforms.riemannPaletteVariant % 2u;
        float3 accentColor = riemannPaletteBankColor(fract(hue + seed * 0.04 + along * 0.02), bank);
        color += accentColor * localEnergy;
        energy += localEnergy;
    }

    float3 field = fieldTexture.sample(linearSampler, in.uv).rgb;
    color += field * 0.015;
    return float4(color, max(energy, 0.0001));
}

fragment float4 renderer_riemann_composite_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> fieldTexture [[texture(0)]],
    texture2d<float> accentTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    if (uniforms.riemannBlackout > 0u) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 uv = in.uv;
    float2 point = centeredPoint(uv, uniforms.resolution, uniforms.centerOffset);
    float radius = length(point);

    float3 field = fieldTexture.sample(linearSampler, uv).rgb;
    float3 accents = accentTexture.sample(linearSampler, uv).rgb;
    float3 composed = field + (accents * (0.12 + uniforms.riemannZeroBloom * 0.20));

    composed = max(composed - (uniforms.blackFloor * 0.055), float3(0.0));
    float vignette = smoothstep(1.95, 0.00, radius);
    composed *= mix(1.0, vignette, 0.12);
    return float4(composed, 1.0);
}
