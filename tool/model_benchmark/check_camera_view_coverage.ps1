[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$viewProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$viewDirectory = 'scratch/camera-view-coverage-2026-10-09'
Push-Location -LiteralPath $viewProjectRoot
try {
  if (-not (Test-Path -LiteralPath "$viewDirectory/validation.json")) {
    throw 'Trial receipt is missing. Generate the declared experiment before checking it.'
  }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_VIEW_EXPERIMENT=true --dart-define=BAGDAR_CHECK_VIEW_REPORT=true `
    test/camera_view_coverage_experiment_test.dart `
    test/path_clear_stop_diagnosis_test.dart `
    test/coverage_aware_stop_guidance_test.dart `
    test/generic_geometry_confidence_authority_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Viewpoint or prior safety regressions failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_camera_view_coverage.py
  if ($LASTEXITCODE -ne 0) { throw 'Viewpoint or prior source/output integrity failed' }
} finally {
  Pop-Location
}
