#include <metal_stdlib>
using namespace metal;

constant uint kMaxSpectralRings = 48;
constant uint kMaxAttackParticles = 128;
constant uint kMaxPrismImpulses = 32;
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

float3 hsvToRgb(float3 c) {
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
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
    float2 uv = in.uv;
    float2 texel = 1.0 / max(uniforms.resolution, float2(1.0, 1.0));

    float3 center = cameraTexture.sample(linearSampler, uv).rgb;
    float3 left = cameraTexture.sample(linearSampler, uv + float2(-texel.x, 0)).rgb;
    float3 right = cameraTexture.sample(linearSampler, uv + float2(texel.x, 0)).rgb;
    float3 up = cameraTexture.sample(linearSampler, uv + float2(0, -texel.y)).rgb;
    float3 down = cameraTexture.sample(linearSampler, uv + float2(0, texel.y)).rgb;

    float lumaCenter = dot(center, float3(0.299, 0.587, 0.114));
    float lumaLeft = dot(left, float3(0.299, 0.587, 0.114));
    float lumaRight = dot(right, float3(0.299, 0.587, 0.114));
    float lumaUp = dot(up, float3(0.299, 0.587, 0.114));
    float lumaDown = dot(down, float3(0.299, 0.587, 0.114));

    float gx = lumaRight - lumaLeft;
    float gy = lumaDown - lumaUp;
    float mag = sqrt((gx * gx) + (gy * gy));
    float contour = smoothstep(0.11, 0.33, mag + (lumaCenter * 0.04));
    return float4(contour, contour, contour, 1.0);
}

fragment float4 renderer_feedback_evolve_fragment(
    VertexOut in [[stage_in]],
    constant RendererFrameUniforms& uniforms [[buffer(0)]],
    texture2d<float> historyTexture [[texture(0)]],
    texture2d<float> contourTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]]
) {
    float2 centered = in.uv - 0.5;
    float c = cos(0.0018);
    float s = sin(0.0018);
    float2 rotated = float2((centered.x * c) - (centered.y * s), (centered.x * s) + (centered.y * c));
    float2 warpedUV = (rotated / 1.012) + 0.5;

    float history = historyTexture.sample(linearSampler, warpedUV).r;
    float contour = contourTexture.sample(linearSampler, in.uv).r;

    float decay = 0.93;
    float injection = contour * (0.42 + (uniforms.attackStrength * 0.20));
    float evolved = max(history * decay, injection);
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

    float field = feedbackTexture.sample(linearSampler, in.uv).r;
    float hue = fract(uniforms.colorShiftHue);
    float saturation = clamp(uniforms.colorShiftSaturation, 0.0, 1.0);
    float3 tint = hsvToRgb(float3(hue, saturation, 0.90));
    float value = smoothstep(0.03, 0.95, field);
    return float4(tint * value, 1.0);
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
