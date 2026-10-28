# Bagdar simulation lab

The lab feeds rendered YUV420 and synthetic inertial samples into the existing
`AiCameraScreen`. Android runs the packaged YOLO TFLite model, NCNN worker,
quality checks, scheduler, depth controller, trackers and shadow spatial runtime.
The inspection screen is the application's existing screen, with a simulation banner.

The simulator uses a separate debug application ID, `com.example.bagdar.simulation`.
Normal `lib/main.dart`/Core launches continue to open the real camera. Simulation
requires `BAGDAR_SIMULATION=true` and a debug/profile build. Its manifest removes
SMS/call/location permissions, and emergency dispatch is explicitly blocked in code.

## Existing generated bundles

See `output/simulation-lab/`. `render-v1` is a short development smoke bundle:
72 clips, 504 frames, 192x288, 10 fps. `render-v2` uses the declared full profile:
72 clips, 2232 frames, 320x480, 15 fps, two seconds per clip, with optional local
City FBX background assets. Check the evaluation report for what actually ran;
rendered frames and loaded models alone do not establish successful inference.

## Launch on this laptop

From the workspace root, with PowerShell and an Android SDK installed:

```powershell
./tool/simulation/lab.ps1 -Action run -Corpus output/simulation-lab/render-v2 -StartEmulator
```

The launcher offers every generated clip. Select a clip to open the same
inspection screen that the normal app uses. The helper starts the task's
`Bagdar_Simulation` AVD if requested: interactive runs show its window, while
`-Sequence all` starts it headlessly. Android Studio can also launch that AVD
in its Device Manager. Create an AVD with that name first on another
machine. Flutter, Android SDK/JDK/NDK and the existing NCNN Android libraries are
required. No physical phone is used by these commands.

The helper selects the existing native NCNN **CPU** backend using
`BAGDAR_SIMULATION_CPU=true`; YOLO also uses CPU. This avoids emulator software
Vulkan shader compilation. The production default backend selection is unchanged.
The exact backend/tier and model file hashes are recorded in each receipt.

Run the entire corpus and collect/evaluate application receipts:

```powershell
./tool/simulation/lab.ps1 -Action run -Corpus output/simulation-lab/render-v2 -Sequence all -StartEmulator -WaitForBatch
./tool/simulation/lab.ps1 -Action collect -Corpus output/simulation-lab/render-v2
./tool/simulation/lab.ps1 -Action evaluate -Corpus output/simulation-lab/render-v2
```

Use `-Sequence hallway-blocked-rain` for a selected clip. `-NoBuild` reuses the
last built simulation APK. Runtime input files are copied into the debuggable
app's private storage using ADB `run-as`; shared-storage access is unnecessary.
Model/manifest hashes and a unique run ID bind results to inputs. Old receipts
from another run are reported as not run for the current run.
After a successful full upload, later launches transfer only the small control
file when the cached manifest identity matches. Every selected clip still checks
its actual pixel/preview hashes before playback. A changed corpus invalidates
the upload cache.

Before a long run, exercise two selected clips in the automatic runner:

```powershell
./tool/simulation/lab.ps1 -Action run -Sequence all -Sequences hallway-clear-lowlight,courtyard-blocked-rain -StartEmulator -WaitForBatch
```

By default an automatic batch cold-starts the same APK once per independent
episode. Within a clip the real scheduler and all temporal state run continuously;
the controller waits for a matching app receipt before stopping that process.
This avoids depending on Flutter disposal when an emulator pauses rendering or
shows an ANR dialog. Each episode has a 90-second receipt deadline. Timeouts,
observed ANR dialogs and app logs are recorded separately; no app receipt is
fabricated for a timeout. `app-reports/process-batch-progress.json` gives progress.

`-InAppBatch` exercises the optional navigation-based runner. It uses transitions
of zero duration, a 90-second episode deadline and a 10-second disposal deadline;
`batch-progress.json` and terminal failures are stored inside the app. This path
can still fail on an emulator whose Android UI is not responding. Interactive
scene selection retains normal Material transitions. Builds run before emulator
startup and use a bounded, short-lived Gradle JVM.

