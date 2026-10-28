# Working on Bagdar

Run commands from the repository root. Start with the [README](README.md),
[documentation index](docs/README.md), and [repository map](docs/repository-structure.md).

## Scope and evidence

Core is the default product profile. Research and simulation need explicit build
flags. Keep generic obstacle geometry in shadow mode; missing, invalid or stale
observations do not establish clear space. Preserve freshness limits, safety
authority and external SOS boundaries when changing a subsystem.

Report software, replay, emulator and physical-device results separately. Link
the exact dated report and source/input/build identities when available. Do not
turn an older passing test count into a claim about the current checkout.

## Where files belong

- Application code: `lib/`; Android code: `android/app/src/`.
- Tests: `test/`, `integration_test/`, `test_driver/`; deliberate fixtures stay
  alongside their test contracts.
- Reproducible experiments and verifiers: `tool/`.
- Native setup and session analysis: `tools/`; offline city data builders: `scripts/`.
- Plans, protocols and evaluations: `docs/`; add new documents to `docs/README.md`.
- Temporary scripts, logs and diffs: ignored `scratch/`; generated runs: ignored `output/`.
- Downloaded map inputs: ignored `local_data/`; model candidates: `model_export/`.
- Presentations and their generators: `presentation/`.

Keep existing fixture paths and immutable receipts stable. Do not move a
benchmark family merely to make its directory smaller: source hashes and frozen
manifests can depend on those paths. `docs/_baseline_logs/` and
`docs/_baseline_sources/` contain deliberate evidence, not disposable caches.

Large research payloads have a [versioned bundle and restore tool](tool/datasets/README.md).
The bundles are published in a private, versioned GitHub research release.
Run `python tool/datasets/datasets.py restore` before the full suite, using your
GitHub credentials or a contents-read token held in the environment. Keep manifests,
small fixtures, licenses and frozen source snapshots in Git. Restore payloads
to their existing paths and verify their exact hashes before running the full
replay suite; never replace a missing-corpus failure with a silent skip.

Preserve the targeted Git attributes for byte-pinned evidence and replay
sources. Line-ending conversion alone can invalidate their frozen hashes.

## Verification

```powershell
flutter pub get
python tool/datasets/datasets.py restore
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
```

For the aggregate Core checks and stricter fixture requirements, follow
[tool/verify_core.md](tool/verify_core.md). Native, device and experimental tools
have additional prerequisites; use the relevant protocol instead of assuming
the Flutter suite covers them.

Run the checks relevant to your change. Record commands, failures, skipped
coverage and device gates honestly. Save new verification output under
`scratch/` or `output/`, not beside `pubspec.yaml`.

## Git hygiene

Review `git status --short` and the actual diff before staging specific paths.
Preserve unrelated changes in this shared checkout. Do not stage the entire
working tree as a shortcut.

Commit application assets required by `pubspec.yaml`, the lockfile, the patched
`third_party/flutter_tts` sources, and intentional fixture/evidence files as
needed. Downloaded runtimes, model candidates, map dumps, editor state, build
caches, and creative/reference directories are local material. Ignore rules do
not remove files that were already tracked; review those explicitly when making
a commit. Keep secrets and signing keys outside version control.

Never run historical scripts from `tool/archive/` as setup or maintenance steps.
