# Task 004 — Spectral Bloom Stub V1: Attack-Driven Multi-Pass Lens

## Purpose

Replace the single-pass radial placeholder for Spectral Bloom with an event-driven optical stub that behaves like a performance instrument:
- adaptive dB-threshold attack detection
- per-attack ring-object spawning
- cinematic multi-pass lens stack
- intentional darkness with low ambient sheen at idle

This task establishes real architecture seams for the final visual engine without over-expanding scope.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- future tasks for spectral engine refinement, presets, and stage-ready optimization

## In scope

### Analysis and attack events
- extend `AudioFeatureFrame` with attack/event fields:
  - `isAttack`
  - `attackStrength`
  - `attackID`
  - `attackDbOverFloor`
- add `AudioAnalysisTuning` with `attackThresholdDB` and internal hysteresis/cooldown defaults
- extend `AudioAnalysisService` with `updateTuning(_:)`
- implement adaptive-floor attack detection in live analysis:
  - threshold crossing
  - positive slope
  - hysteresis re-arm
  - cooldown guard

### Session and mapping integration
- propagate `mode.spectralBloom.attackThresholdDB` to analysis tuning from app-core
- keep control surfaces descriptor-driven and MVVM-safe
- extend renderer-surface mapping to include:
  - `ringDecay`
  - `attackStrength`
  - `attackID`
  - band-energy shaping inputs

### Spectral Bloom renderer stub
- add fixed-size ring-event pool and GPU ring buffer (no per-frame allocation in draw loop)
- spawn ring events only when `attackID` changes
- implement arc-segment spawn policy:
  - 12 sectors
  - dominant-band bias
  - deterministic jitter from `attackID`
  - near-center spawn with small radial jitter
- implement four-pass optical stack:
  1. ring field
  2. lens/chromatic split
  3. shimmer/lenticular streaks
  4. composite with vignette and black-floor handling
- add safety fallback that auto-reduces quality after repeated GPU failures or sustained frame-time spikes

### Parameters and controls
- add exactly two new Spectral Bloom parameters:
  - `mode.spectralBloom.attackThresholdDB`
  - `mode.spectralBloom.ringDecay`
- expose both in Spectral Bloom quick/surface control lists

### Tests
- analysis attack detection behavior
- stable parameter descriptor presence and ranges/default usage
- session tuning propagation
- renderer mapping of attack/ring fields
- deterministic ring pool insertion/eviction and sector selection

## Out of scope

Do not implement:
- physically accurate ray tracing
- new finished behavior for Prism Field or Monochrome Pulse
- extra UI controls beyond the two approved parameters
- preset/schema migrations beyond stable parameter IDs
- third-party dependencies

## Required deliverables

1. Attack-aware analysis contract and live detector implementation.
2. Session-level tuning propagation from parameter control to analysis service.
3. Event-driven Spectral Bloom ring spawning from attack IDs.
4. Four-pass Spectral Bloom optical stub with cinematic-heavy defaults.
5. Stability fallback for GPU error/frame-time stress.
6. Exactly two new Spectral Bloom controls exposed on quick/surface lists.
7. Unit tests covering analysis, mapping, parameter catalog, and pure renderer logic.

## Acceptance criteria

Task 004 is complete when:

1. `AudioFeatureFrame` includes attack/event fields and they are populated by live analysis.
2. `AudioAnalysisService.updateTuning(_:)` is wired and used from session parameter updates.
3. Spectral Bloom ring objects spawn only on new `attackID` events.
4. Four-pass spectral lens pipeline renders in Spectral Bloom mode with fallback path intact.
5. Stability fallback reduces ring/shimmer quality after repeated GPU errors or prolonged slow frames.
6. Only two new Spectral Bloom controls are introduced (`Attack Threshold`, `Ring Decay`).
7. Unit tests for new behavior pass.

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
