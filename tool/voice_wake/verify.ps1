param([string]$OutputDirectory = 'output/voice-wake-stage5-2026-10-13')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = [System.IO.Path]::GetFullPath((Join-Path $repo $OutputDirectory))
New-Item -ItemType Directory -Force -Path $output | Out-Null
function Invoke-Logged([string]$Name, [string]$Program, [string[]]$Arguments) {
    $log = Join-Path $output ($Name + '.log')
    & $Program @Arguments *> $log
    if ($LASTEXITCODE -ne 0) { throw "$Name failed; see $log" }
    Write-Output "$Name passed"
}
Push-Location $repo
$previousJava = $env:JAVA_HOME
try {
    Invoke-Logged 'analyze-final' 'flutter' @('analyze', '--no-pub', 'lib',
        'test/wake_word_probe_test.dart', 'test/wake_word_native_input_test.dart',
        'test/wake_word_probe_widget_test.dart')
    $tests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'regression-tests.txt')
    $tests | Set-Content -LiteralPath (Join-Path $output 'test-files.txt')
    Invoke-Logged 'regression' 'flutter' (@('test', '--no-pub') + $tests + @('--concurrency=1', '--reporter=expanded'))
    $env:JAVA_HOME = 'C:/Program Files/Android/Android Studio/jbr'
    Push-Location (Join-Path $repo 'android')
    try { Invoke-Logged 'android-unit' '.\gradlew.bat' @(':app:testCoreDebugUnitTest', '--console=plain') }
    finally { Pop-Location }
    Invoke-Logged 'core-build' 'flutter' @('build', 'apk', '--flavor', 'core', '--debug', '--no-pub')
    Invoke-Logged 'research-build' 'flutter' @('build', 'apk', '--flavor', 'research', '--debug', '--no-pub',
        '--dart-define=BAGDAR_RESEARCH=true', '--dart-define=BAGDAR_WAKE_PROBE=true')
} finally { $env:JAVA_HOME = $previousJava; Pop-Location }
