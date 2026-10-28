[CmdletBinding()]
param([switch]$WriteValidation)
$ErrorActionPreference = 'Stop'
$wholeTrackProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $wholeTrackProject
try {
  & dart analyze lib/safety/perception/camera_track_motion_coverage.dart `
    test/camera_track_motion_coverage_test.dart test/harness/whole_track_evidence_experiment.dart `
    test/whole_track_evidence_experiment_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Whole support analysis failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_WHOLE_TRACK=true --dart-define=BAGDAR_CHECK_WHOLE_TRACK=true `
    test/camera_track_motion_coverage_test.dart test/whole_track_evidence_experiment_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Whole support contracts/replay failed' }
  & tool/model_benchmark/check_motion_origin.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Frozen upstream safety suite failed' }
  if ($WriteValidation) {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_whole_track_evidence.py --write
  } else {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_whole_track_evidence.py
  }
  if ($LASTEXITCODE -ne 0) { throw 'Whole support integrity failed' }
} finally {
  Pop-Location
}
