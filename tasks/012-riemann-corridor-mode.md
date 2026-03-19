# Task 012 — Riemann Corridor V1 (Zeta Domain-Caustic Standalone Mode)

## Purpose

Add a new standalone stage mode, `Riemann Corridor`, with a dedicated GPU-native path:
- critical-strip corridor field from truncated eta/zeta domain coloring
- deterministic attack accents keyed by `attackID`
- dark-first composition suitable for stage output

This task must not change behavior of existing modes outside shared stability infrastructure.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`

## In scope

### Mode contract and controls
- add `VisualModeID.riemannCorridor` with stable descriptor metadata and decode compatibility
- add stable parameter IDs:
  - `mode.riemannCorridor.detail`
  - `mode.riemannCorridor.flowRate`
  - `mode.riemannCorridor.zeroBloom`
  - `mode.riemannCorridor.paletteVariant` (snapped `0...7`)
- add mode quick/surface lists:
  - `response.inputGain`
  - `response.smoothing`
  - `mode.riemannCorridor.detail`
  - `mode.riemannCorridor.flowRate`
  - `mode.riemannCorridor.zeroBloom`
  - `output.blackFloor`

### UI behavior
- add `Riemann Corridor` to mode picker via descriptor-driven flow
- add top-row `Palette` chip when active mode is `.riemannCorridor`
- chip cycles curated palette indices `0...7` and writes mode-scoped parameter

### Mapper and renderer-facing state
- map new parameters into renderer control state:
  - `riemannDetail`
  - `riemannFlowRate`
  - `riemannZeroBloom`
  - `riemannPaletteVariant`
- preserve existing audio feature wiring (bands, pitch, attacks)

### Renderer path
- add dedicated render-path selection `.riemann` (not radial fallback when pipeline is available)
- add dedicated pass stack:
  1. `renderer_riemann_field_fragment`
  2. `renderer_riemann_accents_fragment`
  3. `renderer_riemann_composite_fragment`
- implement fixed-size pooled accents (`RiemannAccentPool`)
  - insertion only on new `attackID`
  - deterministic sector from dominant band + hash jitter
  - deterministic eviction when full
- silence policy:
  - if `No Image In Silence` and weighted live energy `< 0.03`, hard black
  - otherwise render corridor with black-floor-first grading

### Numerical and stability policy
- implement eta/zeta helpers using truncated alternating eta continuation
- guard denominator behavior near `1 - 2^(1-s)` singular region to avoid NaN/Inf propagation
- add quality tiers integrated into existing degradation path:
  - term count: `36 / 24 / 14`
  - trap taps and accent limits degrade before broader fallback
  - accent limits: `24 / 16 / 10`

### Shader parity
- implement Riemann shaders in:
  - `Packages/ChromaRendering/ChromaSurfaceShaders.metal`
  - embedded fallback shader source in `Packages/ChromaRendering/RenderingServices.swift`

### Tests
- parameter descriptor/control-list stability for Riemann IDs
- mapper routing for Riemann fields
- session/UI palette chip behavior
- renderer pure logic:
  - accent pool dedupe + deterministic eviction
  - deterministic sector selection
  - deterministic flow phase progression
  - blackout gate behavior
  - pass selection chooses `.riemann`
- approximation safety:
  - finite eta samples in normal strip ranges
  - known-value sanity at `s=2`
  - singular-guard behavior near denominator pole

## Out of scope

- no touch/motion interaction changes
- no third-party dependencies
- no redesign of existing mode control surfaces

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
