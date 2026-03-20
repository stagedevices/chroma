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
- iOS and Mac Catalyst action chrome share a two-column tile deck (glass-forward, fullscreen as immediate action)
- iOS uses medium-first sheets for actions; Catalyst uses adaptive popovers for short pickers and sheets for larger workflows
- iOS live mode controls are in Settings sheet sections; Catalyst retains persistent bottom live controls for desktop tuning
- Settings includes a glass appearance tile (`sun.max` / `moon.stars`) that toggles dark vs light glass chrome and switches idle ambient background black vs white with an ink-style transition
- a full-screen performance canvas backed by Metal
- five live modes (`Color Shift` + `Prism Field` + `Tunnel Cels` + `Fractal Caustics` + `Mandelbrot`) with stage-first composition
- `Color Shift` supports:
  - default flat solid backfill (pixel-uniform frame color)
  - directional anti-chatter PWM hue behavior with bistable side latching (left/right hue-side lock instead of wide free-running oscillation)
  - selectable excitement source modes (`Spectral`, `Temporal`, `Pitch`) to decide direction cues
  - dual-point hue clamp (`Hue Range`) with inside/outside selection and hue-spectrum track editing
  - stage-mic adaptive pitch confidence weighting that profiles voice-like vs noisy input and tightens/relaxes fusion gates accordingly
  - confidence/intensity-driven saturation response with no idle hue drift in silence
  - feathered hue boundary clamping for smooth constraint behavior (no hard stepping)
- optional `Feedback` chip path uses front-camera sampled color to drive abstract lava-lamp banding/shapes (no camera image passthrough)
- in Color Shift, `No Image In Silence` remains authoritative for hard-black silence output (including feedback path)
- `Prism Field` supports:
  - dedicated Facet Caustics multi-pass rendering (not radial spokes)
  - hybrid reactivity: continuous flow from live signal plus deterministic attack accents keyed by `attackID`
  - sparse mode controls (`Facet Density`, `Dispersion`) plus shared stage controls
  - black-floor-first composition and silence blackout policy via `No Image In Silence`
- `Tunnel Cels` supports:
  - dedicated pseudo-3D multipass tunnel rendering (field + shape + composite)
  - one-shape-per-attack spawning keyed to new `attackID` events with deterministic lane/sector placement
  - hybrid ADSR lifecycle (fixed attack/decay plus sidechain sustain/release hysteresis) tuned for live stage input
  - sparse mode controls (`Shape Scale`, `Depth Speed`, `Release Tail`) with mode-scoped `Variant` selection (`Cel Cards`, `Prism Shards`, `Glyph Slabs`)
  - black-floor-first composition and silence blackout policy via `No Image In Silence`
- `Fractal Caustics` supports:
  - dedicated Julia orbit-trap multipass rendering (`field` + `attack accents` + `composite`)
  - hybrid reactivity: continuous flow from amplitude/bands/pitch-confidence plus deterministic `attackID` pulse events
  - sparse mode controls (`Detail`, `Flow Rate`, `Attack Bloom`) with mode-scoped `Palette` selection across 8 curated gradient banks
  - black-floor-first composition and silence blackout policy via `No Image In Silence`
- `Mandelbrot` supports:
  - dedicated Mandelbrot-domain multipass rendering (`field` + minimal `attack contours` + `composite`)
  - continuous flight through fractal space with contour-rich boundary structure
  - traversal-style navigation through the mapping space (audio-driven heading, drift, and zoom “flight controls”)
  - deterministic attack-gated minibrot point-of-interest handoffs for guided travel without hard camera cuts
  - hybrid reactivity: continuous flight warp from amplitude/bands/pitch-confidence plus deterministic thin `attackID` pulses
  - palette variants are style-distinct (`topology`, `boundary`, `stream`, `particle` families), not just hue remaps
  - sparse mode controls (`Detail`, `Flow Rate`, `Zero Bloom`) with mode-scoped `Palette` selection across 8 curated gradient banks
  - quality-tier term/tap/accent scaling for realtime stability
  - black-floor-first composition and silence blackout policy via `No Image In Silence`
- typed domain models and service protocols
- per-mode preset workflow:
  - preset browser shows active-mode presets only
  - quick-save from iOS live-controls tile with optional inline rename
  - persisted local preset storage with a seeded starter bank (`Stage Color` plus one curated starter preset per remaining mode)
  - startup backfill: if a preset library is missing entire modes, one curated starter preset is added per missing mode
- production export path:
  - clean program-feed recording from renderer output (no shell chrome)
  - first-frame orientation lock so encoded output matches live program feed orientation (portrait remains portrait)
  - explicit export settings (resolution / fps / codec) persisted in Settings
  - sparse, medium-detent recorder console with prominent action tiles (`Start/Stop`, `Save to Photos`, `Share`)
  - optional mic capture toggle (`with mic` / `video-only`)
  - cache-first export output with explicit post-capture actions (`Save to Photos` primary, `Share` secondary)
- iOS external cast path:
  - live external-target detection and selection
  - external window renders clean program output while device stays operator surface
  - settings output includes an AirPlay route helper for quick route initiation
- initial renderer diagnostics and render-state contracts
- live audio input seam with metering + mono sample publication
- live analysis seam publishing `AudioFeatureFrame` (including pitch-confidence lock fields)
- initial logic tests for state, parameter, renderer-facing contracts, and audio pipeline core mapping

It does not yet ship a polished set/cue system, advanced multi-camera workflows, or final production UX polish for every route edge case.
