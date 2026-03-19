# Task 010 — Tunnel Cels V1 (Attack-Spawned ADSR Shapes)

## Purpose

Add a new stage mode, `Tunnel Cels`, built for deterministic live attack-driven visuals:
- each new `attackID` spawns a cel object in a pseudo-3D tunnel
- object lifetime follows hybrid ADSR behavior (fixed attack/decay + sidechain sustain + release tail)
- black-floor-first composition is preserved for stage readability

This task keeps existing `Color Shift` and `Prism Field` behavior intact.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`

## In scope

### Mode contract and controls
- add `VisualModeID.tunnelCels` with stable descriptor metadata
- add stable mode parameter IDs:
  - `mode.tunnelCels.shapeScale`
  - `mode.tunnelCels.depthSpeed`
  - `mode.tunnelCels.releaseTail`
  - `mode.tunnelCels.variant` (scalar snapped to `0/1/2`)
- add Tunnel Cels quick/surface lists with:
  - `response.inputGain`
  - `response.smoothing`
  - the three tunnel controls above (except `variant`)
  - `output.blackFloor`

### UI behavior
- add Tunnel Cels mode in picker via existing descriptor flow
- add top-row `Variant` chip for Tunnel Cels only
- chip cycles deterministic variant values:
  - `0` = `celCards`
  - `1` = `prismShards`
  - `2` = `glyphSlabs`
- chip writes to `mode.tunnelCels.variant` in `ParameterStore`

### Mapper and renderer-facing state
- map new tunnel parameters into renderer controls:
  - `tunnelShapeScale`
  - `tunnelDepthSpeed`
  - `tunnelReleaseTail`
  - `tunnelVariant`
- preserve existing attack/audio/pitch fields for shared logic

### Renderer path
- add dedicated tunnel multipass path parallel to Prism:
  1. `renderer_tunnel_field_fragment`
  2. `renderer_tunnel_shapes_fragment`
  3. `renderer_tunnel_composite_fragment`
- add fixed-size `TunnelShapePool` and GPU data buffer (no draw-loop allocations)
- spawn only on new `attackID` (deterministic sector/lane from band bias + hash jitter)
- ADSR policy:
  - attack `35 ms`
  - decay `140 ms` to sustain
  - sustain sidechain hysteresis (`on=0.10`, `off=0.07`)
  - release `0.25...2.50 s` from `releaseTail`
  - dropout hold `~90 ms`
- silence policy:
  - if `No Image In Silence` and weighted live energy `< 0.03`, hard black
  - otherwise compose using black-floor grading

### Stability and fallback
- add Tunnel quality profile tiers and degradation:
  - active shape limit
  - trail samples
  - dispersion samples
- integrate tunnel degradation into `degradeActiveModeQuality(...)`
- include tunnel in pipeline/target rebuild and fallback cleanup logic

### Shader parity
- implement tunnel shaders in:
  - `Packages/ChromaRendering/ChromaSurfaceShaders.metal`
  - embedded fallback source in `Packages/ChromaRendering/RenderingServices.swift`

### Tests
- parameter descriptor/control-list stability for tunnel IDs
- mapper routing for tunnel fields
- session/UI behavior for variant chip cycling
- pure renderer logic:
  - pool dedupe + deterministic eviction
  - deterministic sector selection
  - ADSR helper transitions
  - blackout gate
  - renderer pass selection picks `.tunnel` when available

## Out of scope

Do not implement:
- third-party dependencies
- camera feedback redesign
- Prism or Color Shift behavior changes beyond shared switch coverage for new mode

## Required deliverables

1. `Tunnel Cels` is selectable and renders through a dedicated multipass path.
2. Attack-spawned cel objects use deterministic pooled lifecycle behavior.
3. Tunnel controls and variant selector are stable and descriptor-driven.
4. Stability degradation works before hard fallback.
5. Tests/builds pass for iOS simulator and Mac Catalyst.

## Validation

Run and report:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build -project Chroma.xcodeproj`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -project Chroma.xcodeproj`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build -project Chroma.xcodeproj`
