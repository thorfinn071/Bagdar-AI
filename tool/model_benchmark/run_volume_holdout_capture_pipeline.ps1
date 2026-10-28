[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$holdoutProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $holdoutProject
try {
  $holdoutWaitLimit = (Get-Date).AddMinutes(40)
  while (-not (Test-Path -LiteralPath scratch/volume-holdout-2026-10-10/optical/manifest.json)) {
    if ((Get-Date) -gt $holdoutWaitLimit) { throw 'Timed out waiting for complete capture export' }
    Start-Sleep -Seconds 10
  }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/infer_volume_holdout.py
  if ($LASTEXITCODE -ne 0) { throw 'Initial pinned inference failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/infer_volume_holdout.py --check
  if ($LASTEXITCODE -ne 0) { throw 'Independent byte-exact inference rerun failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_VOLUME_HOLDOUT=true --dart-define=BAGDAR_WRITE_HOLDOUT=true test/volume_holdout_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Initial immutable holdout replay failed' }
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_VOLUME_HOLDOUT=true --dart-define=BAGDAR_CHECK_HOLDOUT=true test/volume_holdout_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Independent replay rerun failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/render_volume_holdout.py
  if ($LASTEXITCODE -ne 0) { throw 'Independent post-decision scoring failed' }
  Write-Output 'Holdout inference, replay rerun and post-decision artifacts complete; inspect predeclared gate before validation seal'
} finally {
  Pop-Location
}
