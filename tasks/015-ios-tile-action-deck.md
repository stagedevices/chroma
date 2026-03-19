# Task 015: iOS Tile Action Deck + Medium-First Sheets

## Summary

Redesign the iOS action chrome into a two-column tile system with glass-forward styling and symbol motion accents, while preserving Catalyst’s existing capsule chrome.

For iOS:
- all top actions except `Fullscreen` open sheets
- sheets are medium-first with per-destination expansion policy
- persistent bottom live sliders are removed
- live controls are relocated into `Settings` sections

## Product decisions

- Scope is iOS behavior only; Mac Catalyst keeps existing action cluster and bottom control panel.
- Tile order is:
  - `Modes`
  - mode-specific tile (`Feedback` or `Variant` or `Palette`)
  - `Presets`
  - `Export`
  - `Settings`
  - `Fullscreen`
- `Fullscreen` remains an immediate toggle action (no sheet).
- Mode-specific style actions are explicit picker sheets:
  - Tunnel `Variant` (`0...2`)
  - Fractal `Palette` (`0...7`)
  - Mandelbrot `Palette` (`0...7`)

## Sheet policy

- `.medium + .large`:
  - `modePicker`
  - `presetBrowser`
  - `settingsDiagnostics`
- `.medium` only:
  - `feedbackSetup`
  - `recorderExport`
  - `tunnelVariantPicker`
  - `fractalPalettePicker`
  - `riemannPalettePicker`

## Implementation notes

- Introduce stable routing cases for mode-style picker sheets in `AppSheetDestination`.
- Keep existing cycling methods for compatibility, but add explicit setter methods used by picker sheets.
- Use iOS 26 glass APIs when available (`glassEffect`/glass style), with material fallback for earlier OS versions.
- Respect accessibility reduce motion by disabling continuous icon animation when enabled.

## Validation

- Router/AppViewModel tests for new destinations and presenter methods.
- SessionViewModel tests for explicit mode-style setters.
- Sheet detent policy logic tests.
- iOS simulator build and test.
- Mac Catalyst build.
