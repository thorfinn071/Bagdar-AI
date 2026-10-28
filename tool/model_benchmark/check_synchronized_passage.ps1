[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$syncPassageProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $syncPassageProject
try {
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_SYNC_PASSAGE=true --dart-define=BAGDAR_CHECK_SYNC_PASSAGE=true `
    test/synchronized_passage_experiment_test.dart test/camera_synchronized_rig_test.dart `
    test/camera_scan_age_gate_test.dart test/path_clear_stop_diagnosis_test.dart `
    test/coverage_aware_stop_guidance_test.dart test/generic_geometry_confidence_authority_test.dart `
    test/camera_track_association_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Synchronized passage or preceding safety regressions failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_synchronized_passage.py
  if ($LASTEXITCODE -ne 0) { throw 'Synchronized passage or preceding integrity contract failed' }
} finally {
  Pop-Location
}
