# Task 013: Riemann Atlas V2 (Reference-Faithful Zeta Domain Coloring)

## Goal
Replace corridor-biased Riemann rendering with a reference-faithful zeta domain-coloring atlas while preserving preset compatibility (`VisualModeID.riemannCorridor` and existing parameter IDs).

## Scope
- Keep stable IDs:
  - `mode.riemannCorridor.detail`
  - `mode.riemannCorridor.flowRate`
  - `mode.riemannCorridor.zeroBloom`
  - `mode.riemannCorridor.paletteVariant`
- Rename user-facing mode label to `Riemann`.
- Rework Riemann field to full-strip-emphasis domain coloring (`Re(s)` around `-5...5`, tall imaginary span).
- Keep audio interaction as traversal controls (heading/drift/zoom flight) over the mapping space, not arbitrary paint.
- Keep attack accents minimal and deterministic (`attackID`-gated).
- Preserve dedicated `.riemann` multipass path, fixed pools, fixed render targets, and quality-tier degradation.

## Implementation Notes
- Domain coloring channels:
  - hue from `arg(ζ(s))`
  - value from compressed `log|ζ(s)|` with right-side plateau readability
  - saturation from contour/gradient structure
- Add explicit phase and magnitude contour lines for reference-style ribbing/fans.
- Use hybrid zeta evaluation:
  - eta continuation branch for center/right strip
  - functional-equation branch for left strip with guarded Lanczos gamma approximation
- Simplify composite: remove corridor caustic wash and strong corridor vignette bias; keep dark-first grading.
- Ensure no visible branch-cut seam from palette mapping in final output.
- Make palette variants style-distinct (`topology`, `boundaries`, `streams`, `particles`) instead of basic recolors.

## Validation
- iOS simulator build
- iOS simulator tests
- Mac Catalyst build
- math checks:
  - `ζ(2)` sanity
  - `ζ(-1)` sanity
  - finite sweep across representative strip samples
  - near-singular guard behavior
- non-degeneracy guard:
  - domain-color helper exhibits two-dimensional structure variance to prevent single-axis sweep regressions

## Compatibility
- Internal mode ID remains `riemannCorridor` for decode/preset stability.
- User-facing mode label and summaries are updated to `Riemann`.
