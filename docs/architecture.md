# Chroma Architecture

## Platform strategy

This repository is organized as an iOS-first application with Mac Catalyst support from the same app target.

Implications:
- the live app target is iOS-native and also builds for `platform=macOS,variant=Mac Catalyst`
- UIKit-backed host wrappers are acceptable where they make iOS and Catalyst share the same rendering surface integration path
- platform conditionals should stay narrow and only exist where lifecycle or host-container differences genuinely require them

## Repo layout

```text
Apps/
  Chroma-iOS/
Packages/
  ChromaAppCore/
  ChromaDomain/
  ChromaSharedCore/
  ChromaAudio/
  ChromaAnalysis/
  ChromaRendering/
  ChromaPresets/
  ChromaDiagnostics/
  ChromaRecorder/
  ChromaExternalDisplay/
  ChromaSetlist/
Tests/
  ChromaTests/
  ChromaUITests/
Legacy/
  Prototype/
```

`Legacy/Prototype` is reference material only. It is not part of the live target path.

## Architectural boundaries

### App shell and routing
`Packages/ChromaAppCore`
- app entry coordination
- root shell composition
- sheet routing
- app/session view models
- dependency bootstrap
- iOS action chrome: 2-column tile deck with medium-first sheet presentation
- iOS live controls moved into Settings sheet sections (Catalyst keeps persistent bottom panel)

### Domain models
`Packages/ChromaDomain`
- modes
- sessions
- parameters
- presets
- output/display models
- diagnostics summaries
- export profiles
- sets/cues
- audio feature frames

### Services and engines
- `Packages/ChromaAudio`: audio input and calibration seams
- `Packages/ChromaAnalysis`: analysis seams
- `Packages/ChromaRendering`: renderer and render coordination seams
- `Packages/ChromaPresets`: preset persistence seam
- `Packages/ChromaDiagnostics`: diagnostics sampling/reporting seam
- `Packages/ChromaRecorder`: recorder/export seam
- `Packages/ChromaExternalDisplay`: display routing seam
- `Packages/ChromaSetlist`: setlist/cue seam
- `CameraFeedbackService` lives alongside audio services and provides front-camera frame feed for Color Shift feedback mode

### Shared pure logic
- `Packages/ChromaSharedCore`: renderer-surface state mapping and audio-status formatting helpers
- pure logic only; no UI, Metal lifecycle, or AVAudio engine ownership

## MVVM rule set

Views:
- render UI
- bind to view models
- hold only ephemeral UI state

View models:
- coordinate UI-facing state and intents
- avoid renderer internals, DSP, and system orchestration logic

Services:
- own subsystem behavior and future integration points
- provide explicit protocols and placeholder implementations in this task

## Renderer host seam

The renderer host is a SwiftUI-compatible container backed by an iOS/Catalyst-compatible `MTKView` host.

Current expectations:
- the host embeds a real Metal-backed surface
- the renderer service owns device, command queue, pipeline state, uniforms, and frame timing
- SwiftUI views do not own the draw loop or Metal lifecycle
- a headless renderer service exists for tests so the app host does not need to boot Metal under XCTest
- renderer-facing state mapping remains in shared pure logic, not in SwiftUI views

### Current mode rendering seam

The live mode contract is intentionally narrow:
- `Color Shift`: flat solid backfill with weighted audio-driven hue motion
- `Prism Field`: facet-caustic refracted palette behavior
- `Tunnel Cels`: attack-spawned cel objects in a pseudo-3D tunnel
- `Fractal Caustics`: Julia orbit-trap caustics with flow plus attack pulses
- `Mandelbrot`: flight-traversed Mandelbrot domain coloring with flow warp plus minimal zero-bloom attack contours

Color Shift behavior:
- default output is pixel-uniform (no spatial gradients, spokes, shimmer, or vignette in this mode)
- hue movement uses a hybrid lock+glide model: stable pitch class lock (12-TET/A440) + cents glide when confidence is high
- pitch extraction is analysis-side YIN primary with HPS fallback, then confidence gate + hysteresis/dwell stabilization before renderer mapping
- when tonal confidence is low but live energy is present, Color Shift uses a slow spectral-balance fallback instead of free-running idle cycling
- global response controls and mode controls (`hueResponse`, `hueRange`) shape follow speed, excursion width, and saturation responsiveness; hue holds in silence (no idle drift)
- `No Image In Silence` forces black in silence; `Black Floor` is intentionally ignored in this mode
- optional Feedback chip enables Contour Flow: front-camera-seeded recursive GPU feedback that fully replaces flat fill while active and stays tint-driven (never raw camera passthrough)

Prism Field behavior:
- dedicated multi-pass Facet Caustics pipeline:
  1. facet field synthesis
  2. dispersion/chromatic split warp
  3. attack-driven accent injection (deterministic, pooled, `attackID`-gated)
  4. black-floor-first composite
- no draw-loop allocations; fixed impulse pool and fixed intermediate targets
- `No Image In Silence` can force hard black in low-energy silence; otherwise Prism keeps intentional dark composition via black-floor grading
- if renderer stability degrades, Prism quality reduces in tiers (sample counts + max impulses) before any broader fallback behavior

Tunnel Cels behavior:
- dedicated multipass tunnel pipeline:
  1. tunnel field synthesis
  2. attack-spawned cel shape rendering
  3. black-floor-first composite with trails/dispersion accents
- shape spawning is deterministic and `attackID`-gated (one primary shape per attack)
- shape lifetime uses hybrid ADSR logic:
  - fixed attack/decay
  - sidechain sustain with hysteresis (`on/off` thresholds + short dropout hold)
  - release duration controlled by mode `releaseTail`
