# Task 017 — Color Shift Hue Clamp

## Intent

Upgrade `Color Shift` hue control from a scalar span to a two-point hue clamp (DaVinci-style) with inside/outside selection and a hue-colored track, while keeping stable parameter identity.

## Scope

- keep parameter ID `mode.colorShift.hueRange`
- change value contract to range payload (`min`, `max`, `outside`)
- keep legacy scalar preset/session compatibility via deterministic coercion
- apply clamp in Color Shift hue targeting (CPU-side)
- expose dual-handle hue control in both shell live controls and settings live controls

## Contract updates

- `ParameterControlStyle` adds `.hueRange`
- `ParameterValue` adds `.hueRange(min:max:outside:)`
- `mode.colorShift.hueRange` default becomes `.hueRange(min: 0.13, max: 0.87, outside: false)`

## Behavior

- inside arc uses ordered `min -> max` semantics with wrap across `0/1`
- outside mode uses the complement region
- clamp is feathered at boundaries (fixed v1 feather constant)
- hue clamp is applied after target hue derivation and before phase advance
- existing hold-in-silence / `No Image In Silence` policies remain unchanged

## UI

- hue range row uses:
  - dual draggable handles over hue-spectrum track
  - selected-range emphasis with non-selected dimming
  - inline `Inside/Outside` segmented control
  - degree readouts for both endpoints
- card and row height remain unchanged in compact tile-expanded control UI

## Validation

- domain serialization and parameter-store coercion tests
- mapper routing tests for hue min/max/outside
- renderer hue-clamp wrap/outside/feather tests
- iOS sim build + tests
- Mac Catalyst build
