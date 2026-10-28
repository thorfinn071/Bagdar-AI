[CmdletBinding()]
param([switch]$WriteValidation)
$ErrorActionPreference = 'Stop'
$egoMotionProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $egoMotionProject
try {
  & dart analyze lib/safety/perception/camera_ego_motion.dart `
    lib/safety/perception/separated_motion_risk.dart lib/safety/runtime/ego_motion_shadow_adapter.dart `
    test/camera_ego_motion_test.dart test/ego_motion_shadow_adapter_test.dart `
    test/harness/ego_motion_experiment.dart test/ego_motion_experiment_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Ego-motion analysis failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/infer_ego_motion.py --check
  if ($LASTEXITCODE -ne 0) { throw 'Pinned inference drift' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_EGO=true --dart-define=BAGDAR_CHECK_EGO=true `
    test/camera_ego_motion_test.dart test/ego_motion_shadow_adapter_test.dart test/ego_motion_experiment_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Ego-motion contracts or deterministic replay failed' }
  & tool/model_benchmark/check_whole_track_evidence.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Frozen upstream suite failed' }
  if ($WriteValidation) {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_ego_motion.py --write
  } else {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_ego_motion.py
  }
  if ($LASTEXITCODE -ne 0) { throw 'Ego-motion identity or arithmetic checks failed' }
} finally {
  Pop-Location
}
