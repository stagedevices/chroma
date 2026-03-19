# Task 005 — Gain Staging and Spectral Stability

## Purpose

Stabilize Spectral Bloom startup behavior and improve attack sensitivity in real-world live input conditions:
- use real dBFS metering context for attack logic
- wire global response gain into analysis sensitivity
- harden spectral renderer behavior under GPU stress

This task addresses reliability and responsiveness without expanding the control surface.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- `tasks/004-spectral-bloom-attack-driven-lens.md`

## In scope

### Metering contract extension
- extend `AudioMeterFrame` with raw dBFS context:
  - `rmsDBFS`
  - `peakDBFS`
- populate these fields in live audio capture while preserving normalized `rms` / `peak` values

### Analysis gain staging
- extend `AudioAnalysisTuning` with `inputGainDB`
- map `response.inputGain` to analysis tuning from `SessionViewModel`
- use dBFS-derived signal math for adaptive-floor and attack detection (instead of normalized envelope values)
- keep Task 004 attack behavior (threshold/hysteresis/cooldown/attack IDs) intact

### Spectral renderer stability
- proactively cap spectral quality for very high-resolution drawables
- when repeated GPU command-buffer failures occur, temporarily force radial fallback before re-entering spectral passes
- keep fallback internal (no new user controls)

### Diagnostics/status formatting
- update live audio status formatting to prefer dBFS values when available

### Tests
- add/update tests for:
  - response gain propagation into analysis tuning
  - dBFS-based attack detection path
  - audio status formatting with dBFS label

## Out of scope

Do not implement:
- new user-facing controls
- new visual modes
- physically accurate ray tracing
- preset schema migrations
- third-party dependencies

## Required deliverables

1. `AudioMeterFrame` includes optional dBFS fields and live capture populates them.
2. Analysis attack detection consumes dBFS-based signal values.
3. Session updates propagate `response.inputGain` into analysis tuning.
4. Renderer includes timed fallback and proactive quality caps for stability.
5. Unit tests covering the above behavior are green.

## Acceptance criteria

Task 005 is complete when:

1. Attack detection is no longer based solely on normalized meter values.
2. Raising/lowering `response.inputGain` changes analysis tuning via `inputGainDB`.
3. Repeated GPU errors no longer immediately loop into continuous spectral failures.
4. Existing tests plus new task tests pass on `xcodebuild test`.

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
