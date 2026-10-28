param([string]$OutputDirectory = 'scratch/fast-motion-simd', [string]$ClangPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $root
if (-not $ClangPath) {
  $ndkRoot = Join-Path $env:LOCALAPPDATA 'Android/Sdk/ndk'
  $ClangPath = Get-ChildItem -LiteralPath $ndkRoot -Filter clang.exe -Recurse |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $ClangPath) { throw 'Supply -ClangPath for a Windows-host LLVM compiler.' }
$linker = Join-Path (Split-Path -Parent $ClangPath) 'ld.lld.exe'
if (-not (Test-Path -LiteralPath $linker)) { throw 'LLVM linker unavailable.' }
$out = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
[IO.Directory]::CreateDirectory($out) | Out-Null
$object = Join-Path $out 'fast_motion_match_simd.obj'
$dll = Join-Path $out 'fast_motion_match_simd.dll'
& $ClangPath --target=x86_64-pc-windows-msvc -O3 -fno-fast-math -ffp-contract=off `
  -fno-math-errno -c 'tool/model_benchmark/native/fast_motion_match_simd.c' -o $object
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# No CRT, process initialization, external dependencies or native allocation.
& $linker -flavor link /dll /noentry /nodefaultlib /machine:x64 "/out:$dll" $object
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $ClangPath --version
Write-Output "Native strict SIMD2 matcher: $dll"
