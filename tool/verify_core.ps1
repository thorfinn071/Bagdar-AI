# Bagdar Core software verification. Read-only by default.
#
# Developer suite:
#   powershell -File tool/verify_core.ps1
# Strict release-candidate signal (fails on every required missing corpus):
#   powershell -File tool/verify_core.ps1 -Rc
# Optional compilation evidence and explicit report output:
#   powershell -File tool/verify_core.ps1 -Rc -AndroidBuild `
#     -OutputDirectory scratch/verification

param(
  [switch]$Rc,
  [switch]$AndroidBuild,
  [string]$OutputDirectory
)

$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepoRoot
$Results = [System.Collections.Generic.List[object]]::new()

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Block,
    [bool]$Required = $true
  )
  Write-Host "=== $Name ==="
  $started = Get-Date
  & $Block
  $code = $LASTEXITCODE
  if ($null -eq $code) { $code = 0 }
  $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
  $passed = $code -eq 0
  $Results.Add([ordered]@{
    name = $Name
    required = $Required
    passed = $passed
    exitCode = $code
    durationMs = $durationMs
  })
  if (-not $passed) {
    Write-Host "FAILED: $Name (exit $code)" -ForegroundColor Red
  }
}

# This repository is intentionally a dirty shared workspace. A whole-tree format
# gate would turn unrelated user work into a false failure, so the aggregate
# verifier relies on analyzer/tests plus the whitespace gate below.
Invoke-Step "static analysis" { flutter analyze --no-pub }
Invoke-Step "Flutter software tests" { flutter test --no-pub }
Invoke-Step "strict legacy safety harness" {
  flutter test --no-pub --dart-define=BAGDAR_RC=true `
    test/harness/scenario_harness_test.dart
}
Invoke-Step "procedural spatial corpus reproducibility" {
  dart run tool/build_spatial_corpus.dart --check
}
Invoke-Step "real model-output replay reproducibility" {
  dart run tool/build_model_prediction_replay.dart --check
}

$spatialArgs = @("run", "tool/report_spatial_metrics.dart", "--summary")
if ($Rc) { $spatialArgs += "--rc" }
Invoke-Step "spatial replay policy gate" { dart @spatialArgs }

Invoke-Step "model artifact/hash/decoder contracts" {
  & "model_export/venv/Scripts/python.exe" `
    "model_export/export_candidates.py" --check
}
Invoke-Step "real ONNX candidate predictions" {
  & "model_export/venv/Scripts/python.exe" `
    "tool/model_benchmark/run_predictions.py" `
    --check "test/fixtures/model_predictions/predictions.json"
}
Invoke-Step "ONNX reference vs NCNN parity" {
  & "tools/ncnn/.venv/Scripts/python.exe" `
    "tools/ncnn/parity_test.py" `
    --check-fixture "test/fixtures/ncnn_contract/reference_outputs.json"
}
Invoke-Step "working-tree whitespace check" { git diff --check }

if ($AndroidBuild) {
  Invoke-Step "Android debug compilation evidence" {
    flutter build apk --debug
  } $false
} else {
  $Results.Add([ordered]@{
    name = "Android debug compilation evidence"
    required = $false
    passed = $null
    exitCode = $null
    durationMs = 0
    status = "not_requested"
  })
}

$commitSha = (& git rev-parse HEAD).Trim()
$dirty = [bool]((& git status --porcelain).Trim())
$requiredFailures = @($Results | Where-Object {
  $_.required -and $_.passed -eq $false
})
$passed = $requiredFailures.Count -eq 0
$summary = [ordered]@{
  schemaVersion = 2
  tool = "tool/verify_core.ps1"
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  command = [ordered]@{
    rc = [bool]$Rc
    androidBuild = [bool]$AndroidBuild
  }
  source = [ordered]@{
    commitSha = $commitSha
    dirty = $dirty
  }
  evidenceClasses = [ordered]@{
    desktopSoftwareRc = if ($passed) { "pass" } else { "fail" }
    modelCorrectnessRc = if ($passed) { "pass" } else { "fail" }
    androidBuild = if ($AndroidBuild) { "compilation_evidence_only" } else { "not_run" }
    namedDeviceRuntime = "not_run"
    controlledWalking = "not_run"
  }
  stages = $Results
  passed = $passed
}
$rendered = $summary | ConvertTo-Json -Depth 8
if ($OutputDirectory) {
  $resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
  $resolvedOutput = [System.IO.Path]::GetFullPath(
    (Join-Path $RepoRoot $OutputDirectory)
  )
  if (-not $resolvedOutput.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputDirectory must remain inside the repository."
  }
  New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
  $reportPath = Join-Path $resolvedOutput "core-verification.json"
  Set-Content -LiteralPath $reportPath -Value $rendered -Encoding UTF8
  Write-Host "Wrote $reportPath"
} else {
  Write-Host $rendered
}

if (-not $passed) { exit 1 }
Write-Host "verify_core: pass (Rc=$Rc, AndroidBuild=$AndroidBuild)"
