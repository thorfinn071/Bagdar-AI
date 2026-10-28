param(
    [string]$Python = 'python',
    [string]$OutputDirectory = 'output/voice-wake-cnn'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Push-Location $repo
try {
    $output = [System.IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    function Invoke-Step([string]$Name, [string[]]$Arguments) {
        & $Python @Arguments *> (Join-Path $output ($Name + '.log'))
        if ($LASTEXITCODE -ne 0) { throw "$Name failed; see its log in $output" }
        Write-Output "$Name completed"
    }
    Invoke-Step 'download' @('tool/voice_wake/neural/download.py', '--output', (Join-Path $output 'data'))
    & (Join-Path $PSScriptRoot 'generate_sapi_test.ps1') -OutputDirectory (Join-Path $output 'corpus')
    Invoke-Step 'corpus' @('tool/voice_wake/neural/corpus.py', '--data', (Join-Path $output 'data'), '--output', (Join-Path $output 'corpus'))
    $manifest = Join-Path $output 'corpus/manifest.json'
    $candidate = Join-Path $output 'candidate'
    if (-not (Test-Path -LiteralPath (Join-Path $candidate 'frozen-policy.json'))) {
        $arguments = @('tool/voice_wake/neural/train.py', '--manifest', $manifest, '--output', $candidate)
        if (Test-Path -LiteralPath (Join-Path $candidate 'classifier.keras')) { $arguments += '--resume-export' }
        Invoke-Step 'training' $arguments
    }
    Invoke-Step 'holdout' @('tool/voice_wake/neural/evaluate.py', '--manifest', $manifest, '--candidate', $candidate, '--output', (Join-Path $output 'holdout.json'))
    Invoke-Step 'unit-tests' @('-m', 'unittest', 'discover', '-s', 'tool/voice_wake/neural', '-p', 'test_pipeline.py', '-v')
} finally { Pop-Location }
