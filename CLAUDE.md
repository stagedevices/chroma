# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Chroma

Chroma is a native Apple live audio-reactive visual instrument for concerts, performances, and capture/render workflows. It is not a VJ app, video editor, or compositing suite. It should feel like a tunable instrument with stage-ready output and elegant, sparse, high-fidelity visuals.

## Building and testing

```bash
# Build the app
xcodebuild build -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all tests
xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test class
xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ChromaTests/ParameterStoreTests
```

No Makefile or build scripts — standard `xcodebuild` only. No third-party dependencies; everything is Apple-native (SwiftUI, Metal, AVAudioEngine, Accelerate/vDSP, Combine).

## Architecture

### Module layout

```
Apps/Chroma-iOS/          — app entry point (ChromaIOSApp.swift)
Packages/
  ChromaAppCore/          — app shell: routing, view models, views, bootstrap
  ChromaDomain/           — pure domain models (parameters, presets, modes, session, audio features)
  ChromaSharedCore/       — pure logic helpers (no UI/lifecycle dependencies)
  ChromaAudio/            — audio input (AVAudioEngine), camera feedback, calibration
  ChromaAnalysis/         — pitch detection, attack detection, feature extraction
  ChromaRendering/        — Metal renderer, control state, GPU shaders (1582-line .metal file)
  ChromaPresets/          — preset disk persistence
  ChromaRecorder/         — AVAssetWriter recording/export
  ChromaDiagnostics/      — diagnostics sampling
  ChromaExternalDisplay/  — iOS external display routing
  ChromaSetlist/          — setlist/cue scaffold
Tests/ChromaTests/        — logic and integration tests
```

### Startup and dependency injection

`ChromaAppBootstrap` is the single DI root. It creates all services and wires them into `SessionViewModel`. Two modes:
- `makeDefault()` — real Metal renderer, live audio, live camera, disk persistence
- `makeTesting()` — `HeadlessRendererService`, all `Placeholder*Service` implementations (no hardware, no disk)

Test environment is detected via the `XCTestConfigurationFilePath` env var.

### Live data flow

```
AVAudioEngine
  → AudioMeterFrame + AudioSampleFrame
  → LiveAudioAnalysisService (dedicated queue: pitch, attacks, band energy)
  → AudioFeatureFrame
  → SessionViewModel
  → RendererSurfaceStateMapper (parameters → RendererControlState)
  → MetalRendererService.update(surfaceState:)
  → Metal shaders render frame
  → RendererFrameCaptureSink (export seam)
```

### Parameter system

All visual controls live in `ParameterCatalog` (40+ parameters). Parameters are typed (`ParameterValue` enum: scalar, hueRange, etc.), stored in `ParameterStore` with global/mode scope, and serialized into `Preset` without untyped bags. `RendererSurfaceStateMapper` converts parameter store state into `RendererControlState` for the renderer.

### Rendering

`MetalRendererService` owns all Metal resources and the draw loop. SwiftUI views do not touch Metal lifecycle — `RendererHostView` is just an `MTKView` wrapper. Five live rendering modes (Color Shift, Prism Field, Tunnel Cels, Fractal Caustics, Mandelbrot/Riemann Corridor) plus a Custom node-graph scaffold. All modes support `No Image In Silence` hard-black silence output, attack-gated events, and quality tier scaling.

### MVVM boundaries

- **Views**: render UI, bind to view models, local ephemeral state only
- **ViewModels** (`AppViewModel`, `SessionViewModel`): coordinate UI-facing state; do not contain DSP or renderer internals
- **Services**: own subsystem behavior (audio, rendering, persistence, export)
- **Domain models** (`ChromaDomain`): pure data, no UI dependencies

Platform conditionals (`#if targetEnvironment(macCatalyst)`) are kept narrow and lifecycle-driven. iOS is primary; Mac Catalyst ships from the same target.

## Source of truth

When implementation diverges from intent, update the relevant docs in the same change:
- `AGENTS.md` — project contract and task rules
- `docs/architecture.md` — detailed architectural decisions
- `docs/mvvm-module-map.md` — module responsibilities and file listing
- `docs/product-brief.md` — product goals and principles
- `tasks/*.md` — individual task briefs
