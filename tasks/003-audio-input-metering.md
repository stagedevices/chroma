# Task 003 — Audio Input, Metering, and Feature Publication

## Purpose

Build the first real audio pipeline seam on top of the Task 002 renderer foundation:
- live audio input capture
- live meter-frame publication
- analysis-side `AudioFeatureFrame` publication
- renderer-facing integration through existing app-core seams

This task is about trustworthy architecture and data flow, not final DSP or visual-engine behavior.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- future tasks for spectral analysis, beat/onset detection, and visual engine growth

## In scope

### Audio input seam
- upgrade `AudioInputService` to expose live meter publication
- keep placeholder implementation for tests
- add live implementation using `AVAudioEngine` and Accelerate/vDSP meter math

### Analysis seam
- upgrade `AudioAnalysisService` to expose `AudioFeatureFrame` publication
- keep placeholder implementation for tests
- add live implementation that consumes meter frames and emits feature frames

### App-core integration
- bind meter and feature publishers in `SessionViewModel`
- keep renderer-facing state mapping out of SwiftUI views
- feed feature-derived modulation through stable render-state mapping contracts

### Diagnostics seam
- expose audio status with meter/feature context through diagnostics contracts
- keep diagnostics UI consumption indirect (no renderer/audio internals in views)

### Shared testable logic
- keep renderer-surface state mapping and audio status formatting in shared pure logic
- add/update unit tests for mapper behavior and analysis publication behavior

## Out of scope

Do not implement:
- FFT/spectrum bins
- beat/onset/pitch detectors
- advanced audio calibration UX
- preset persistence changes
- external display routing implementation
- recorder/export implementation
- third-party dependencies

## Required deliverables

1. Live audio input implementation behind `AudioInputService`.
2. Meter publication contract (`AudioMeterFrame`) available to analysis/app-core.
3. Live analysis implementation behind `AudioAnalysisService` publishing `AudioFeatureFrame`.
4. Session/app-core integration that updates renderer-facing state from feature frames.
5. Shared pure-logic mapping/formatting seams covered by tests.
6. Diagnostics summaries include live audio context.

## Acceptance criteria

Task 003 is complete when:

1. Audio input service can start and publish meter frames.
2. Analysis service can consume meter frames and publish feature frames.
3. Session/app-core updates renderer-facing state via stable mapping seams.
4. Diagnostics include audio status derived from live meter/feature state.
5. `xcodebuild test` for scheme `chroma` is green.
6. Implementation remains compatible with iOS app target and the same app under Mac Catalyst.

## Validation

Run and report:

- `xcodebuild -list -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
