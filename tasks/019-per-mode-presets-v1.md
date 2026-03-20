# Task 019: Per-Mode Presets V1

## Summary
Implement per-mode preset UX and behavior while preserving existing preset schema compatibility:
- active-mode preset browsing
- quick save from the iOS live-controls tile
- optional rename after quick save
- local disk persistence
- keep seeded `Stage Color` preset for `Color Shift`

## Implementation
- Keep `Preset` shape unchanged (`id`, `name`, `modeID`, `values`).
- Extend preset service seam with `deletePreset(id:)`.
- Add `DiskPresetService`:
  - JSON persistence in app support/documents fallback
  - deterministic sorted storage
  - graceful decode fallback to empty
  - seed insertion only when store file is missing
- Update `SessionViewModel`:
  - `presetsForActiveMode`
  - `quickSaveActiveModePreset()`
  - `renamePreset(id:newName:)`
  - `deletePreset(id:)`
  - snapshot capture rule for save: globals + active mode assignments only
- Update Preset Browser sheet:
  - active-mode filtered list
  - mode-specific empty state copy
  - rename/delete actions
- Update iOS action master tile save row:
  - first tap quick-saves immediately
  - inline rename affordance for newly saved preset
  - no tile height growth

## Tests
- `DiskPresetService` seed/load/save/delete deterministic tests.
- Session/view-model tests for:
  - mode filtering
  - quick-save payload scope
  - rename/delete active preset metadata updates.
- Existing build/test matrix:
  - iOS simulator build
  - iOS simulator tests
  - Mac Catalyst build

## Assumptions
- Internal IDs remain stable.
- Per-mode behavior is enforced in browser/save UX.
- Existing direct `applyPreset` remains compatible.
