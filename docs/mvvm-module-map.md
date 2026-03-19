# MVVM Module Map

## Live app target

### `Apps/Chroma-iOS`
Owns the app entry point, platform scene configuration, app assets, and target metadata.

## Shared modules

### `Packages/ChromaAppCore`
- `AppRouter`
- `AppViewModel`
- `SessionViewModel`
- `ChromaAppBootstrap`
- root shell views
- sheet views including `FeedbackSetupSheet`
- renderer host embedding view
- fullscreen chrome-hide/reveal behavior

### `Packages/ChromaDomain`
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
- `AudioSampleFrame`
- parameter catalog and parameter store

### `Packages/ChromaSharedCore`
- `RendererSurfaceStateMapper`
- `AudioStatusFormatter`
- pure logic helpers consumed by app-core and tests

### `Packages/ChromaAudio`
- `AudioInputService`
- `InputCalibrationService`
- `PlaceholderAudioInputService`
- `LiveAudioInputService`
- `AudioMeterFrame` publication seam
- `AudioSampleFrame` publication seam
- `CameraFeedbackService`
- `PlaceholderCameraFeedbackService`
- `LiveCameraFeedbackService` (front camera capture for Color Shift feedback)

### `Packages/ChromaAnalysis`
- `AudioAnalysisService`
- `PlaceholderAudioAnalysisService`
- `LiveAudioAnalysisService`
- `AudioFeatureFrame` publication seam (including pitch/confidence lock fields)

### `Packages/ChromaRendering`
- `RendererService`
- `RenderCoordinator`
- `RendererSurfaceState`
- `RendererControlState`
- `RendererDiagnosticsSummary`
- real Metal renderer implementation
- headless test renderer implementation
- Metal shader sources for:
  - `Color Shift` flat backfill
  - Color Shift `Contour Flow` feedback passes (contour/evolve/present)
  - `Prism Field`

### `Packages/ChromaPresets`
- `PresetService`
- placeholder preset persistence implementation

### `Packages/ChromaDiagnostics`
- `DiagnosticsService`
- placeholder diagnostics implementation

### `Packages/ChromaRecorder`
- `RecorderService`
- placeholder export/recording implementation

### `Packages/ChromaExternalDisplay`
- `ExternalDisplayCoordinator`
- placeholder display routing implementation

### `Packages/ChromaSetlist`
- `SetlistService`
- placeholder set/cue implementation

## Tests

### `Tests/ChromaTests`
- app/router/view-model tests
- domain serialization tests
- parameter store tests
- renderer state and diagnostics tests
- audio pipeline core tests (meter -> feature, formatter, mapper modulation)

### `Tests/ChromaUITests`
- reserved for future UI flows
- intentionally minimal in Task 001