- silence policy mirrors stage composition rules: `No Image In Silence` can force hard black; otherwise tunnel remains dark-first via black-floor grading
- variant selection (`Cel Cards`, `Prism Shards`, `Glyph Slabs`) is mode-scoped
- on iOS, variant selection is presented via a medium-detent picker sheet from the top action tile
- on Catalyst, variant selection remains chip-style cycling

Fractal Caustics behavior:
- dedicated multi-pass Fractal Caustics pipeline:
  1. Julia orbit-trap field synthesis
  2. attack-driven pulse injection (deterministic, pooled, `attackID`-gated)
  3. palette-mapped composite with black-floor-first grading
- no draw-loop allocations; fixed pulse pool and fixed intermediate targets
- continuous modulation uses amplitude/bands as primary flow drivers and pitch lock fields for high-confidence micro-phase modulation
- palette customization is mode-scoped and snaps `paletteVariant` to curated banks (`0...7`)
- on iOS, palette selection is presented via a medium-detent picker sheet from the top action tile
- on Catalyst, palette selection remains chip-style cycling
- `No Image In Silence` can force hard black in low-energy silence; otherwise Fractal stays dark-first via black-floor grading

Mandelbrot behavior:
- dedicated multi-pass Mandelbrot pipeline:
  1. Mandelbrot field synthesis with smooth-escape contour structure and traversal camera mapping
  2. minimal attack contour pulse injection (deterministic, pooled, `attackID`-gated)
  3. palette-mapped composite with light black-floor grading
- no draw-loop allocations; fixed accent pool and fixed intermediate targets
- continuous modulation uses amplitude/bands/pitch as flight controls over a persistent camera state (`center`, `heading`, `zoom`) so traversal feels like movement through a space
- attack events can trigger deterministic minibrot point-of-interest handoffs (cooldown-gated) with bounded steering and zoom acceleration to avoid hard cuts
- palette customization is mode-scoped and snaps `paletteVariant` to curated banks (`0...7`)
- on iOS, palette selection is presented via a medium-detent picker sheet from the top action tile
- on Catalyst, palette selection remains chip-style cycling
- Mandelbrot palette variants are style-distinct render families (`topology`, `boundaries`, `streams`, `particles`) rather than simple hue shifts
- explicit phase/escape contour lines are derived from smooth-escape iteration structure to preserve readable boundary fans without seams
- `No Image In Silence` can force hard black in low-energy silence; otherwise Mandelbrot remains visible with dark-first grading

Renderer stability rules:
- command-buffer error handling and timed fallback infrastructure remain in place
- no draw-loop allocations are introduced in active mode rendering
- feedback rendering uses fixed intermediate textures + ping-pong recursion to avoid per-frame buffer churn
- tunnel rendering uses fixed-size pooled events and quality tiers before hard fallback
- fractal rendering uses fixed-size pooled pulses and quality tiers (orbit/trap samples + pulse count) before hard fallback
- mandelbrot rendering uses fixed-size pooled accents and quality tiers (iteration budget + trap taps + accent count) before hard fallback

## Audio input and analysis seam

Task 003 baseline expectations:
- `AudioInputService` can publish live `AudioMeterFrame` values from capture
- `AudioAnalysisService` consumes meter frames and publishes `AudioFeatureFrame` values
- session/app-core consumes these streams and updates renderer-facing state via stable contracts
- renderer remains decoupled from audio device ownership

Task 004 analysis seam extensions:
- `AudioAnalysisService` supports live detector updates via `updateTuning(_:)`
- analysis tuning includes adaptive attack-gate threshold (`attackThresholdDB`) with fixed hysteresis/cooldown defaults for v1
- live analysis computes adaptive noise floor in dB and emits attack/event fields on `AudioFeatureFrame`
- session/app-core owns analysis tuning propagation (current live UI mapping is response gain + fixed threshold baseline); SwiftUI views remain descriptor-driven and unaware of detector internals

Task 005 analysis and metering extensions:
- `AudioMeterFrame` carries both normalized envelope values and raw dBFS context (`rmsDBFS`, `peakDBFS`)
- live analysis attack detection runs on dBFS-derived signal math rather than normalized envelope values
- global `response.inputGain` is mapped into analysis tuning (`inputGainDB`) so response gain affects attack sensitivity and event generation, not only visual intensity

Task 008 pitch-reactive Color Shift extensions:
- `AudioInputService` publishes lightweight mono sample frames (`AudioSampleFrame`) alongside meter frames
- `LiveAudioAnalysisService` consumes meter + sample streams; heavy pitch DSP runs on a dedicated analysis queue (never in the audio tap callback)
- `AudioFeatureFrame` now carries pitch and lock-state fields (`pitchHz`, `pitchConfidence`, `stablePitchClass`, `stablePitchCents`) for renderer-facing color decisions
- pitch confidence fusion is stage-mic adaptive: live sample profiling (tonal/noise/voice likelihood) dynamically tunes YIN/HPS agreement weighting and confidence floors to stay stable across voiced material and noisy rooms

## Output architecture

Output remains first-class even in an iOS-first/Catalyst repository:
- the operator shell and program output are separate concerns
- display target selection is a domain concern, not view-local UI state
- future external display routing should attach through `ExternalDisplayCoordinator` and `OutputSessionState`

## Parameter architecture

The parameter system must support from day one:
- global parameters
- mode-scoped parameters
- stable grouping
- basic and advanced tiers
- preset serialization without untyped bags

## Testing strategy

The current baseline includes logic tests for:
- domain-model construction and serialization
- parameter store behavior
- app/session state and routing behavior
- renderer-facing state mapping and diagnostics behavior
- audio metering-to-feature publication and renderer modulation mapping behavior
