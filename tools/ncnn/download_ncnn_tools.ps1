# Download ncnn CLI tools (onnx2ncnn, ncnnoptimize) for Windows.
# Place result in tools/ncnn/bin/.

$ErrorActionPreference = "Stop"
$ToolsDir = $PSScriptRoot
$BinDir = Join-Path $ToolsDir "bin"
$TmpZip = Join-Path $ToolsDir "ncnn-tools.zip"
$TmpDir = Join-Path $ToolsDir "ncnn-tmp"

# Pinned release with Windows VS2019 binaries.
$Release = "20240820"
$Url = "https://github.com/Tencent/ncnn/releases/download/$Release/ncnn-$Release-windows-vs2019.zip"

if (Test-Path (Join-Path $BinDir "onnx2ncnn.exe")) {
    Write-Host "[skip] ncnn tools already present in $BinDir"
    exit 0
}

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Write-Host "Downloading $Url ..."
Invoke-WebRequest -Uri $Url -OutFile $TmpZip -UseBasicParsing

Write-Host "Extracting ..."
if (Test-Path $TmpDir) { Remove-Item -Recurse -Force $TmpDir }
Expand-Archive -Path $TmpZip -DestinationPath $TmpDir -Force

# Locate onnx2ncnn.exe and ncnnoptimize.exe within the archive.
$Found = Get-ChildItem -Path $TmpDir -Recurse -Include "onnx2ncnn.exe","ncnnoptimize.exe" -File
if ($Found.Count -lt 2) {
    Write-Error "Could not locate both onnx2ncnn.exe and ncnnoptimize.exe in archive"
    exit 1
}

foreach ($f in $Found) {
    Copy-Item $f.FullName -Destination $BinDir -Force
    Write-Host "[ok] $($f.Name) -> $BinDir"
}

Remove-Item -Recurse -Force $TmpDir
Remove-Item -Force $TmpZip

Write-Host "`nDone. Tools installed in $BinDir"
