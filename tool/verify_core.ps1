# Bagdar Core software verification. Read-only by default.
#
# Developer suite:
#   powershell -File tool/verify_core.ps1
# Strict release-candidate signal (fails on every required missing corpus):
#   powershell -File tool/verify_core.ps1 -Rc
# Optional compilation evidence and explicit report output:
#   powershell -File tool/verify_core.ps1 -Rc -AndroidBuild `
#     -OutputDirectory scratch/verification

param(
  [switch]$Rc,
  [switch]$AndroidBuild,
  [string]$OutputDirectory
)

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepoRoot
$Results = [System.Collections.Generic.List[object]]::new()

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Block,
    [bool]$Required = $true
  )
  Write-Host "=== $Name ==="
  $started = Get-Date
  & $Block
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
  $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
  $passed = $code -eq 0
  $Results.Add([ordered]@{
    name = $Name
    required = $Required
    passed = $passed
    exitCode = $code
    durationMs = $durationMs
  })
  if (-not $passed) {
    Write-Host "FAILED: $Name (exit $code)" -ForegroundColor Red
  }
}

# This repository is intentionally a dirty shared workspace. A whole-tree format
# gate would turn unrelated user work into a false failure, so the aggregate
# verifier relies on analyzer/tests plus the whitespace gate below.
Invoke-Step "static analysis" { flutter analyze --no-pub }
Invoke-Step "Flutter software tests" { flutter test --no-pub --concurrency=1 }
Invoke-Step "strict legacy safety harness" {
  flutter test --no-pub --dart-define=BAGDAR_RC=true `
    test/harness/scenario_harness_test.dart
}
Invoke-Step "procedural spatial corpus reproducibility" {
  dart run tool/build_spatial_corpus.dart --check
}
Invoke-Step "real model-output replay reproducibility" {
  dart run tool/build_model_prediction_replay.dart --check
}
Invoke-Step "metric passage contract reproducibility" {
  dart run tool/model_benchmark/evaluate_passage_clearance_contract.dart `
    --check "docs/_baseline_logs/passage_clearance_contract.json"
}
Invoke-Step "synthetic metric passage shadow replay reproducibility" {
  flutter test --no-pub --concurrency=1 `
    --dart-define=BAGDAR_CHECK_PASSAGE_REPORT=true `
    test/synthetic_passage_shadow_replay_test.dart
}
Invoke-Step "camera-visible corpus and held-out split integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_visible_passage_assets.py"
}
Invoke-Step "camera-visible NCNN and frozen scale reproducibility" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_visible_passage_ncnn.py" --check
}
Invoke-Step "camera-visible shadow passage replay reproducibility" {
  dart run tool/model_benchmark/evaluate_visible_passage.dart --check
}
Invoke-Step "camera recovery independent corpus integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_visible_passage_assets.py" --recovery
}
Invoke-Step "camera recovery NCNN and original frozen calibration" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_passage_recovery_ncnn.py" --check
}
Invoke-Step "camera recovery shadow replay reproducibility" {
  dart run tool/model_benchmark/evaluate_visible_passage.dart --check --recovery
}
Invoke-Step "camera track association independent corpus integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_visible_passage_assets.py" --association
}
Invoke-Step "camera track association development freeze integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/freeze_track_passage_development.py" --check
}
Invoke-Step "camera track association pinned NCNN and frozen calibration" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_track_passage_ncnn.py" --check
}
Invoke-Step "camera track association shadow replay reproducibility" {
  dart run tool/model_benchmark/evaluate_visible_passage.dart --check --association
}
Invoke-Step "camera temporal independent corpus integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_temporal_passage_assets.py"
}
Invoke-Step "camera temporal development freeze integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/freeze_temporal_passage_development.py" --check
}
Invoke-Step "camera temporal pinned NCNN reproducibility" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_temporal_passage_ncnn.py" --check
}
Invoke-Step "camera temporal shadow replay reproducibility" {
  dart run tool/model_benchmark/evaluate_temporal_passage.dart --check
}
Invoke-Step "camera metric motion visible corpus and observation labels" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_metric_motion_assets.py"
  if ($LASTEXITCODE -ne 0) { return }
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/annotate_metric_motion_observability.py" --check
}
Invoke-Step "camera metric motion development freeze integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/freeze_metric_motion_development.py" --check
}
Invoke-Step "camera metric motion pinned NCNN reproducibility" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_metric_motion_ncnn.py" --check
}
Invoke-Step "camera metric motion shadow replay reproducibility" {
  dart run tool/model_benchmark/evaluate_metric_motion.dart --check
}
Invoke-Step "camera scale motion independent visible corpus integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_scale_motion_assets.py"
}
Invoke-Step "camera scale motion development freeze integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/freeze_scale_motion_development.py" --check
}
Invoke-Step "camera scale motion pinned NCNN reproducibility" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_scale_motion_ncnn.py" --check
}
Invoke-Step "camera scale motion shadow replay reproducibility" {
  dart run tool/model_benchmark/evaluate_scale_motion.dart --check
}
Invoke-Step "camera processing age source and regression contract integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_camera_processing_age.py" --check
}
Invoke-Step "camera processing age parity, deadlines and overload shadow replay" {
  dart run tool/model_benchmark/evaluate_camera_processing_age.dart --check
}
Invoke-Step "independent fast motion source and shadow contract integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_fast_camera_motion.py" --check
}
Invoke-Step "independent fast motion AOT parity, worker and shadow reproducibility" {
  dart run tool/model_benchmark/evaluate_fast_camera_motion.dart --check
}
Invoke-Step "concurrent-load motion source and earlier fast contract integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_fast_camera_motion_load.py" --check
}
Invoke-Step "concurrent-load native motion AOT parity, worker and shadow reproducibility" {
  dart run tool/model_benchmark/evaluate_fast_camera_motion_load.dart --check
}
Invoke-Step "packed fast motion earlier contracts and copy correction integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_fast_camera_motion_packed.py" --check
}
Invoke-Step "packed native motion full parity, worker and shadow reproducibility" {
  dart run tool/model_benchmark/evaluate_fast_camera_motion_packed.dart --check
}
Invoke-Step "independent callback stream earlier source contracts integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_fast_camera_motion_stream.py" --check
}
Invoke-Step "independent callback stream control parity and scheduler contracts" {
  dart run tool/model_benchmark/evaluate_fast_camera_motion_stream.dart --check
}
Invoke-Step "strict SIMD motion earlier contracts and native source integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_fast_camera_motion_simd.py" --check
}
Invoke-Step "strict SIMD bitwise scores, full parity and native safety contracts" {
  dart run tool/model_benchmark/evaluate_fast_camera_motion_simd.dart --check
}
Invoke-Step "paired Blender scene corpus, admission negatives and first baseline integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" -m unittest discover `
    -s tool/model_benchmark -p test_paired_scene_corpus.py
  if ($LASTEXITCODE -eq 0) {
    & "tools/ncnn/.venv/Scripts/python.exe" `
      "tool/model_benchmark/verify_paired_scene_baseline.py"
  }
}
Invoke-Step "paired Blender production YOLO control reproducibility" {
  python "tool/model_benchmark/evaluate_paired_scene_models.py" detector --check
}
Invoke-Step "paired Blender production MiDaS NCNN reproducibility" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/evaluate_paired_scene_models.py" depth --check
}
Invoke-Step "paired Blender geometry and shadow runtime report reproducibility" {
  flutter test --no-pub --concurrency=1 `
    --dart-define=BAGDAR_CHECK_PAIRED_REPORT=true `
    --dart-define=BAGDAR_CHECK_CORRECTION_REPORT=true `
    --dart-define=BAGDAR_CORRECTION_REPORT=docs/_baseline_logs/blender_paired_correction_shadow_v3.json `
    test/blender_paired_scene_shadow_replay_test.dart `
    test/blender_paired_scene_correction_replay_test.dart
}
Invoke-Step "paired Blender no hazardous continue, timely stops and no false imminent quality gate" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_paired_scene_correction.py"
}
Invoke-Step "visible body optical packet admission and prior baseline integrity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_visible_body.py"
}
Invoke-Step "visible body single-frame replay and static scan authority reproducibility" {
  flutter test --no-pub --concurrency=1 `
    --dart-define=BAGDAR_CHECK_BODY_REPORT=true `
    test/blender_visible_body_replay_test.dart
}
Invoke-Step "complete optical surface bounds, negative coverage and prior freezes" {
  & "tools/ncnn/.venv/Scripts/python.exe" -m unittest discover `
    -s tool/blender -p "test_pixel_*_envelope.py"
  if ($LASTEXITCODE -ne 0) { return }
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_scan_complete.py"
}
Invoke-Step "static scan coverage and complete envelope replay reproducibility" {
  flutter test --no-pub --concurrency=1 `
    --dart-define=BAGDAR_CHECK_SCAN_COVERAGE=true `
    --dart-define=BAGDAR_CHECK_SCAN_COMPLETE=true `
    test/blender_scan_coverage_replay_test.dart `
    test/blender_scan_complete_replay_test.dart
}
Invoke-Step "scan processing elapsed evidence, NCNN load and prior freezes" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/verify_scan_processing.py"
}
Invoke-Step "synchronized synthetic rig capture, coverage and elapsed receipts" {
  python "tool/model_benchmark/verify_synchronized_rig.py"
}

