# AGENTS

## Project identity

Chroma is a native Apple live audio-reactive visual instrument for concerts, performances, and capture/render workflows.

It is not a traditional VJ app, video editor, or compositing suite.

Chroma should feel like a tunable instrument:
- one primary performance surface
- stage-ready output
- elegant, sparse, high-fidelity visual behavior
- strong architectural foundations for future expansion

## Source of truth

When working in this repository, treat the following as the primary project contract:
- `AGENTS.md`
- `docs/product-brief.md`
- `docs/architecture.md`
- `docs/mvvm-module-map.md`
- `tasks/*.md`

If implementation diverges from architecture or product intent, update the relevant docs in the same change.

## Stack constraints

Preferred stack:
- Swift
- SwiftUI for app shell and controls
- Metal / MetalKit for rendering
- AVAudioEngine for live audio I/O
- Accelerate / vDSP for analysis math

Platform strategy:
- native iOS target
- Mac Catalyst distribution from the same iOS-first app target
- shared code/modules where appropriate
- not separate native macOS-first architecture in this repo reset

## Architectural rules

### 1. Keep boundaries clean
Use MVVM for app/UI state flow, but do not put DSP, rendering internals, or complex infrastructure logic into views or view models.

Views:
- render UI
- bind to view models
- manage local ephemeral UI state only

ViewModels:
- coordinate UI-facing state
- issue intents/actions
- bind services to views
- avoid becoming dumping grounds

Services / engines:
- audio input
- analysis
- rendering
- recorder/export
- external display coordination

Domain models:
- parameters
- presets
- modes
- sessions
- sets / cues
- export profiles
- diagnostics summaries

### 2. Prefer stable contracts
Choose clear, stable names for:
- parameters
- mode identifiers
- preset schema
- service protocols
- diagnostics summaries

Do not rename public-facing parameters or core models casually.

### 3. Build scaffolding, not fake completeness
For early tasks:
- create real architectural seams
- create real protocols, models, and placeholders where appropriate
- do not stub misleading demo logic that will be thrown away immediately

### 4. No architectural drift
Do not:
- collapse modules together for convenience
- move rendering into UI layers
- move analysis into views
- introduce magical shared singletons without justification
- add broad abstractions with no clear use

### 5. External display is first-class
Chroma must support stage/projection workflows. Even when output features are only scaffolded, the architecture should assume:
- separable UI surface and output surface
- fullscreen/performance mode
- future external display routing

## Dependency policy

Do not add third-party dependencies unless explicitly required by a task or justified in the change summary.

Before adding any dependency:
- explain why Apple-native frameworks are insufficient
- explain the long-term maintenance cost
- explain the architectural boundary it serves

## Product direction guardrails

Protect these priorities:
- beautiful audio-reactive visuals
- stage-ready output
- one serious visual engine
- long-term architecture
- elegant and sparse aesthetic
- black/darkness as compositional material
- future-ready scaffolding for more modes, presets, sets, and export

Avoid turning Chroma into:
- a stock VJ app
- a clip launcher
- a video editor
- a compositing suite
- a kitchen-sink prototype

## Expected repo shape

The repository should evolve toward:
- one Catalyst-enabled iOS app target under `Apps/`
- shared domain/services/modules under `Packages/`
- dedicated tests under `Tests/`
- legacy prototype code under `Legacy/`
- docs and task briefs that remain aligned with implementation

## Task execution rules

When executing a task:
1. Read the relevant docs first.
2. Stay inside the task scope.
3. Keep diffs narrow and deliberate.
4. Update docs if architectural assumptions change.
5. Add or update tests for logic-bearing code where applicable.
6. Run relevant build/test validation before finishing.

## Output contract for every task

End every task with:
- what changed
- files touched
- validation run
- incomplete items, if any
- risks / follow-up tasks

## Quality bar

Prefer:
- clarity over cleverness
- durability over speed hacks
- explicit contracts over hidden behavior
- platform-native solutions over unnecessary abstraction

The result should resemble the beginning of a serious product.
