# Download ncnn Android prebuilt runtime (with Vulkan).
# Places headers + libs into android/app/src/main/cpp/third_party/ncnn/.
# Required ABIs: arm64-v8a, armeabi-v7a, x86_64 (debug emulator).

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$ThirdParty = Join-Path $RepoRoot "android/app/src/main/cpp/third_party/ncnn"
$TmpZip = Join-Path $PSScriptRoot "ncnn-android.zip"
$TmpDir = Join-Path $PSScriptRoot "ncnn-android-tmp"

# Pinned release.
$Release = "20240820"
$Url = "https://github.com/Tencent/ncnn/releases/download/$Release/ncnn-$Release-android-vulkan.zip"

if (Test-Path (Join-Path $ThirdParty "lib/arm64-v8a/libncnn.a")) {
    Write-Host "[skip] ncnn android libs already present in $ThirdParty"
    exit 0
}

New-Item -ItemType Directory -Force -Path $ThirdParty | Out-Null
Write-Host "Downloading $Url ..."
Invoke-WebRequest -Uri $Url -OutFile $TmpZip -UseBasicParsing

Write-Host "Extracting ..."
if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
Expand-Archive -Path $TmpZip -DestinationPath $TmpDir -Force

# Locate the per-ABI directories: each contains include/ and lib/.
$RootDir = Get-ChildItem -Path $TmpDir -Directory | Select-Object -First 1
if (-not $RootDir) {
    Write-Error "Empty archive"
    exit 1
}

# Layout: $RootDir/<ABI>/{include,lib}
$IncludeCopied = $false
foreach ($abiDir in Get-ChildItem -Path $RootDir.FullName -Directory) {
    $abi = $abiDir.Name
    if ($abi -notin @("arm64-v8a", "armeabi-v7a", "x86_64", "x86")) { continue }

    $libSrc = Join-Path $abiDir.FullName "lib"
    $libDst = Join-Path $ThirdParty "lib/$abi"
    if (Test-Path $libSrc) {
        New-Item -ItemType Directory -Force -Path $libDst | Out-Null
        Copy-Item -Recurse -Force "$libSrc/*" $libDst
        Write-Host "[ok] $abi libs -> $libDst"
    }

    if (-not $IncludeCopied) {
        $incSrc = Join-Path $abiDir.FullName "include"
        $incDst = Join-Path $ThirdParty "include"
        if (Test-Path $incSrc) {
            New-Item -ItemType Directory -Force -Path $incDst | Out-Null
            Copy-Item -Recurse -Force "$incSrc/*" $incDst
            Write-Host "[ok] include -> $incDst"
            $IncludeCopied = $true
        }
    }
}

Remove-Item -Recurse -Force $TmpDir
Remove-Item -Force $TmpZip

Write-Host "`nDone. NCNN runtime installed in $ThirdParty"
Write-Host "Now run: flutter clean; flutter run"