## Create a new corpus

Choose a new output directory: generators do not overwrite an existing corpus.

```powershell
./tool/simulation/lab.ps1 -Action render -Corpus output/simulation-lab/my-corpus
./tool/simulation/lab.ps1 -Action package -Corpus output/simulation-lab/my-corpus
```

`-Smoke` renders seven smaller frames per clip. Change `lab_spec.json` for a new
versioned experiment. The Blender CLI also supports `--layouts`, `--conditions`,
`--frames`, `--severity .25..3` and `--urban-assets City`. These are comma-separated
layout/condition selections. `City` is optional local background geometry; its
FBX sources, scale transforms and content hashes are recorded in the render manifest.

Layouts are hallway, courtyard, shop entrance, sidewalk/drop, underpass/headroom
and approaching pedestrian. Every layout has a geometrically passable control
and an obstructed counterpart. Conditions are clean, walking shake, low light,
defocus, rain/lens droplets/wet materials and combined degradation.

## Evidence and input boundaries

- `runtime/manifest.json`, I420 planes, RGB previews and ideal kinematic IMU samples
  are the app inputs. Evaluator-only labels, sparse first-return geometry witnesses
  and exact scene geometry remain outside that directory and outside inference.
- Camera motion and inertial samples come from the same pose function. This is an
  idealized sensor model: measured camera calibration, stabilization, bias, drift
  and a phone's image-processing pipeline have not been reproduced.
- Shake includes true 3-D camera motion and an approximate exposure smear. Lens
  defocus, rain streaks/droplets and shot/read noise are deterministic approximations.
  Wet materials and low-light illumination are rendered in Blender. These procedural
  scenes are not claimed to be a photorealistic or representative real-world corpus.
- Files, sizes, identities, increasing capture/delivery times, hashes and inertial
  samples are checked. Pixels are preloaded and privately copied before delivery.
  Rendering cost does not slow the replay clock. The real scheduler can skip work.
- Capture times retain delays, including time spent paused. Dropped frames are
  logged and never inferred; replay does not automatically loop or reset history.
  A new clip is a new independent camera/application episode.
- Reports distinguish model calls, rejected/accepted data, quality skips, spatial
  decisions, stops on passable controls and hazardous continues. A protective STOP
  caused by missing evidence is not successful recognition. Zero hazardous continues
  with little/no inference is not a perception-quality pass.
- MiDaS remains relative depth. Ideal Blender depth is never substituted for it.
  Physical camera/device/audio/accessibility validation and controlled walking remain
  separate. Generic geometry stays shadow; `promotionAllowed=false`.

## Independent quality-gate diagnosis

`quality_protocol_v1.json` freezes a separate experiment: disjoint chart families
and seeds for development/holdout, paired blur/noise transforms, two dimensions,
two contrasts and sampling-phase/flat-field controls. These are diagnostic 2-D
charts, not realistic Blender scenes or hazard ground truth. The benchmark calls
the unchanged production `BlurDetector`; no replacement threshold is fitted.

```powershell
python tool/simulation/build_quality_corpus.py output/simulation-lab/my-quality-run
dart run tool/simulation/quality_benchmark.dart output/simulation-lab/my-quality-run
python tool/simulation/summarize_quality.py output/simulation-lab/my-quality-run --report output/simulation-lab/my-quality-run/report.md
```

Use a new directory; the generator and scorer preserve existing inputs/baselines.
The executed `quality-gate-v1` corpus contains 968 images. Its initial baseline
and scorer are preserved alongside a rerun after import/style cleanup; all 968
image results matched exactly. The original APK probe references that initial
baseline's SHA-256. See `docs/image-quality-evaluation-2026-10-27.md`.

Paired inputs can also be traced through the existing APK:

```powershell
python tool/simulation/quality_app_probe.py package output/simulation-lab/my-quality-run output/simulation-lab/my-quality-probe
./tool/simulation/lab.ps1 -Action run -Corpus output/simulation-lab/my-quality-probe -Sequence all -StartEmulator -NoBuild
python tool/simulation/quality_app_probe.py evaluate output/simulation-lab/my-quality-probe output/simulation-lab/my-quality-probe/report.md
```

