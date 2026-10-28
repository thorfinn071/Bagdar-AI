param(
  [ValidateSet('render','package','build','run','collect','evaluate')]
  [string]$Action = 'run',
  [string]$Corpus = 'output/simulation-lab/render-v2',
  [string]$Sequence = '',
  [string[]]$Sequences = @(),
  [string]$Device = 'emulator-5554',
  [string]$Blender = 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe',
  [string]$Python = 'python',
  [switch]$Smoke,
  [switch]$NoBuild,
  [switch]$StartEmulator,
  [switch]$InAppBatch,
  [switch]$WaitForBatch
)
$ErrorActionPreference = 'Stop'
$labRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Set-Location -LiteralPath $labRoot
$corpusPath = [IO.Path]::GetFullPath((Join-Path $labRoot $Corpus))
if (-not $corpusPath.StartsWith((Join-Path $labRoot 'output') + [IO.Path]::DirectorySeparatorChar)) {
  throw 'Choose a corpus directory inside the workspace output/ directory.'
}
$runtimePath = Join-Path $corpusPath 'runtime'
$package = 'com.example.bagdar.simulation'
$remote = "/data/user/0/$package/files/simulation"
$adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
function Invoke-LabCommand([string]$File, [string[]]$Arguments) {
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}
function Build-Simulation {
  $previousGradleOptions = $env:GRADLE_OPTS
  try {
    $env:GRADLE_OPTS = "$previousGradleOptions -Dorg.gradle.workers.max=2 -Dorg.gradle.jvmargs=-Xmx2g -Dorg.gradle.daemon=false -Dkotlin.daemon.jvm.options=-Xmx768m"
    Invoke-LabCommand 'flutter' @('build','apk','--debug','--no-pub','--flavor','simulation',
      '--target','lib/simulation_main.dart','--target-platform','android-x64',
      '--dart-define=BAGDAR_SIMULATION=true','--dart-define=BAGDAR_SIMULATION_CPU=true',
      "--dart-define=BAGDAR_SIMULATION_MANIFEST=$remote/manifest.json")
  } finally {
    $env:GRADLE_OPTS = $previousGradleOptions
  }
  $sourceHashes = [ordered]@{}
  Get-ChildItem -LiteralPath (Join-Path $labRoot 'lib') -Recurse -File -Filter '*.dart' |
    Sort-Object FullName | ForEach-Object {
      $sourceHashes[$_.FullName.Substring($labRoot.Length+1).Replace('\','/')] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  $receipt = @{ flavor='simulation'; mode='debug'; abi='x86_64'; sourceHashes=$sourceHashes;
    apkSha256=(Get-FileHash -LiteralPath 'build/app/outputs/flutter-apk/app-simulation-debug.apk' -Algorithm SHA256).Hash.ToLowerInvariant();
    physicalDeviceValidation='not_run'; promotionAllowed=$false }
  $receiptPath = Join-Path $labRoot 'output/simulation-lab/build-receipt.json'
  New-Item -ItemType Directory -Force -Path (Split-Path $receiptPath) | Out-Null
  [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
}
switch ($Action) {
  'render' {
    $renderArgs = @('--background','--python-exit-code','1','--python','tool/simulation/generate_scenes.py',
      '--','--output',$corpusPath)
    if (Test-Path -LiteralPath (Join-Path $labRoot 'City/building-a.fbx')) { $renderArgs += @('--urban-assets','City') }
    if ($Smoke) { $renderArgs += '--smoke' }
    Invoke-LabCommand $Blender $renderArgs
  }
  'package' { Invoke-LabCommand $Python @('tool/simulation/package_replay.py',$corpusPath) }
  'build' { Build-Simulation }
  'run' {
    if (-not (Test-Path -LiteralPath (Join-Path $runtimePath 'manifest.json'))) { throw 'Package this corpus first.' }
    if ($Device -notmatch '^emulator-[0-9]+$') { throw 'This command targets an Android emulator.' }
    if (-not $NoBuild) { Build-Simulation }
    $qemu = & $adb -s $Device shell getprop ro.kernel.qemu 2>$null
    if ($LASTEXITCODE -ne 0 -or "$qemu".Trim() -ne '1') {
      if (-not $StartEmulator) { throw 'The selected emulator is not running. Use -StartEmulator or start it in Android Studio.' }
      $emulator = Join-Path $env:LOCALAPPDATA 'Android/Sdk/emulator/emulator.exe'
      $port = $Device.Replace('emulator-','')
      $emulatorArgs = @('-avd','Bagdar_Simulation','-port',$port,
        '-no-audio','-no-snapshot','-no-boot-anim','-gpu','swiftshader_indirect','-memory','2048')
      if ($Sequence -eq 'all') {
        $emulatorArgs += '-no-window'
        Start-Process -FilePath $emulator -ArgumentList $emulatorArgs -WindowStyle Hidden
      } else {
        # Interactive scene selection needs the emulator window.
        Start-Process -FilePath $emulator -ArgumentList $emulatorArgs -WindowStyle Normal
      }
      $bootDeadline = [DateTime]::UtcNow.AddMinutes(3)
      do {
        Start-Sleep -Seconds 3
        $booted = & $adb -s $Device shell getprop sys.boot_completed 2>$null
      } while ("$booted".Trim() -ne '1' -and [DateTime]::UtcNow -lt $bootDeadline)
      if ("$booted".Trim() -ne '1') { throw 'Emulator did not boot.' }
    }
    Invoke-LabCommand $adb @('-s',$Device,'install','-r','build/app/outputs/flutter-apk/app-simulation-debug.apk')
    Invoke-LabCommand $adb @('-s',$Device,'shell','am','force-stop',$package)
    if ($Sequence -and $Sequence -ne 'all') {
      $manifest = Get-Content -LiteralPath (Join-Path $runtimePath 'manifest.json') -Raw | ConvertFrom-Json
      if ($Sequence -notin $manifest.sequences.id) { throw "Unknown sequence: $Sequence" }
    }
    $runId = [guid]::NewGuid().ToString()
    $control = @{ sequenceId=$Sequence; autoClose=($Sequence -eq 'all'); runId=$runId }
    if ($Sequences.Count -gt 0) {
      if ($Sequence -ne 'all') { throw '-Sequences requires -Sequence all.' }
      $manifest = Get-Content -LiteralPath (Join-Path $runtimePath 'manifest.json') -Raw | ConvertFrom-Json
      if (($Sequences | Select-Object -Unique).Count -ne $Sequences.Count) { throw 'Duplicate sequence IDs.' }
      foreach ($selectedSequence in $Sequences) {
        if ($selectedSequence -notin $manifest.sequences.id) { throw "Unknown sequence: $selectedSequence" }
      }
      $control.sequenceIds = $Sequences
    }
    $controlJson = $control | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $runtimePath 'control.json'), $controlJson, [Text.UTF8Encoding]::new($false))
    Invoke-LabCommand $Python @('tool/simulation/device_io.py','push',$runtimePath,'--adb',$adb,'--serial',$Device)
    if ($Sequence -eq 'all' -and -not $InAppBatch) {
      Invoke-LabCommand $Python @('tool/simulation/process_batch.py',$corpusPath,'--adb',$adb,'--serial',$Device)
    } else {
      Invoke-LabCommand $adb @('-s',$Device,'shell','am','start','-n',"$package/com.example.bagdar.MainActivity")
    }
    if ($WaitForBatch -and $Sequence -eq 'all' -and $InAppBatch) {
      $deadline = [DateTime]::UtcNow.AddMinutes(30)
      $finished = $false
      while ([DateTime]::UtcNow -lt $deadline) {
        $markerText = & $adb -s $Device shell -T run-as $package cat 'files/simulation/batch-complete.json' 2>$null
        if ($LASTEXITCODE -eq 0) {
          $marker = "$markerText" | ConvertFrom-Json
          if ($marker.runId -eq $runId) {
            if ($marker.error) { throw "Batch failed: $($marker.error)" }
            if ($marker.completed) { $finished = $true; break }
          }
        }
        Start-Sleep -Seconds 3
      }
      if (-not $finished) { throw 'Batch did not finish within 30 minutes. Collect partial reports and inspect logcat.' }
    }
  }
  'collect' {
    Invoke-LabCommand $Python @('tool/simulation/device_io.py','collect',$corpusPath,'--adb',$adb,'--serial',$Device)
  }
  'evaluate' { Invoke-LabCommand $Python @('tool/simulation/evaluate_runs.py',$corpusPath) }
}
