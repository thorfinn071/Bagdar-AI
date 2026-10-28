[CmdletBinding()]
param([switch]$WriteValidation)
$ErrorActionPreference = 'Stop'
$holdoutProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $holdoutProject
try {
  & dart analyze test/harness/volume_holdout_fixture.dart test/harness/volume_holdout_replay.dart `
    test/harness/volume_holdout_faults.dart test/volume_holdout_test.dart test/volume_holdout_source_audit_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Holdout analysis failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' -m unittest discover -s tool/model_benchmark -p test_volume_holdout_scoring.py
  if ($LASTEXITCODE -ne 0) { throw 'Independent geometry scoring failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/infer_volume_holdout.py --check
  if ($LASTEXITCODE -ne 0) { throw 'Holdout byte-exact inference failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_VOLUME_HOLDOUT=true --dart-define=BAGDAR_CHECK_HOLDOUT=true test/volume_holdout_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Holdout replay reproducibility failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_HOLDOUT_AUDIT=true --dart-define=BAGDAR_CHECK_HOLDOUT_AUDIT=true test/volume_holdout_source_audit_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Read-only source diagnosis reproducibility failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/audit_volume_holdout_visibility.py
  if ($LASTEXITCODE -ne 0) { throw 'Independent visibility witness failed' }
  & tool/model_benchmark/check_volume_authority.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Frozen 226 Flutter/7 Python upstream verification failed' }
  if ($WriteValidation) {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_volume_holdout.py --write
  } else {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_volume_holdout.py
  }
  if ($LASTEXITCODE -ne 0) { throw 'Holdout source/payload/arithmetic verification failed' }
  $holdoutGate = Get-Content -Raw scratch/volume-holdout-2026-10-10/replay.json | ConvertFrom-Json
  if (-not $holdoutGate.syntheticHoldoutGatePassed) {
    throw 'Predeclared behavioural holdout gate failed; frozen result retained; promotion disabled'
  }
} finally {
  Pop-Location
}
