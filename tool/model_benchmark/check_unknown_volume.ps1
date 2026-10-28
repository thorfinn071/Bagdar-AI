[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [string]$PythonExecutable = 'tools/ncnn/.venv/Scripts/python.exe'
)

$ErrorActionPreference = 'Stop'
$volumeRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$volumeOutput = [System.IO.Path]::GetFullPath(
  $(if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory }
    else { Join-Path $volumeRoot $OutputDirectory })
)
if (Test-Path -LiteralPath $volumeOutput) {
  throw "Preserve previous unknown-volume artifacts; choose a new directory: $volumeOutput"
}
New-Item -ItemType Directory -Path $volumeOutput | Out-Null
Push-Location -LiteralPath $volumeRoot
try {
  # NumPy and matplotlib are supplied by the existing NCNN research environment.
  & $PythonExecutable -c 'import numpy, matplotlib' *> (Join-Path $volumeOutput 'python-environment.log')
  if ($LASTEXITCODE -ne 0) { throw 'Python requires NumPy and matplotlib; select the research environment with -PythonExecutable' }
  $volumeAnalysis = @(
    'analyze', '--no-pub',
    'test/harness/unknown_volume_diagnostics.dart',
    'test/unknown_volume_diagnostics_test.dart',
    'test/unknown_volume_replay_test.dart'
  )
  & flutter @volumeAnalysis *> (Join-Path $volumeOutput 'analyze.log')
  if ($LASTEXITCODE -ne 0) { throw "Analysis failed; see $volumeOutput/analyze.log" }
  $volumeTests = @(
    'test', '--no-pub', '--concurrency=1', '--reporter=expanded',
    '--dart-define=BAGDAR_UNKNOWN_VOLUME_REPLAY=true',
    "--dart-define=BAGDAR_UNKNOWN_VOLUME_OUTPUT=$volumeOutput",
    'test/unknown_volume_diagnostics_test.dart',
    'test/unknown_volume_replay_test.dart',
    'test/camera_passage_clearance_source_test.dart',
    'test/single_camera_observability_test.dart',
    'test/coverage_aware_stop_guidance_test.dart',
    'test/spatial_runtime_admission_regression_test.dart'
  )
  & flutter @volumeTests *> (Join-Path $volumeOutput 'tests.log')
  if ($LASTEXITCODE -ne 0) { throw "Tests failed; see $volumeOutput/tests.log" }
  & $PythonExecutable 'tool/model_benchmark/verify_unknown_volume.py' `
    '--directory' $volumeOutput '--render' *> (Join-Path $volumeOutput 'independent-audit.log')
  if ($LASTEXITCODE -ne 0) { throw "Independent audit failed; see $volumeOutput/independent-audit.log" }
  [ordered]@{
    schemaVersion = 1
    softwareChecksPassed = $true
    fullCoreAggregate = 'not_run'
    namedDeviceRuntime = 'not_run'
    controlledWalking = 'not_run'
    promotionAllowed = $false
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $volumeOutput 'verification.json') -Encoding utf8
  Write-Output "Unknown-volume diagnostic verified: $volumeOutput/report.md"
} finally {
  Pop-Location
}
