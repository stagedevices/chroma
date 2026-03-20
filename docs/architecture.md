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
- iOS + Catalyst action chrome: shared 2-column tile deck
- iOS: medium-first sheet presentation for action flows
- Catalyst: adaptive action presentation (tile-anchored popovers for short pickers, sheets for larger flows)
- mode picker sheet uses a hero pager (`TabView` pages + custom dots + explicit apply button), with preview-only swipe and apply-on-tap commit
- iOS live controls moved into Settings sheet sections (Catalyst keeps persistent bottom panel)
- preset browser is mode-scoped (active mode only) with apply/rename/delete flows
- iOS live-controls save tile supports quick-save + inline rename for presets
- appearance toggle is session-driven (`dark`/`light` glass) and re-renders shell + settings + canvas with an ink transition token
- Settings includes a navigable About subpage (inside the same NavigationStack) with external website/privacy/support links
- Settings includes production pro-control sections for:
  - performance policy (`Auto`, `High Quality`, `Safe FPS`, thermal fallback)
  - audio calibration (room-noise capture + attack/silence gate trims)
  - Mandelbrot navigation lock (`Guided Zoom` / `Free Flight`) and steering damping
  - mode defaults (save/reset current mode parameter baselines)
  - session recovery (autosave/restore toggles + panic reset)
- mode defaults and session recovery use dedicated persistence seams, separate from presets

### Domain models
`Packages/ChromaDomain`
- modes
- sessions
- parameters
- presets
- output/display models
  - output state includes glass appearance style so chrome treatment and idle ambient color are persisted with session state
- diagnostics summaries
- export profiles
- sets/cues
- audio feature frames
- session state includes persisted `performanceSettings`, `audioCalibrationSettings`, and `sessionRecoverySettings` with decode-safe defaults

### Services and engines
- `Packages/ChromaAudio`: audio input and calibration seams
- `Packages/ChromaAnalysis`: analysis seams
- `Packages/ChromaRendering`: renderer and render coordination seams
- `Packages/ChromaPresets`: preset persistence seam
  - disk-backed preset storage for runtime, placeholder service for tests
  - mode starter backfill adds one curated seed preset when an entire mode has no presets in local storage
- `Packages/ChromaAppCore`: session persistence seams
  - `ModeDefaultsService` stores per-mode default parameter snapshots
  - `SessionRecoveryService` stores debounced session + parameter snapshots for launch restore
- `Packages/ChromaDiagnostics`: diagnostics sampling/reporting seam
- `Packages/ChromaRecorder`: recorder/export seam
  - `LiveRecorderService` captures renderer program-feed frames via renderer frame sink + optional mic audio from live audio samples
  - AVAssetWriter-based lifecycle (`starting`/`recording`/`finalizing`/`completed`/`failed`) with cache-first output and bounded cleanup
- `Packages/ChromaExternalDisplay`: display routing seam
  - `LiveExternalDisplayCoordinator` publishes live target availability and selected-target reconciliation from iOS screen lifecycle events
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
- renderer exposes a single frame-capture sink registration seam so export captures program feed directly from render output (never shell UI composition)

### Current mode rendering seam

The live mode contract is intentionally narrow:
- `Color Shift`: flat solid backfill with weighted audio-driven hue motion
- `Prism Field`: facet-caustic refracted palette behavior
- `Tunnel Cels`: attack-spawned cel objects in a pseudo-3D tunnel
- `Fractal Caustics`: Julia orbit-trap caustics with flow plus attack pulses
- `Mandelbrot`: flight-traversed Mandelbrot domain coloring with flow warp plus minimal zero-bloom attack contours

Color Shift behavior:
- default output is pixel-uniform (no spatial gradients, spokes, shimmer, or vignette in this mode)
- hue movement uses a directional PWM model with bistable latching: hue oscillates from center toward a latched side (left/right) instead of free bipolar sweep
- direction source is selectable via `mode.colorShift.excitementMode`:
  - `Spectral` (low vs high dominance)
  - `Temporal` (short/transient vs long/sustain cue)
  - `Pitch` (up/down pitch motion; confidence-gated fallback to spectral weighting)
