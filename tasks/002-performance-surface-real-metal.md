# Task 002 — Performance Surface: Real Metal

## Purpose

Replace the placeholder performance surface with a real Metal-backed render surface and establish the first production-worthy rendering spine for Chroma.

This task makes the performance surface physically credible while staying intentionally narrow:
- real Metal device + drawable integration
- real frame loop
- real renderer lifecycle seam
- real render-state / uniform path
- one authored placeholder visual driven by time and manual controls
- lightweight renderer diagnostics

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- future tasks for audio input, analysis, and the first visual engine

## In scope

### Metal surface integration
- replace the placeholder render host with a real Metal-backed container
- support the live iOS app target and the same app under Mac Catalyst
- embed the Metal surface cleanly inside the SwiftUI performance shell

### Renderer foundation
- establish a real renderer lifecycle
- own Metal device / command queue / pipeline state
- create a stable frame loop
- submit render passes and present drawables every frame

### Render state and uniforms
- define minimal renderer-facing state for time, viewport, and manual controls
- support at least:
  - elapsed time
  - viewport size / resolution
  - intensity
  - scale
  - motion amount
  - diffusion / black floor or similar
  - optional center offset

### Minimal placeholder visual
- render a simple authored visual on black
- animate continuously over time
- respond to at least 3 manual parameters
- point toward Chroma’s sparse, luminous direction instead of demo-sample aesthetics

### Performance UI integration
- make the render surface the app canvas
- keep overlay chrome separate from the render surface
- support performance mode that fades the shell away and leaves a temporary reveal control

### Diagnostics seam
- expose lightweight renderer diagnostics suitable for future diagnostics UI
- include at minimum:
  - readiness status
  - drawable resolution summary
  - approximate FPS or frame-time summary
  - active mode placeholder summary

## Out of scope

Do not implement:
- live audio input
- FFT / spectrum analysis
- onset / pitch / beat logic
- final Chroma visual engine behavior
- preset persistence details
- external display routing implementation
- recorder/export implementation
- multiple finished modes
- mode morph implementation
- third-party dependencies

## Required deliverables

1. Real Metal-backed surface in the live app target and under Mac Catalyst.
2. Renderer service foundation owning Metal lifecycle and frame submission.
3. SwiftUI render container seam that keeps platform host details out of feature views.
4. Minimal real render-state pipeline for time, viewport, and manual controls.
5. One authored placeholder visual on black responding to at least 3 controls.
6. Renderer diagnostics summaries exposed to the UI layer.
7. Initial tests for render-state defaults, state mapping, or diagnostics behavior.

## Acceptance criteria

This task is complete when:

1. The placeholder performance surface is replaced with a real Metal-backed render surface.
2. The iOS build shows live rendered output.
3. The Mac Catalyst build shows live rendered output.
4. The render container seam remains clear and SwiftUI-compatible.
5. Renderer lifecycle owns device, command queue, and frame rendering.
6. A real renderer-facing state / uniform path exists.
7. The visual animates and responds to at least 3 manual controls.
8. Renderer diagnostics are exposed cleanly to the UI layer.
9. The implementation preserves MVVM + services boundaries.

## Validation

Run the most relevant available validations and report the exact commands:

- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'`
