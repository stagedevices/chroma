# Chroma Product Brief

## Positioning

Chroma is a live audio-reactive visual instrument for performers, directors, and capture/render workflows on Apple platforms.

It is not a VJ clip launcher or a general-purpose editor. Chroma should feel like a coherent instrument with one primary surface, disciplined control surfaces, and reliable stage output.

## Product goals

- make one serious audio-reactive visual engine possible
- keep performance operation sparse, legible, and stage-ready
- support projector and external-display workflows from the start
- create durable foundations for presets, setlists, cues, diagnostics, and export
- keep the codebase organized around long-term engine boundaries rather than demo convenience

## Experience principles

- one primary performance surface
- black/darkness as compositional material
- stable controls with clear naming
- minimal shell chrome around the visual surface
- operator confidence over novelty

## Core workflow pillars

### Perform
- launch into a performance-oriented shell
- tune the active mode with stable parameters
- route output to the correct screen surface
- monitor system health and recover quickly

### Preset and mode work
- switch between named visual modes
- capture and recall presets against stable parameter contracts
- keep mode-specific and global parameters explicit

### Output and capture
- maintain a clean seam between operator UI and stage output
- support future recorder/export workflows without distorting the live shell

## Current scope

The current repository work establishes the foundation, first real render spine, and first live audio-to-feature path:
- one iOS-first app target with Mac Catalyst support
- one sparse root shell with routing seams
- a full-screen performance canvas backed by Metal
- two live modes (`Color Shift` + `Prism Field`) with stage-first composition
- `Color Shift` supports:
  - default flat solid backfill (pixel-uniform frame color)
  - pitch-reactive hybrid lock+glide hue behavior (YIN + HPS fallback, confidence-gated, hysteresis-stable)
  - stage-mic adaptive pitch confidence weighting that profiles voice-like vs noisy input and tightens/relaxes fusion gates accordingly
  - confidence/intensity-driven saturation response with no idle hue drift in silence
  - optional `Feedback` chip path (`Contour Flow`) driven by front-camera contour injection and GPU recursion, tinted by Color Shift hue logic
- in Color Shift, `No Image In Silence` remains authoritative for hard-black silence output (including feedback path)
- `Prism Field` supports:
  - dedicated Facet Caustics multi-pass rendering (not radial spokes)
  - hybrid reactivity: continuous flow from live signal plus deterministic attack accents keyed by `attackID`
  - sparse mode controls (`Facet Density`, `Dispersion`) plus shared stage controls
  - black-floor-first composition and silence blackout policy via `No Image In Silence`
- typed domain models and service protocols
- initial renderer diagnostics and render-state contracts
- live audio input seam with metering + mono sample publication
- live analysis seam publishing `AudioFeatureFrame` (including pitch-confidence lock fields)
- initial logic tests for state, parameter, renderer-facing contracts, and audio pipeline core mapping

It does not ship a finished visual engine, polished preset browser, or production export stack.
