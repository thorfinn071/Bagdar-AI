[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [Parameter(Mandatory = $true)][string]$BaselineReceipt,
  [string]$PythonExecutable = 'python'
)

$ErrorActionPreference = 'Stop'
$logicAuditRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logicAuditOutput = [IO.Path]::GetFullPath(
  $(if ([IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory }
    else { Join-Path $logicAuditRoot $OutputDirectory })
)
$logicAuditBaseline = [IO.Path]::GetFullPath(
  $(if ([IO.Path]::IsPathRooted($BaselineReceipt)) { $BaselineReceipt }
    else { Join-Path $logicAuditRoot $BaselineReceipt })
)
if (Test-Path -LiteralPath $logicAuditOutput) { throw 'Use a new output directory' }
if (-not (Test-Path -LiteralPath $logicAuditBaseline -PathType Leaf)) { throw 'Baseline receipt missing' }
New-Item -ItemType Directory -Path $logicAuditOutput | Out-Null
Push-Location -LiteralPath $logicAuditRoot
try {
  & flutter analyze --no-pub test/stop_logic_audit_test.dart *> "$logicAuditOutput/analyze.log"
  if ($LASTEXITCODE -ne 0) { throw 'Audit analysis failed; see analyze.log' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_STOP_LOGIC_REPLAY=true `
    "--dart-define=BAGDAR_STOP_LOGIC_OUTPUT=$logicAuditOutput" `
    "--dart-define=BAGDAR_STOP_LOGIC_BASELINE=$logicAuditBaseline" `
    test/stop_logic_audit_test.dart *> "$logicAuditOutput/tests.log"
  if ($LASTEXITCODE -ne 0) { throw 'Audit tests failed; see tests.log' }
  & $PythonExecutable tool/model_benchmark/verify_stop_logic_audit.py `
    --audit "$logicAuditOutput/audit.json" --baseline $logicAuditBaseline `
    *> "$logicAuditOutput/independent-audit.log"
  if ($LASTEXITCODE -ne 0) { throw 'Independent receipt audit failed; see independent-audit.log' }
  Write-Output "STOP logic audit complete: $logicAuditOutput/report.md"
} finally {
  Pop-Location
}
