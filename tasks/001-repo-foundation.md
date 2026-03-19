# Task 001 — Repo Foundation Reset

## Purpose

Reset Chroma onto a clean iOS-first + Mac Catalyst repository foundation so future tasks can land against stable contracts instead of the legacy prototype shell.

## Supports

- `AGENTS.md`
- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`

## In scope

### Repo / project structure
- normalize the repo root around `Apps/`, `Packages/`, `Tests/`, `docs/`, `tasks/`, and `Legacy/`
- keep the old prototype under `Legacy/Prototype`
- keep one live iOS app target with Mac Catalyst enabled
- expose one live shared scheme `chroma`

### App shell scaffold
- create one sparse root shell with one primary performance surface
- create top-level routing seams for mode picker, preset browser, recorder/export, and settings/diagnostics
- create app and session view models plus dependency bootstrap

### Domain and subsystem scaffolding
Create real typed models and placeholder seams for:
- sessions
- modes
- parameters
- presets
- output/display
- diagnostics
- export profiles
- sets/cues
- audio feature frames
- audio input
- analysis
- rendering
- recorder/export
- external display coordination

### Rendering integration seam
- create a SwiftUI-compatible renderer host suitable for future Metal work
- keep behavior placeholder-backed in this task

### Testing baseline
Add unit tests covering at minimum:
- domain serialization basics
- parameter store behavior
- app/session state behavior

## Out of scope

Do not implement:
- a finished renderer
- a finished audio pipeline
- FFT or full analysis logic
- a finished preset browser
- a finished recorder/export system
- onboarding or UI polish passes
- multiple finished visual modes
- third-party dependencies

## Required deliverables

### 1. One live app target
Create one iOS app target that also builds under Mac Catalyst.

### 2. Live scheme
Provide one live shared scheme:
- `chroma`

### 3. Root shell
Create a sparse shell with:
- one primary performance surface
- sheet routing seams for mode picker, preset browser, recorder/export, and settings/diagnostics

### 4. App/session view models
Create:
- `AppRouter`
- `AppViewModel`
- `SessionViewModel`

### 5. Domain model scaffolding
Create initial models for:
- `ChromaSession`
- `VisualModeID`
- `VisualModeDescriptor`
- `VisualMorphState`
- `ParameterDescriptor`
- `ParameterValue`
- `ParameterGroup`
- `Preset`
- `DisplayTarget`
- `OutputSessionState`
- `ExportProfile`
- `DiagnosticsSnapshot`
- `PerformanceSet`
- `PerformanceCue`
- `AudioFeatureFrame`

### 6. Service / coordinator scaffolding
Create protocols and placeholder implementations for:
- `AudioInputService`
- `InputCalibrationService`
- `AudioAnalysisService`
- `RendererService`
- `RenderCoordinator`
- `PresetService`
- `RecorderService`
- `DiagnosticsService`
- `ExternalDisplayCoordinator`
- `SetlistService`

### 7. Parameter store seam
Create a parameter store with:
- global and mode-scoped parameter values
- stable grouping
- basic and advanced tiers

### 8. Validation
Validate with:
- `xcodebuild -list`
- `xcodebuild -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build`
- `xcodebuild -scheme chroma -destination 'generic/platform=macOS,variant=Mac Catalyst' build`
- `xcodebuild test -scheme chroma -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'`
