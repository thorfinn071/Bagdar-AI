# Repository map

The root contains the Flutter package, platform projects and entry documentation.
Run examples and tools from the root unless a tool explicitly says otherwise.

| Location | Purpose |
| --- | --- |
| `lib/` | App entry points, camera controllers, Core/safety runtime, services, UI, onboarding, research and simulation adapters |
| `android/` | Android flavors, Kotlin plugins and C++ integrations |
| `ios/`, `linux/`, `macos/`, `web/`, `windows/` | Platform scaffolding; existence does not establish support or validation |
| `assets/` | Packaged detectors, fonts, labels and language-pack placeholders declared in `pubspec.yaml` |
| `test/`, `integration_test/`, `test_driver/` | Unit/widget, integration and driver checks plus their fixtures |
| `third_party/flutter_tts/` | Local TTS patch used by the app; see its `BAGDAR_PATCH.md` |
| `tool/` | Core verifier, spatial import/replay, model benchmarks, Blender, simulation, device-performance and voice-wake experiments |
| `tools/` | Native runtime setup, source-deposit tooling and session analysis |
| `scripts/` | Offline map/GTFS/city-package builders |
| `docs/` | Plans, contracts, protocols and dated evaluations; start at [the index](README.md) |
| `docs/_baseline_logs/`, `docs/_baseline_sources/` | Frozen receipts and associated source snapshots; retain their identities |
| `docs/archive/` | Earlier audits, reference prompts and the previous long README |
| `tool/archive/` | Historical one-off migration scripts retained for reference |
| `presentation/` | Presentation generators, creative-production guide and local office documents |
| `model_export/` | Export scripts, requirements and manifests; weights/ONNX candidates are local downloads |
| `local_data/` | Local map/GTFS inputs, ignored by Git |
| `output/` | Generated research runs, reports and recordings, ignored by Git |
| `scratch/` | Temporary logs, diffs, scripts and local cleanup backups, ignored by Git |

## Local creative and reference directories

`bagdar_blend/`, `bagdar_vid/`, `City/`, `FBX format/` and `VisionGuide/` remain
at their existing locations and are ignored by Git. The simulation renderer can
use `City/` by its current path. These folders are not Flutter application assets.

## Cleanup record: 2026-10-27

The cleanup moved 25 files without changing their bytes:

- Root audit and diagnostic notes moved to `docs/archive/`.
- Copied presentation skill references moved to `docs/archive/reference-prompts/`.
- Four historical `fix_*.py` scripts moved to `tool/archive/sos-fixes/`.
- Presentation documents, the Blender production guide and `update_pptx.py`
  moved to `presentation/`.
- Three root map/GTFS inputs moved to `local_data/maps/`.
- The extra root YOLO checkpoint moved to `model_export/local/yolo11n.pt`.
- Root logs/diffs/command output and the generated Android problems report
  moved to `scratch/repository-cleanup-2026-10-27/`.

The local snapshot in that scratch directory records the original Git status,
index hash, source hashes and every source/destination/hash pair. No files were
staged or committed as part of this cleanup. Existing deletions and unfinished
application changes were retained. The prior README is preserved in
[the archive](archive/readme-2026-10-27.md).

The presentation generator now writes next to its own source instead of to a
machine-specific absolute root path. It still requires its existing Node
dependency, `pptxgenjs`.

Two analyzer style notices in `tool/simulation/quality_report.dart` were also
resolved: use the package import for the existing blur detector and put the
path-rejection statement inside braces. Application algorithms are unchanged.

Some generated Linux/macOS platform files and presentation decks were already
tracked before cleanup. Ignore rules prevent new additions but do not remove
those existing index entries. The Git index was preserved; review any desired
untracking explicitly when preparing a commit.

## Cleanup verification

Executed on 2026-10-27 with Flutter 3.41.4 / Dart 3.11.1:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --concurrency=1 --reporter expanded`: 2,653 passed,
  19 skipped, no failures. This is the ordinary developer suite, not strict RC.
- Before/after standalone quality-tool smoke reports match byte for byte.
- `node --check presentation/build.js`: passed; no deck was regenerated.
- 25 moved-file SHA-256 checks, 204 documentation links and 30 representative
  ignore/keep rules passed.
- The 14,799 protected application, native, asset and test/fixture files match
  the pre-cleanup snapshot; existing staged state and deletions were preserved.

Local logs and the move/source verification receipt are in
`scratch/repository-cleanup-2026-10-27/`. This cleanup did not run strict Core RC,
build an APK or perform physical-device acceptance.

## Dataset preparation: 2026-10-28

The [dataset guide](../tool/datasets/README.md) describes the versioned manifest,
bundle creation, integrity checks and restoration. The reviewed local preparation
contains 23 bundles and 17,383 archived files; four speech metadata/license files
also remain in the source snapshot. The proposed source snapshot is approximately
107 MiB, with the large payloads provisioned separately at their original paths.

An isolated Git checkout exposed line-ending conversion in frozen inputs and
required dependencies that existed only under ignored scratch/model-export paths.
Git attributes now preserve evidence/assets and 50 hash-pinned live sources.
Exact legacy dependency paths and hashes are recorded explicitly; arbitrary
scratch content and recordings are excluded. Existing historical hashes and
application algorithms were not rewritten.

All 23 bundles were exercised through loopback HTTP restoration in stages;
the final manifest verifies every restored file. Python tool tests: 17 passed.
The isolated checkout's analyzer was clean. A full Flutter run with
`BAGDAR_RC=true` exposed missing local inputs; after restoration, all affected
replay/model/history groups and the previously skipped depth replay passed their
targeted retests. The aggregate Core verifier, Android build, public hosting and
physical-device acceptance were not run as part of this preparation.

Nine generated Linux/macOS entries were removed from Git tracking; their local
files are unchanged. Only these removals are staged. Dataset payload tracking
is unchanged until a durable download source is published and verified. No
commit, push, release publication or history rewrite was performed.

Reviewed bundles and checksums are in ignored
`output/research-data/bagdar-research-2026-10-28-v4-reviewed/`. Local source,
restore and test receipts are in ignored
`scratch/repository-preparation-2026-10-28/`.
