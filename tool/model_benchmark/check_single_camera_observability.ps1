param(
    [string]$Flutter = 'C:\src\flutter\bin\flutter.bat',
    [string]$Dart = 'C:\src\flutter\bin\dart.bat',
    [string]$Python = ''
)

$ErrorActionPreference = 'Stop'
$observabilityRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if (-not $Python) {
    $Python = Join-Path $observabilityRepo 'tools/ncnn/.venv/Scripts/python.exe'
}
$observabilityLogs = Join-Path $observabilityRepo 'scratch/single-camera-observability-2026-10-11'

function Invoke-ObservabilityCheck {
    param([string]$Name, [string]$Binary, [string[]]$Arguments)
    $checkLog = Join-Path $observabilityLogs "$Name.log"
    & $Binary @Arguments *> $checkLog
    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $checkLog -Tail 25
        throw "$Name failed; see $checkLog"
    }
    Write-Output "$Name passed; $checkLog"
}

Push-Location -LiteralPath $observabilityRepo
try {
    foreach ($checkBinary in @($Flutter, $Dart, $Python)) {
        if (-not (Test-Path -LiteralPath $checkBinary -PathType Leaf)) {
            throw "Executable not found: $checkBinary"
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $observabilityLogs 'preregistration.json'))) {
        throw 'Missing frozen experiment inputs; this check does not create or replace preregistration.'
    }
    $observabilitySources = @(
        'lib/safety/perception/single_camera_observability.dart',
        'test/single_camera_observability_test.dart',
        'test/single_camera_observability_experiment_test.dart'
    )
    Invoke-ObservabilityCheck -Name 'targeted-analysis' -Binary $Dart -Arguments (@('analyze') + $observabilitySources)
    Invoke-ObservabilityCheck -Name 'format-check' -Binary $Dart -Arguments (@('format', '--output=none', '--set-exit-if-changed') + $observabilitySources)
    Invoke-ObservabilityCheck -Name 'regression-tests' -Binary $Flutter -Arguments @(
        'test', '--no-pub', '--concurrency=1', '--dart-define=BAGDAR_CHECK_OBSERVABILITY=true',
        'test/single_camera_observability_test.dart',
        'test/single_camera_observability_experiment_test.dart',
        'test/camera_passage_clearance_source_test.dart',
        'test/passage_clearance_test.dart',
        'test/camera_visible_passage_recovery_test.dart'
    )
    Invoke-ObservabilityCheck -Name 'independent-verifier' -Binary $Python -Arguments @(
        'tool/model_benchmark/single_camera_observability.py', 'verify'
    )
    Write-Output 'Known synthetic observability checks passed. False-stop reduction remains unestablished.'
}
finally {
    Pop-Location
}
