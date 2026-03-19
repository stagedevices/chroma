# Task 006 — Attack Particle Halo Mode

## Purpose

Ship the first post-Spectral-Bloom flagship mode with clear stage value and deterministic real-time behavior:
- add `Attack Particle Halo` as a dedicated renderer mode path
- keep architecture GPU-native, fixed-pool, and allocation-safe in draw loops
- preserve black-floor composition and stability-first fallback behavior

This task implements the first step of Mode Roadmap V1 and intentionally does not ship Cel Lattice or Caustic Flow Field yet.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- `tasks/005-gain-staging-and-spectral-stability.md`

## In scope

### Mode contract and parameters
- extend `VisualModeID` and mode descriptors with `attackParticleHalo`
- add stable parameter IDs:
  - `mode.attackParticleHalo.burstDensity`
  - `mode.attackParticleHalo.trailDecay`
  - `mode.attackParticleHalo.lensSheen`
- include these controls in quick/surface parameter lists for the new mode

### Mapper/session seam
- map new mode parameters into renderer-facing control state
- continue routing attack/event analysis fields into renderer state (`isAttack`, `attackStrength`, `attackID`, band energies)
- keep UI descriptor-driven (no custom one-off view logic)

### Renderer implementation
- keep Spectral Bloom stack unchanged
- add a parallel multi-pass path for `Attack Particle Halo`:
  1. particle energy field pass (HDR)
  2. trail/lenticular sheen pass
  3. final composite pass with black-floor-first grading
- add fixed-size particle pool/event model and fixed-size GPU data arrays
- spawn burst particles only when `attackID` changes
- use deterministic sector selection from attack ID + dominant band energies
- preserve timed radial fallback and quality degradation behavior under stress

### Tests
- add/update tests for:
  - new descriptor IDs/ranges/defaults
  - mapper output for attack mode controls and attack fields
  - particle pool dedupe/eviction behavior
  - deterministic attack-particle sector selection

## Out of scope

Do not implement:
- Cel Lattice mode
- Caustic Flow Field mode
- camera-reactive pipelines (Vision/MediaPipe)
- diffusion runtime inference in live rendering
- third-party dependencies

## Required deliverables

1. `Attack Particle Halo` appears in mode selection and has its own renderer path.
2. New mode parameters are stable and wired through parameter catalog + mapper.
3. Particle bursts are attack-ID-driven and deterministic.
4. Existing renderer fallback/quality protections remain intact.
5. Unit tests for new mode contracts and particle logic pass.

## Acceptance criteria

Task 006 is complete when:

1. Switching to `Attack Particle Halo` no longer renders the old radial placeholder path under normal conditions.
2. Burst behavior tracks `attackID` changes and ignores repeated IDs.
3. Black-floor and no-image-in-silence behavior remain compositional and stable.
4. Builds and tests run cleanly on iOS simulator and Mac Catalyst.

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
