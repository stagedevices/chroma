# Task 018: Color Shift Directional Excitement Modes (Anti-Chatter PWM)

## Summary
Rework Color Shift hue motion from wide excitement-amplified oscillation to a directional, bistable PWM model. Direction is driven by a selectable excitation source and held with hysteresis/dwell/cooldown so the mode stays stage-stable under noisy input.

## Implementation Notes
- Add `mode.colorShift.excitementMode` (`0...2`, default `0`) with stable ID.
- Extend renderer control state with `colorShiftExcitementMode`.
- Include the parameter in Color Shift surface controls so it appears in the iOS full-width icon tile and expands in-place as a segmented selector (`Spectral`, `Temporal`, `Pitch`).
- Keep hue range thumbs behavior and center trim wheel behavior unchanged.
- Add renderer-local direction state:
  - latched side sign (`-1` or `+1`)
  - smoothed evidence
  - candidate sign + dwell timer
  - switch cooldown
  - last attack ID and pitch phase cache for cue derivation
- Direction evidence sources:
  - `Spectral`: low/high split with mid bias
  - `Temporal`: transient-vs-sustain cue
  - `Pitch`: up/down pitch-phase drift, confidence-gated fallback to spectral/temporal blend
- Replace bipolar PWM targeting with side-locked PWM targeting (center-to-side travel only).
- Keep silence blackout policy unchanged.

## Validation
- Build/test iOS simulator target.
- Build Mac Catalyst target.
- Ensure Color Shift no longer chatters near neutral input and no longer increases oscillation amplitude with excitement.
