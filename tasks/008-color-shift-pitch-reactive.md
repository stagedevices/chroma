# Task 008 — Color Shift Pitch-Locked Reactivity

## Purpose

Finish `Color Shift` as a stage-usable audio-reactive mode by replacing envelope-only hue cycling with pitch-driven, confidence-gated behavior:
- YIN primary + HPS fallback pitch extraction
- hysteresis/dwell lock behavior to avoid chatter
- hybrid lock+glide hue model with saturation driven by intensity + confidence
- no visual drift in silence

This task keeps `Color Shift` flat/pixel-uniform and leaves `Prism Field` unchanged.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- `tasks/006-attack-particle-halo-mode.md`

## In scope

### Public contracts and state
- add `AudioSampleFrame` domain model (`timestamp`, `sampleRate`, `monoSamples`)
- extend `AudioInputService` with `samplePublisher`
- extend `AudioFeatureFrame` with:
  - `pitchHz: Double?`
  - `pitchConfidence: Double`
  - `stablePitchClass: Int?`
  - `stablePitchCents: Double`
- extend renderer-facing control/uniform state with pitch lock fields and `colorShiftSaturation`

### Audio pipeline
- publish mono sample chunks from the live input tap while preserving existing meter path
- consume meter + sample streams in `LiveAudioAnalysisService`
- run pitch DSP on dedicated queue (never heavy work in tap callback)
- maintain 4096-sample ring and run:
  - YIN primary (4096 preferred, 2048 fallback)
  - HPS fallback (2048)
- implement fixed stability defaults:
  - lock gate: confidence >= 0.60 and signal active
  - switch hysteresis: 14 cents
  - switch dwell: 90 ms
  - release: confidence < 0.35 or no signal for 180 ms

### Color Shift behavior
- keep flat solid backfill rendering
- replace free-running hue cycle with target tracking:
  - stable lock target from `stablePitchClass / 12`
  - glide from `stablePitchCents` scaled by `hueRange`
  - no stable pitch + low activity: hold hue (no drift)
  - no stable pitch + active signal: slow spectral-balance fallback hue
- drive saturation from weighted intensity + pitch confidence
- keep existing silence blackout policy (`No Image In Silence`)
- keep control IDs unchanged:
  - `mode.colorShift.hueResponse`
  - `mode.colorShift.hueRange`

### Docs and tests
- update architecture and product docs to describe pitch-reactive Color Shift behavior
- add analysis/renderer tests for detector, fallback, lock hysteresis, release hold, and saturation monotonicity

## Out of scope

Do not implement:
- new Color Shift UI controls
- changes to `Prism Field` behavior
- third-party dependencies
- camera-feedback mode redesign

## Required deliverables

1. Color Shift reacts to tonal pitch with stable lock+glide behavior.
2. Hue no longer free-runs in silence.
3. Saturation responds monotonically to signal intensity/confidence.
4. Pitch fields are published in `AudioFeatureFrame` and mapped through renderer state.
5. Builds/tests pass on iOS simulator and Mac Catalyst.

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
