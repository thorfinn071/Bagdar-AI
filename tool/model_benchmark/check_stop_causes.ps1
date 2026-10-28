[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputDirectory)

$ErrorActionPreference = 'Stop'
$stopCauseRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stopCauseOutput = [System.IO.Path]::GetFullPath(
  $(if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory }
    else { Join-Path $stopCauseRoot $OutputDirectory })
)
if (Test-Path -LiteralPath $stopCauseOutput) {
  throw "Use a new output directory; preserve prior reports: $stopCauseOutput"
}
New-Item -ItemType Directory -Path $stopCauseOutput | Out-Null

Push-Location -LiteralPath $stopCauseRoot
try {
  $stopCauseAnalysis = @(
    'analyze', '--no-pub',
    'tool/model_benchmark/stop_cause_diagnostics.dart',
    'test/harness/stop_cause_replay.dart',
    'test/stop_cause_diagnostics_test.dart',
    'test/stop_cause_replay_test.dart'
  )
  & flutter @stopCauseAnalysis *> (Join-Path $stopCauseOutput 'analyze.log')
  if ($LASTEXITCODE -ne 0) { throw "Analysis failed; see $stopCauseOutput/analyze.log" }

  # Shared Flutter workspace: run serially, never alongside another Flutter run.
  $stopCauseTests = @(
    'test', '--no-pub', '--concurrency=1', '--reporter=expanded',
    '--dart-define=BAGDAR_STOP_CAUSES_REPLAY=true',
    "--dart-define=BAGDAR_STOP_CAUSES_OUTPUT=$stopCauseOutput",
    'test/stop_cause_diagnostics_test.dart',
    'test/stop_cause_replay_test.dart',
    'test/spatial_runtime_admission_regression_test.dart',
    'test/coverage_aware_stop_guidance_test.dart',
    'test/volume_authority_runtime_test.dart',
    'test/volume_authority_history_test.dart'
  )
  & flutter @stopCauseTests *> (Join-Path $stopCauseOutput 'tests.log')
  $stopCauseTestExit = $LASTEXITCODE
  $stopCauseVerified = $stopCauseTestExit -eq 0
  [ordered]@{
    schemaVersion = 1
    softwareChecksPassed = $stopCauseVerified
    flutterTestExitCode = $stopCauseTestExit
    command = 'tool/model_benchmark/check_stop_causes.ps1'
    fullCoreAggregate = 'not_run'
    namedDeviceRuntime = 'not_run'
    controlledWalking = 'not_run'
    promotionAllowed = $false
  } | ConvertTo-Json | Set-Content -LiteralPath (
    Join-Path $stopCauseOutput 'verification.json'
  ) -Encoding utf8
  if (-not $stopCauseVerified) { throw "Tests failed; see $stopCauseOutput/tests.log" }
  Write-Output "STOP diagnosis verified: $stopCauseOutput/report.md"
} finally {
  Pop-Location
}
