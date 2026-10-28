[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$diagnosisRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$diagnosisReport = Join-Path $diagnosisRoot 'scratch/path-clear-diagnosis-2026-10-07/replay.json'
$diagnosisDefine = if (Test-Path -LiteralPath $diagnosisReport) {
  '--dart-define=BAGDAR_CHECK_STOP_DIAGNOSIS=true'
} else {
  '--dart-define=BAGDAR_WRITE_STOP_DIAGNOSIS=true'
}
$diagnosisTestArguments = @(
  'test', '--no-pub', '--concurrency=1', '--reporter=expanded',
  $diagnosisDefine,
  'test/coverage_aware_stop_guidance_test.dart',
  'test/path_clear_stop_diagnosis_test.dart',
  'test/generic_geometry_confidence_authority_test.dart'
)

Push-Location -LiteralPath $diagnosisRoot
try {
  & flutter @diagnosisTestArguments
  if ($LASTEXITCODE -ne 0) { throw 'Path-clear regression tests failed' }
  & python 'tool/model_benchmark/verify_path_clear_stop_diagnosis.py'
  if ($LASTEXITCODE -ne 0) { throw 'Path-clear source/output integrity failed' }
} finally {
  Pop-Location
}
