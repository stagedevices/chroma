# Task 023: Settings Pro Controls (Performance, Calibration, Navigation, Defaults, Recovery)

## Summary
- Add production-oriented settings systems for stage stability and repeatability:
  - Performance Mode (`Auto`, `High Quality`, `Safe FPS`) with thermal-aware fallback
  - Audio Calibration (`Calibrate Room Noise`, attack gate trim, silence gate trim)
  - Mandelbrot Navigation Lock (`Guided Zoom` / `Free Flight`) with steering-strength damping
  - Mode Defaults (`Set Current as Mode Default`, `Reset Mode Defaults`)
  - Session Recovery (autosave, restore on launch, clean-state panic reset)

## Scope
- `ChromaSession` persists `performanceSettings`, `audioCalibrationSettings`, and `sessionRecoverySettings` with decode-safe defaults.
- `SessionViewModel` wires settings intents to analysis/renderer/persistence seams.
- Add `ModeDefaultsService` and `SessionRecoveryService` with placeholder + disk implementations.
- Add iOS/Catalyst Settings tile sections for all new controls using existing glass styling.
- Mapper/renderer receive performance mode + silence-gate + navigation parameters.
- Mandelbrot traversal respects navigation mode (`Guided` vs `Free`) and steering damping.

## Non-goals
- No new render mode.
- No preset schema changes.
- No changes to mode IDs or existing parameter IDs outside added navigation parameters.
