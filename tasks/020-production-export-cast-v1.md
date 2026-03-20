# Task 020: Production Export + External Cast V1

## Scope
- Export captures clean renderer program feed (no shell chrome).
- Export supports `Include Mic Audio` toggle (`with mic` / `video-only`).
- Finalized exports are written to app cache and opened via share sheet.
- iOS external cast routes clean program to external display while device remains operator UI.
- Mac Catalyst remains single-window output for this task.

## Contracts
- `RecorderCaptureRequest`
- `RecorderCaptureState`
- `RecorderService` state publishers and start/stop lifecycle
- `RendererFrameCaptureSink` + `RendererService.setFrameCaptureSink(_:)`
- `ExternalDisplayCoordinator` live targets + selected target publishers

## UI
- `RecorderExportSheet` is operational:
  - export profile select
  - mic-audio toggle
  - start / stop-and-export controls
  - live state + elapsed + failure/status messaging
  - automatic share-sheet handoff on successful finalize
- Settings Output section uses live target availability and includes iOS AirPlay route picker helper.

## Defaults and policies
- `Include Mic Audio` defaults to `on` and persists across launches.
- Export output location: cache directory under `Chroma/Exports`.
- Cache retention: bounded cleanup (count + age).
- Codec request falls back to supported runtime codec with non-fatal status message.

## Validation intent
- Recorder state transitions and export output are logic-tested.
- External display target reconciliation is logic-tested.
- End-to-end build/test validation via iOS Simulator + Mac Catalyst build.