- pitch extraction is analysis-side YIN primary with HPS fallback, then confidence gate + hysteresis/dwell stabilization before renderer mapping
- when tonal confidence is low but live energy is present, Color Shift uses a slow spectral-balance fallback instead of free-running idle cycling
- `hueRange` is a dual-point hue clamp value (`min`, `max`, `outside`) edited through a hue-spectrum track with inside/outside selection
- Color Shift target hue is clamped to the selected arc/complement using ordered wrap-aware arc semantics and a fixed feathered boundary
- global response controls and mode controls (`hueResponse`, `hueRange`, `excitementMode`) shape pulse rate, allowed hue excursion width, directional cue interpretation, and saturation responsiveness; hue holds in silence (no idle drift)
- `No Image In Silence` forces black in silence; `Black Floor` is intentionally ignored in this mode
- optional Feedback chip enables camera-color-driven abstract field rendering: front-camera frames are sampled for color, then used to drive procedural lava-lamp style banding/blobs (no camera-image passthrough)

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
- on Catalyst, variant selection uses tile-anchored picker popovers

Fractal Caustics behavior:
- dedicated multi-pass Fractal Caustics pipeline:
  1. Julia orbit-trap field synthesis
  2. attack-driven pulse injection (deterministic, pooled, `attackID`-gated)
  3. palette-mapped composite with black-floor-first grading
- no draw-loop allocations; fixed pulse pool and fixed intermediate targets
- continuous modulation uses amplitude/bands as primary flow drivers and pitch lock fields for high-confidence micro-phase modulation
- palette customization is mode-scoped and snaps `paletteVariant` to curated banks (`0...7`)
- on iOS, palette selection is presented via a medium-detent picker sheet from the top action tile
- on Catalyst, palette selection uses tile-anchored picker popovers
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
- on Catalyst, palette selection uses tile-anchored picker popovers
- Mandelbrot palette variants are style-distinct render families (`topology`, `boundaries`, `streams`, `particles`) rather than simple hue shifts
- explicit phase/escape contour lines are derived from smooth-escape iteration structure to preserve readable boundary fans without seams
- `No Image In Silence` can force hard black in low-energy silence; otherwise Mandelbrot remains visible with dark-first grading

Renderer stability rules:
- command-buffer error handling and timed fallback infrastructure remain in place
- no draw-loop allocations are introduced in active mode rendering
- feedback rendering uses a dedicated procedural field path seeded by camera color samples (shape-rich abstraction, never camera-image projection)
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
- settings calibration now owns `attackThresholdDB` + `silenceGateThreshold`; app-core propagates both into `AudioAnalysisService.updateTuning(_:)` and renderer silence-gate behavior

Task 008 pitch-reactive Color Shift extensions:
- `AudioInputService` publishes lightweight mono sample frames (`AudioSampleFrame`) alongside meter frames
- `LiveAudioAnalysisService` consumes meter + sample streams; heavy pitch DSP runs on a dedicated analysis queue (never in the audio tap callback)
- `AudioFeatureFrame` now carries pitch and lock-state fields (`pitchHz`, `pitchConfidence`, `stablePitchClass`, `stablePitchCents`) for renderer-facing color decisions
- pitch confidence fusion is stage-mic adaptive: live sample profiling (tonal/noise/voice likelihood) dynamically tunes YIN/HPS agreement weighting and confidence floors to stay stable across voiced material and noisy rooms

## Output architecture

Output remains first-class even in an iOS-first/Catalyst repository:
- the operator shell and program output are separate concerns
- display target selection is a domain concern, not view-local UI state
- iOS uses live target routing through `ExternalDisplayCoordinator`; selecting external creates a clean external program window while the device remains operator surface
- Catalyst remains single-window output in this task scope while sharing the same target contracts

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
