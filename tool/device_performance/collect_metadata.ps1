param(
  [string]$Serial,
  [string]$OutputDirectory = "scratch/device-performance-metadata"
)

$ErrorActionPreference = "Stop"
$taskRepo = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$taskOutput = [System.IO.Path]::GetFullPath((Join-Path $taskRepo $OutputDirectory))
if (-not $taskOutput.StartsWith($taskRepo + [System.IO.Path]::DirectorySeparatorChar,
    [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "OutputDirectory must be inside the repository."
}
$taskAdbCommand = Get-Command adb -ErrorAction SilentlyContinue
$taskAdb = if ($taskAdbCommand) { $taskAdbCommand.Source } else {
  Join-Path $env:LOCALAPPDATA "Android/sdk/platform-tools/adb.exe"
}
if (-not (Test-Path -LiteralPath $taskAdb)) { throw "Android adb was not found." }
$taskDeviceLines = & $taskAdb devices -l
if ($LASTEXITCODE -ne 0) { throw "adb device enumeration failed." }
$taskDevices = @($taskDeviceLines | ForEach-Object {
  if ($_ -match '^(\S+)\s+device(?:\s|$)') { $Matches[1] }
})
if (-not $Serial -and $taskDevices.Count -eq 1) { $Serial = $taskDevices[0] }
if ($Serial -and $Serial -notin $taskDevices) { throw "Selected device is not attached and authorized." }
$taskReceipt = [ordered]@{
  schema = "bagdar-device-performance-metadata-v1"
  generatedAtUtc = [DateTime]::UtcNow.ToString("o")
  deviceRuntime = "not_run"
  attachedDeviceCount = $taskDevices.Count
  captureLatencyMeasured = $false
  source = [ordered]@{ commit = (& git -C $taskRepo rev-parse HEAD).Trim(); dirty = [bool](& git -C $taskRepo status --porcelain) }
}
if ($Serial) {
  if ($Serial -match '^emulator-') { throw "Performance evidence requires a physical device." }
  $taskProps = [ordered]@{}
  foreach ($taskProp in @('ro.product.manufacturer','ro.product.model','ro.build.version.sdk',
      'ro.build.version.release','ro.hardware','ro.product.cpu.abi','ro.kernel.qemu')) {
    $taskValue = & $taskAdb -s $Serial shell getprop $taskProp
    if ($LASTEXITCODE -ne 0) { throw "Device property query failed." }
    $taskProps[$taskProp] = ($taskValue -join "`n").Trim()
  }
  if ($taskProps['ro.kernel.qemu'] -eq '1') { throw "Emulator is not phone performance evidence." }
  $taskReceipt.device = $taskProps
  $taskReceipt.memory = ((& $taskAdb -s $Serial shell cat /proc/meminfo) | Select-Object -First 5)
  $taskReceipt.battery = @(& $taskAdb -s $Serial shell dumpsys battery)
  $taskReceipt.deviceRuntime = "metadata_only"
  $taskReceipt.apk = "not_verified"
}
$taskHashes = [ordered]@{}
foreach ($taskFile in @('assets/yolov8n_int8.tflite','assets/midas_small.ncnn.param',
    'assets/midas_small.ncnn.bin','lib/services/ncnn_depth_provider.dart',
    'lib/services/ncnn_depth_processor.dart','lib/services/ncnn_depth_worker.dart',
    'lib/services/ncnn_depth_worker_types.dart','lib/services/ncnn_depth_bridge.dart',
    'lib/camera/depth_pipeline_controller.dart','lib/camera_screen.dart',
    'lib/core/performance/perception_performance.dart','lib/models/frame_packet.dart',
    'lib/services/model_service.dart','lib/services/field_logger.dart',
    'integration_test/core_ncnn_worker_profile_test.dart',
    'test_driver/perception_performance_driver.dart',
    'test/ncnn_depth_worker_test.dart','test/perception_performance_test.dart',
    'test/depth_pipeline_observation_guard_test.dart',
    'test/generic_obstacle_semantic_fusion_test.dart')) {
  $taskHashes[$taskFile] = (Get-FileHash -LiteralPath (Join-Path $taskRepo $taskFile) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$taskReceipt.artifactHashes = $taskHashes
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
$taskReceiptPath = Join-Path $taskOutput "metadata.json"
$taskReceipt | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $taskReceiptPath -Encoding UTF8
Write-Output "Metadata receipt: $taskReceiptPath"
if (-not $Serial) {
  Write-Output "No single selected physical phone; runtime measurements remain not_run."
  exit 2
}
