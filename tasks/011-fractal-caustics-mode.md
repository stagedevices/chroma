# Task 011: Fractal Caustics V1 (Audio-Interactive Julia Orbit-Trap)

## Summary
Add a new live mode, `Fractal Caustics`, implemented as a dedicated GPU path:
- Julia-field core
- orbit-trap caustic identity
- hybrid flow + attack reactivity
- audio-only interaction in v1
- curated palette chip cycle
- sparse stage controls (3 sliders + 1 chip)

## Scope
- add `VisualModeID.fractalCaustics`
- add stable mode parameters:
  - `mode.fractalCaustics.detail`
  - `mode.fractalCaustics.flowRate`
  - `mode.fractalCaustics.attackBloom`
  - `mode.fractalCaustics.paletteVariant` (snapped `0...7`)
- map new fields into renderer control/uniform state
- add top-row `Palette` chip in Fractal mode only
- add dedicated Fractal multipass renderer path:
  1. `fractal_field`
  2. `fractal_accents`
  3. `fractal_composite`
- use fixed pulse pool keyed to new `attackID` values
- add quality tier degradation for fractal path
- update docs and tests for catalog/mapping/pools/pass selection/blackout behavior

## Notes
- gradient customization in v1 is curated palette-bank selection, not a free-form editor
- no touch or motion interactions in v1
- other modes remain behaviorally unchanged outside shared stability handling
