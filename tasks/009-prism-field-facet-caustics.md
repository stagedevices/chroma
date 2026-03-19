# Task 009 — Prism Field Facet Caustics V1

## Purpose

Upgrade `Prism Field` from the radial placeholder branch into a stage-usable visual theme:
- dedicated multi-pass Facet Caustics renderer path
- hybrid reactivity (continuous flow + deterministic attack accents)
- sparse but meaningful Prism-specific controls

This task intentionally keeps `Color Shift` and camera feedback behavior unchanged.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`

## In scope

### Mode contract and controls
- keep existing mode IDs (`colorShift`, `prismField`)
- add stable Prism parameter IDs:
  - `mode.prismField.facetDensity`
  - `mode.prismField.dispersion`
- include both in quick/surface Prism control lists while retaining shared controls (`response.inputGain`, `response.smoothing`, `output.blackFloor`)

### Mapper and renderer-facing state
- map Prism parameters into renderer controls:
  - `prismFacetDensity`
  - `prismDispersion`
- keep existing attack/audio fields available for event-driven accents

### Renderer path
- add Prism-only multi-pass stack:
  1. `prism_facet_field`
  2. `prism_dispersion`
  3. `prism_attack_accents`
  4. `prism_composite`
- add fixed-size `PrismImpulsePool` (deterministic insertion/eviction)
- spawn accents only when `attackID` changes
- add reusable `PrismRenderTargets` and `PrismPipelineStates`
- preserve zero draw-loop allocations

### Stability and fallback
- add Prism quality tiers (high/medium/low) affecting:
  - active impulse limit
  - facet sample count
  - dispersion sample count
- wire Prism quality degradation into existing GPU/frame-time fallback entry points
- keep radial path as fallback if Prism multipass is unavailable or temporarily suppressed

### Shader parity
- implement Prism fragment functions in:
  - `Packages/ChromaRendering/ChromaSurfaceShaders.metal`
  - fallback embedded Metal source in `RenderingServices.swift`

### Silence/black composition policy
- if `No Image In Silence == true` and weighted live energy is below threshold (`0.03`), Prism outputs hard black
- otherwise Prism keeps black-floor-first dark composition

### Tests
- descriptor/control-list coverage for new Prism parameter IDs
- mapper tests for `prismFacetDensity` and `prismDispersion`
- pure renderer tests for Prism impulse pool dedupe/eviction and deterministic sector selection
- pure behavior tests for Prism blackout gate and Prism render-path selection

## Out of scope

Do not implement:
- new visual modes
- third-party dependencies
- Color Shift behavior redesign

## Required deliverables

1. Prism uses dedicated Facet Caustics multipass under normal conditions.
2. New Prism parameter IDs are stable and descriptor-driven.
3. Attack accents are deterministic and `attackID`-gated.
4. Prism quality degrades gracefully before broader fallback behavior.
5. Tests and builds pass for iOS simulator and Mac Catalyst.

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
