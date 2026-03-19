# Task 001 — Repo Foundation

## Purpose

Create the initial repository foundation for Chroma so future work can proceed task-by-task against a stable, long-term architecture.

This task should establish:
- native iOS and macOS app entry points
- shared architectural seams
- MVVM-oriented app shell scaffolding
- placeholder services and domain models for core subsystems
- initial test structure
- project organization that supports future Codex tasks cleanly

This task is about **foundation**, not feature completeness.

## Supports

- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`

## In scope

### Repo / project structure
- create the initial app/project/workspace structure
- create native iOS and macOS app targets
- create shared modules or packages for the major architectural domains
- add placeholder tests for logic-bearing modules

### App shell scaffold
- create app entry points
- create a root shell with one main performance surface and sheet-routing scaffolding
- create top-level app/session view models
- create basic dependency bootstrap/injection seams

### Domain and subsystem scaffolding
Create placeholder types/contracts for:
- session state
- modes
- parameters
- presets
- audio input
- analysis
- rendering
- recorder/export
- diagnostics
- external display
- future sets/cues

### Rendering integration seam
- create a renderer host/container seam for future Metal integration
- it may be placeholder-backed in this task
- do not implement the full renderer

### Output architecture seam
- create output/display abstractions that make future external display support straightforward
- implementation can be minimal, but architecture must be present

### Documentation alignment
- ensure created code structure aligns with the docs
- if a minor implementation detail differs, update docs in the same change

## Out of scope

Do **not** implement:
- a full Metal renderer
- a full AVAudioEngine input stack
- FFT / full analysis logic
- finished presets UI
- finished mode editor
- finished recorder/export pipeline
- onboarding
- multiple finished visual modes
- premium/paywall logic
- large styling or polish passes

Do not add third-party dependencies.

## Preferred structure

The exact final filesystem can vary, but the result should resemble this shape:

```text
Chroma/
  Apps/
    Chroma-iOS/
    Chroma-macOS/
  Packages/
    ChromaDomain/
    ChromaAudio/
    ChromaAnalysis/
    ChromaRendering/
    ChromaPresets/
    ChromaDiagnostics/
  Tests/
```

If a single Xcode project with clear groups/targets is more practical, that is acceptable, but the architectural boundaries must remain obvious and future-proof.

## Required deliverables

### 1. Native app targets

Create:

* one iOS app target
* one macOS app target

Each should:

* launch successfully
* share the same high-level architecture
* present the same root shell concept

### 2. Root shell

Create a root UI shell with:

* one primary performance surface
* subordinate sheet routing seams for:

  * recorder/export
  * preset browser
  * mode editor
  * settings/diagnostics

The actual sheet contents may be minimal placeholders, but routing must exist.

### 3. App/session view models

Create:

* `AppRouter`
* `AppViewModel`
* `SessionViewModel`

These should:

* coordinate high-level state
* define routing/sheet presentation
* expose current active mode / session summaries
* remain clean and lightweight

### 4. Domain model scaffolding

Create initial domain models/protocols for:

* `ChromaSession`
* `VisualModeID`
* `VisualModeDescriptor`
* `VisualMorphState`
* `ParameterDescriptor`
* `ParameterValue`
* `ParameterGroup`
* `Preset`
* `DisplayTarget`
* `OutputSessionState`
* `ExportProfile`
* `DiagnosticsSnapshot`
* `PerformanceSet`
* `PerformanceCue`
* `AudioFeatureFrame`

These may be minimal but should be real typed models, not placeholders hidden behind dictionaries.

### 5. Service / coordinator scaffolding

Create protocols and/or initial concrete placeholder types for:

* `AudioInputService`
* `InputCalibrationService`
* `AudioAnalysisService`
* `RendererService`
* `RenderCoordinator`
* `PresetService`
* `RecorderService`
* `DiagnosticsService`
* `ExternalDisplayCoordinator`
* `SetlistService`

These do not need full implementation in this task, but they should establish future attachment points.

### 6. Renderer host seam

Create a renderer host view/container suitable for future Metal integration:

* platform-appropriate wrapper
* SwiftUI-compatible embedding strategy
* safe placeholder behavior for now

### 7. Parameter store seam

Create a parameter store with:

* stable grouping concepts
* global and mode-specific parameter support seams
* basic vs advanced tier seam

Full parameter editing UI is not required, but the architecture must exist.

### 8. Tests

Add initial tests covering at minimum:

* domain model construction/serialization basics where applicable
* parameter store behavior basics
* app/session state basics where testable without UI harness complexity

The goal is not exhaustive coverage. The goal is to establish a testing habit and real attachment points.

## Requirements

### Architectural requirements

* native iOS + native macOS, not Catalyst-first
* clean separation between UI/app state and services
* no DSP in view models
* no renderer internals in view models
* no ad hoc untyped global state bags
* stable naming and explicit boundaries

### Product requirements

The scaffold must clearly make room for:

* one serious visual engine
* future more-than-one mode support
* future morph support
* presets
* external display
* recorder/export
* diagnostics
* future QLab-style sets/cues

### Code-quality requirements

* compile cleanly
* use clear naming
* avoid speculative abstraction beyond the defined subsystem seams
* avoid false/demo completeness that will be immediately discarded

## Acceptance criteria

This task is complete when all of the following are true:

1. The repository contains native iOS and macOS app entry points.
2. Both app targets build successfully.
3. Both app targets present a shared conceptual root shell centered on a performance surface.
4. The root shell includes subordinate sheet-routing seams for recorder/export, presets, mode editor, and settings/diagnostics.
5. Core domain model scaffolding exists as typed models.
6. Core service/coordinator scaffolding exists as real types/protocols.
7. A renderer host/container seam exists for future Metal integration.
8. A parameter store seam exists with global/mode-specific/basic-advanced structure.
9. Initial tests exist and pass.
10. The resulting structure clearly supports future tasks without major architectural rewrites.

## Validation

Run the most relevant available validations, and include the exact commands run in the final summary.

Target validations should include the equivalent of:

```bash
xcodebuild -list
xcodebuild -scheme Chroma-iOS -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcodebuild -scheme Chroma-macOS -destination 'platform=macOS' build
xcodebuild test -scheme Chroma-iOS -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

If the exact scheme names differ, use the implemented names consistently and report them.

## Notes for implementation

Prefer a structure that future tasks can extend cleanly:

* Task 002: app shell and routing refinement
* Task 003: performance surface
* Task 004: audio input service
* Task 005: analysis pipeline core
* Task 006: renderer foundation

Do not overbuild the renderer or DSP now. This task wins by creating a durable spine for the project.

## Deliverable summary requirements

When finished, report:

* what changed
* files touched
* validations run
* incomplete items, if any
* recommended next tasks

## Tests

- The first Codex prompt is intentionally scoped to **foundation only**.
- The docs align on the same architectural thesis: native iOS/macOS, MVVM UI shell, services for engines/infrastructure, serious future scaffolding.
- `Task 001` is atomic enough for Codex to execute without inventing the rest of the app.
- The output contract in `AGENTS.md` and the prompt are aligned, so Codex should produce structured summaries instead of vague completion notes.
