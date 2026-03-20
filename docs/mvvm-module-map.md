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
- iOS + Catalyst tile-based top action deck (2-column tiles)
- iOS medium-first sheet routing, Catalyst adaptive popover/sheet routing
- modes sheet rendered as a hero pager with explicit apply CTA (swipe previews only; no implicit mode commit)
- mode-style pickers for Tunnel `Variant` and Fractal/Mandelbrot `Palette` (sheet on iOS, popover on Catalyst)
- iOS settings sheet as the home for live mode controls (persistent bottom sliders removed on iOS)
- settings pro-control sections for performance policy, audio calibration, Mandelbrot navigation lock, mode defaults, and session recovery
- settings appearance tile toggles light/dark glass theme (`sun.max` / `moon.stars`) and triggers shared ink-transition rerender
- settings includes an in-stack About subpage with glass link tiles (website/privacy/support) opened via external browser routing
- custom hue-range editor row (dual handle + inside/outside) for Color Shift controls in both shell/settings control surfaces
- bottom full-width action tile expansion for icon-first live controls, including Color Shift `Excitement Mode` segmented selection
- mode-scoped preset browser and quick-save/inline-rename preset interactions
- mode defaults persistence flow (save/reset current mode defaults, apply defaults on mode switch)
- session recovery flow (debounced autosave snapshot, restore on launch, clean-state panic reset)
- iOS export sheet flow with live capture controls (`Include Mic Audio`, start/stop, elapsed/status, share handoff)
- iOS external-program window host wiring (device operator UI + clean external program feed)

### `Packages/ChromaDomain`
- `ChromaSession`
- `VisualModeID`
- `VisualModeDescriptor`
- `VisualMorphState`
- `ParameterDescriptor`
- `ParameterValue`
- `ParameterControlStyle` (including hue-range control style)
- `ParameterGroup`
- `Preset`
- `DisplayTarget`
- `OutputSessionState`
  - includes persisted `glassAppearanceStyle` (`dark` / `light`) for shell + ambient background styling
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
- `LiveInputCalibrationService` (ambient capture window -> attack/silence threshold recommendations)

### `Packages/ChromaAnalysis`
- `AudioAnalysisService`
- `PlaceholderAudioAnalysisService`
- `LiveAudioAnalysisService`
- `AudioFeatureFrame` publication seam (including pitch/confidence lock fields)

### `Packages/ChromaRendering`
- `RendererService`
- `RenderCoordinator`
- `RendererFrameCaptureSink` seam for export capture
- `RendererSurfaceState`
- `RendererControlState`
- `RendererDiagnosticsSummary`
- real Metal renderer implementation
- headless test renderer implementation
- Metal shader sources for:
  - `Color Shift` flat backfill
  - Color Shift camera-color-driven feedback field (abstract banding/blob shapes; no camera-image passthrough)
  - `Prism Field`
  - `Tunnel Cels` (field/shapes/composite multipass)
  - `Fractal Caustics` (field/accents/composite multipass)
  - `Mandelbrot` (field/accents/composite multipass with traversal-driven domain coloring and attack-gated minibrot handoffs)

### `Packages/ChromaPresets`
- `PresetService`
- `DiskPresetService` for local persisted presets
  - startup mode-gap backfill from curated seed presets (one starter per missing mode)
- placeholder preset persistence for tests and lightweight scaffolding

### `Packages/ChromaAppCore` (persistence seams)
- `ModeDefaultsService` + disk/placeholder implementations
- `SessionRecoveryService` + disk/placeholder implementations

### `Packages/ChromaDiagnostics`
- `DiagnosticsService`
- placeholder diagnostics implementation

### `Packages/ChromaRecorder`
- `RecorderService`
- `LiveRecorderService` (AVAssetWriter, optional mic track, cache output, bounded cleanup)
- placeholder recorder implementation for tests/scaffolding

### `Packages/ChromaExternalDisplay`
- `ExternalDisplayCoordinator`
- `LiveExternalDisplayCoordinator` for iOS screen connect/disconnect and selected-target reconciliation
- placeholder coordinator for Catalyst/tests

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
