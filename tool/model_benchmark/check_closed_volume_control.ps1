[CmdletBinding()]
param([switch]$WriteValidation)
$ErrorActionPreference = 'Stop'
$controlProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $controlProject
try {
  & dart analyze test/harness/closed_volume_control_fixture.dart test/harness/closed_volume_control_replay.dart `
    test/harness/closed_volume_control_faults.dart test/closed_volume_control_test.dart test/closed_volume_control_source_audit_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Closed-volume control analysis failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' -m unittest discover -s tool/model_benchmark -p test_volume_holdout_scoring.py
  if ($LASTEXITCODE -ne 0) { throw 'Independent geometry scoring failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_CLOSED_AUDIT=true --dart-define=BAGDAR_CHECK_CLOSED_AUDIT=true test/closed_volume_control_source_audit_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Closed producer precondition reproducibility failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/closed_volume_control.py infer --check
  if ($LASTEXITCODE -ne 0) { throw 'Closed control byte-exact inference failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_CLOSED_CONTROL=true --dart-define=BAGDAR_CHECK_CLOSED=true test/closed_volume_control_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Closed runtime/fault replay reproducibility failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_HOLDOUT_AUDIT=true --dart-define=BAGDAR_CHECK_HOLDOUT_AUDIT=true test/volume_holdout_source_audit_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Original unavailable control changed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/audit_volume_holdout_visibility.py > $null
  if ($LASTEXITCODE -ne 0) { throw 'Original missing first-return witness changed' }
  & tool/model_benchmark/check_volume_authority.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Frozen upstream regression failed' }
  if ($WriteValidation) {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/closed_volume_control.py verify --write
  } else {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/closed_volume_control.py verify
  }
  if ($LASTEXITCODE -ne 0) { throw 'Closed control integrity/scoring failed' }
  $controlGate = Get-Content -Raw scratch/closed-volume-control-2026-10-11/replay.json | ConvertFrom-Json
  if (-not $controlGate.syntheticControlGatePassed) {
    throw 'Predeclared behavioral control gate failed; immutable result retained'
  }
} finally {
  Pop-Location
}