This probe repeats fixed diagnostic luma, including fixed noise, 31 times per
clip. It checks frame admission and actual model calls, with no claim about
real camera dynamics or obstacle recognition. Use its dedicated evaluator;
the Blender hazard/passable evaluator does not apply to these charts. Runtime
inputs contain neither expected blur outcomes nor evaluator-only labels.

## Frozen research quality observer

The pixel-only `lib/research/image_quality_observer.dart` returns diagnostic
states with explicit uncertainty. It is used by the offline benchmark and does
not replace the production filter. Freeze a new candidate/protocol before
generating a new corpus; do not revise a candidate on an evaluated holdout.

```powershell
python tool/simulation/build_observer_corpus.py output/simulation-lab/new-observer-experiment
dart run tool/simulation/quality_observer_benchmark.dart output/simulation-lab/new-observer-experiment
python tool/simulation/summarize_observer.py output/simulation-lab/new-observer-experiment output/simulation-lab/new-observer-experiment/report.md
```

`quality-observer-v1` has 1,032 images. V1 responds to white/shot noise but fails
on correlated noise: all 32 blurred correlated-noise holdout images were called
structured. It is unsuitable for production replacement. Structured is never
permission to process a frame or move. Preserve that result when designing v2;
use new disjoint holdout families/seeds for any changed candidate.

## Continuity and actual emulator lifecycle

The 30-second stress bundles repeat existing two-second renders. Original
within-episode clocks keep advancing through actual Android Home/resume.
Model state is preserved inside an episode; the app navigates between episodes
in one process. Receipts record delivery age, callback concurrency, sampled
scheduler occupancy, RSS and separate route-disposal evidence. Callback counts
do not measure the native inference queue. An ANR/timeout is a failed probe.

```powershell
python tool/simulation/continuity_probe.py package output/simulation-lab/render-v2 output/simulation-lab/new-continuity-experiment
./tool/simulation/lab.ps1 -Action build
# Start Bagdar_Simulation and install the new APK first, then:
python tool/simulation/continuity_probe.py run output/simulation-lab/new-continuity-experiment --adb "$env:LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
```

The controller targets an emulator only, preserves previous experiment folders,
and binds its own run ID to app progress, receipts and the input manifest.
It records ADB read timeouts and retries on later polls within the same deadline.
`continuity_probe.py recover CORPUS --adb ADB` can save matching completed native
receipts after a controller transport failure; recovery preserves the original
failed controller status. The final successful run is `continuity-v1-run6`:
902 frames, actual background/resume, two route/host disposal acknowledgements,
no framework errors, read timeouts or observed ANRs in that run. The cleanup
failure was an uninitialized deferred acoustic service, now covered by regression
tests; interactive navigation retains its normal pop behavior.
Verify source/build/installed APK identity with `verify_build.py` before a run.
Use `docs/stationary-device-acceptance-checklist-2026-10-27.md` for the separate
physical-device session; none of those checks is completed by this lab.

## Versioned procedural breadth

`generate_scenes.py --spec tool/simulation/lab_breadth_v1.json` selects a versioned
camera, geometry and material configuration. It records original and effective
specification hashes, including CLI overrides, plus validator and generator
hashes. The default specification remains supported. The breadth smoke has
eight courtyard/shop clear/blocked clean/rain clips, 56 frames, a different
camera/lens/height, wider cross-track geometry and different material controls.
This is procedural variation with ideal IMU, not measured sensor calibration.

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --python-exit-code 1 --python tool/simulation/generate_scenes.py -- --spec tool/simulation/lab_breadth_v1.json --output output/simulation-lab/new-breadth-experiment
python tool/simulation/package_replay.py output/simulation-lab/new-breadth-experiment
```

## Software checks

```powershell
python -m unittest discover -s tool/simulation -p "test_*.py" -v
flutter test --no-pub test/simulation_bundle_test.dart
flutter test --no-pub --dart-define=BAGDAR_SIMULATION=true test/simulation_bundle_test.dart test/simulation_sos_block_test.dart
```
