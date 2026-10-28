# Spatial recording import v2 — paired-frame admission

Status: software-only validator. No phone recording has been imported or
measured by this contract. It does not enable assistive guidance.

`tool/import_spatial_recording.dart` accepts legacy schema v1 unchanged. A
recorded schema v2 manifest adds a `capture` object and exactly one derived
`frame-pairs` JSONL artifact. The manifest and JSONL must be stored outside Git
when they describe private recordings; keep any saved receipt outside Git as
well. The tool reads the files in place, emits a receipt, and redacts the exact
raw-media retention location from that receipt. Do not put RGB/depth images,
videos, base64 media, participant
identifiers, or precise location in the JSONL.

The v2 `capture` object requires:

| Field | Meaning |
| --- | --- |
| `deviceModel`, `androidVersion` | Named device/build context |
| `cameraMountId`, `rgbCameraId`, `depthProviderId` | Capture configuration |
| `depthModelId`, `depthModelHash`, `preprocessId` | Depth implementation identity; never silently mix models |
| `depthSemantics` | `metricMeters` or `relativeProximity`; relative values are never metres |
| `timestampDomain` | Exactly `elapsedRealtimeUs` for both RGB and depth |
| `maxPairSkewUs` | Positive bound up to the current 150,000 µs camera-session limit; use a tighter measured bound when available |

Each JSONL row has `frameIndex` (contiguous from zero), `sessionGeneration`,
`frameId`, `rgbTimestampUs`, `rgbSha256`, `rgbTransformId`, and `depthStatus`.
For `aligned`, it also has `depthTimestampUs`, `depthSha256`, and
`depthTransformId`. For `missing`, those three fields must be null or absent.
Only `aligned` and explicit `missing` are admitted: stale, reused, skewed, or
transform-mismatched depth must not be represented as an aligned pair. Frame
IDs increase within a session; RGB timestamps increase across the recording.

Example row (hash values here are placeholders):

```json
{"frameIndex":0,"sessionGeneration":1,"frameId":1,"rgbTimestampUs":1000000,"rgbSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","rgbTransformId":"upright-r0","depthStatus":"aligned","depthTimestampUs":990000,"depthSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","depthTransformId":"upright-r0"}
```

Import a consent-controlled export:

```powershell
dart run tool/import_spatial_recording.dart --manifest C:\private\bagdar-capture\manifest.json
```

The receipt reports frame count, aligned/missing counts, and the maximum
observed timestamp skew. It has `accuracyMetricsReady: false` because metadata
alone cannot establish physical pixel alignment, depth correctness, labels,
critical-hazard recall, false stops, or device runtime performance. Those need
reviewed annotations, downstream replay, and named-device tests. A successful
receipt must never promote `GenericObstacleMode.shadow`.

Validation command:

```powershell
flutter test --no-pub test/spatial_recording_import_test.dart
```

## Offline shadow metrics over labelled frames

To evaluate a recording, add two hashed derived artifacts to the same v2
manifest. The importer still admits a recording without these artifacts;
evaluation requires exactly one of each:

| `kind` | File | Contract |
| --- | --- | --- |
| `event-annotations` | `.json` | Human-supplied critical hazard events and labelled passable frame intervals |
| `shadow-decisions` | `.jsonl` | One explicit decision per frame from one pinned model/preprocess run |

`event-annotations` schema v1:

```json
{
  "schemaVersion": 1,
  "annotationRevision": "review-draft-1",
  "criticalEvents": [
    {
      "hazardId": "low-obstacle-1",
      "hazardClass": "low-obstacle",
      "startFrameIndex": 0,
      "endFrameIndex": 2,
      "latestStopTimestampUs": 1150000
    }
  ],
  "passableIntervals": [
    {"startFrameIndex": 3, "endFrameIndex": 5}
  ]
}
```

Frame ranges are inclusive. Critical and passable labels cannot overlap;
unlabelled frames are excluded from recall/false-stop denominators and counted
separately. A critical event's deadline must be no earlier than the RGB
timestamp of its first frame. Distinct hazards need distinct `hazardId`s.

Each `shadow-decisions` JSONL row contains `frameIndex`,
`sessionGeneration`, `frameId`, `decisionTimestampUs`, `action`, `delivery`,
`runId`, `modelId`, `modelHash`, and `preprocessId`. `action` is one of
`stopNow`, `holdAndScan`, `continueForward`, or `none`; `delivery` must be
`shadow`. The session/frame IDs must match the paired capture frame, all
timestamps use the capture's monotonic domain, and the run/model/preprocess
identity must remain constant. A skipped inference must be an explicit `none`,
not an omitted row.

```powershell
dart run tool/evaluate_spatial_recording.dart `
  --manifest C:\private\bagdar-capture\manifest.json
flutter test --no-pub test/spatial_recording_accuracy_test.dart
```

The report distinguishes events with a `stopNow` by the deadline, late
`stopNow`, and no `stopNow`; `onTimeCriticalRecall` uses only timely stops.
`falseStopRate` is the fraction of labelled passable frames with `stopNow`,
including passable frames where depth was missing; the latter also have their
own degraded counter. Alert latency is measured from the first labelled RGB
frame to the first shadow stop and reported as nearest-rank p50/p90. A zero
denominator is `null`, never an invented 0% or 100%. Always-stopping behavior
can have high recall and a high false-stop rate, so both must be reviewed.

This is an offline comparison of **supplied labels and supplied shadow
decisions**. It does not run MiDaS/DA-V2, verify that labels are true, measure
physical pixel alignment, test user-facing alerts, or validate a named phone.
The included tests use artificial data only. Keep real private manifests,
decisions, annotations, and reports outside Git. No metric from this tool
permits promotion out of `GenericObstacleMode.shadow`.
