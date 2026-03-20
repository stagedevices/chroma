# Task 022: Light Glass Appearance Toggle (Shell + Settings + Ambient)

## Summary
- Add a persisted appearance mode toggle (`dark` / `light`) in Settings.
- Toggle is exposed as a glass tile using `moon.stars` and `sun.max`.
- Switching appearance updates shell chrome, settings glass cards, and idle ambient surface background.
- Apply an ink-style transition animation on appearance changes.

## Scope
- `OutputSessionState` adds `glassAppearanceStyle` with legacy decode fallback.
- `SessionViewModel` adds appearance toggle/set APIs and publishes an appearance transition token.
- `RootShellView` and `SettingsDiagnosticsSheet` run ink-transition overlays keyed by token.
- `PerformanceSurfaceView` idle background switches black/white by appearance.
- Shared glass tile/card modifiers now support light and dark variants.

## Non-goals
- No render-mode math changes.
- No parameter ID changes.
- No export/cast workflow changes.
