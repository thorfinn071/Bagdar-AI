[CmdletBinding()]
param([switch]$WriteValidation)
$ErrorActionPreference = 'Stop'
$volumeAuthorityProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $volumeAuthorityProject
try {
  & dart analyze lib/safety/runtime/volume_authority_spatial_runtime.dart `
    test/volume_authority_runtime_test.dart test/volume_authority_history_test.dart `
    test/harness/volume_authority_regression.dart test/volume_authority_regression_test.dart `
    test/harness/ego_volume_fixture.dart test/harness/ego_volume_repair.dart test/ego_volume_repair_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Volume authority analysis failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_VOLUME_FIX=true --dart-define=BAGDAR_CHECK_VOLUME_FIX=true `
    test/volume_authority_runtime_test.dart test/volume_authority_history_test.dart `
    test/volume_authority_regression_test.dart test/ego_volume_repair_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Volume authority contracts or replay failed' }
  & tool/model_benchmark/check_ego_motion.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Frozen upstream suite failed' }
  if ($WriteValidation) {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_volume_authority.py --write
  } else {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_volume_authority.py
  }
  if ($LASTEXITCODE -ne 0) { throw 'Volume authority identity/arithmetic checks failed' }
} finally {
  Pop-Location
}