$spatialArgs = @("run", "tool/report_spatial_metrics.dart", "--summary")
if ($Rc) { $spatialArgs += "--rc" }
Invoke-Step "procedural replay and external manifest integrity" { dart @spatialArgs }

# The canonical manifest pins external corpus hashes, but does not execute
# their frame timelines. Run each Blender replay explicitly in the same mode.
foreach ($externalManifest in @(
  "test/fixtures/spatial_safety/blender-egocentric-v1/replay-manifest.json",
  "test/fixtures/spatial_safety/blender-temporal-v2/replay-manifest.json",
  "test/fixtures/spatial_safety/blender-context-v3/replay-manifest.json"
)) {
  $externalArgs = @(
    "run", "tool/report_spatial_metrics.dart",
    "--manifest", $externalManifest, "--summary"
  )
  if ($Rc) { $externalArgs += "--rc" }
  Invoke-Step "external Blender frame replay: $externalManifest" {
    dart @externalArgs
  }
}

Invoke-Step "Blender oracle-depth shadow runtime replay reproducibility" {
  flutter test --no-pub --dart-define=BAGDAR_CHECK_SHADOW_REPORT=true `
    test/blender_temporal_shadow_replay_test.dart
}
Invoke-Step "context Blender oracle-depth shadow replay reproducibility" {
  flutter test --no-pub --dart-define=BAGDAR_CONTEXT_CORPUS=true `
    --dart-define=BAGDAR_CHECK_SHADOW_REPORT=true `
    test/blender_temporal_shadow_replay_test.dart
}

Invoke-Step "context desktop NCNN depth output reproducibility" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/test_generate_context_ncnn_depth.py"
  if ($LASTEXITCODE -ne 0) { return }
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tool/model_benchmark/generate_context_ncnn_depth.py" --check
}
Invoke-Step "context desktop NCNN depth shadow replay reproducibility" {
  flutter test --no-pub --dart-define=BAGDAR_CONTEXT_CORPUS=true `
    --dart-define=BAGDAR_NCNN_DEPTH=true `
    --dart-define=BAGDAR_CHECK_SHADOW_REPORT=true `
    test/blender_temporal_shadow_replay_test.dart
}
Invoke-Step "context oracle versus NCNN diagnostic reproducibility" {
  python "tool/model_benchmark/compare_context_depth_replay.py" `
    --check "docs/_baseline_logs/blender_context_depth_comparison.json"
}

Invoke-Step "model artifact/hash/decoder contracts" {
  & "model_export/venv/Scripts/python.exe" `
    "model_export/export_candidates.py" --check
}
Invoke-Step "real ONNX candidate predictions" {
  & "model_export/venv/Scripts/python.exe" `
    "tool/model_benchmark/run_predictions.py" `
    --check "test/fixtures/model_predictions/predictions.json"
}
Invoke-Step "ONNX reference vs NCNN parity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tools/ncnn/parity_test.py" `
    --check-fixture "test/fixtures/ncnn_contract/reference_outputs.json"
}
Invoke-Step "working-tree whitespace check" { git diff --check }

if ($AndroidBuild) {
  Invoke-Step "Android debug compilation evidence" {
    flutter build apk --debug
  } $false
} else {
  $Results.Add([ordered]@{
    name = "Android debug compilation evidence"
    required = $false
    passed = $null
    exitCode = $null
    durationMs = 0
    status = "not_requested"
  })
}

$commitSha = (& git rev-parse HEAD).Trim()
$dirty = [bool]((& git status --porcelain).Trim())
$requiredFailures = @($Results | Where-Object {
  $_.required -and $_.passed -eq $false
})
$passed = $requiredFailures.Count -eq 0
$summary = [ordered]@{
  schemaVersion = 2
  tool = "tool/verify_core.ps1"
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  command = [ordered]@{
    rc = [bool]$Rc
    androidBuild = [bool]$AndroidBuild
  }
  source = [ordered]@{
    commitSha = $commitSha
    dirty = $dirty
  }
  evidenceClasses = [ordered]@{
    desktopSoftwareRc = if ($passed) { "pass" } else { "fail" }
    # Artifact/decoder/replay checks prove reproducibility and integration,
    # while scene recall/false-stop evidence remains a separate blocked gate.
    modelCorrectnessRc = "not_established"
    androidBuild = if ($AndroidBuild) { "compilation_evidence_only" } else { "not_run" }
    namedDeviceRuntime = "not_run"
    controlledWalking = "not_run"
  }
  stages = $Results
  passed = $passed
}
$rendered = $summary | ConvertTo-Json -Depth 8
if ($OutputDirectory) {
  $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
  $resolvedOutput = [System.IO.Path]::GetFullPath(
    (Join-Path $RepoRoot $OutputDirectory)
  )
  if (-not $resolvedOutput.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must remain inside the repository."
  }
  New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
  $reportPath = Join-Path $resolvedOutput "core-verification.json"
  Set-Content -LiteralPath $reportPath -Value $rendered -Encoding UTF8
  Write-Host "Wrote $reportPath"
} else {
  Write-Host $rendered
}

if (-not $passed) { exit 1 }
Write-Host "verify_core: pass (Rc=$Rc, AndroidBuild=$AndroidBuild)"
