[CmdletBinding()]
param([switch]$WriteValidation)
$ErrorActionPreference = 'Stop'
$motionOriginProject = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location -LiteralPath $motionOriginProject
try {
  & flutter test --no-pub --concurrency=1 --reporter=expanded `
    --dart-define=BAGDAR_MOTION_ORIGIN=true --dart-define=BAGDAR_CHECK_MOTION_ORIGIN=true `
    --dart-define=BAGDAR_SEQUENCE_SELECTION=true --dart-define=BAGDAR_CHECK_SEQUENCE_SELECTION=true `
    --dart-define=BAGDAR_SEQUENCE_RETURN=true --dart-define=BAGDAR_CHECK_SEQUENCE_RETURN=true `
    --dart-define=BAGDAR_FIRST_RETURN=true --dart-define=BAGDAR_CHECK_FIRST_RETURN=true `
    --dart-define=BAGDAR_SYNC_PASSAGE=true --dart-define=BAGDAR_CHECK_SYNC_PASSAGE=true `
    test/motion_origin_experiment_test.dart test/frame_stable_generic_obstacle_detector_test.dart `
    test/camera_fast_motion_shadow_replay_test.dart test/camera_fast_motion_test.dart `
    test/camera_metric_motion_shadow_scene_test.dart `
    test/prepare_sequence_first_return_test.dart test/sequence_first_return_experiment_test.dart `
    test/track_first_return_experiment_test.dart test/synchronized_passage_experiment_test.dart `
    test/camera_synchronized_rig_test.dart test/camera_scan_age_gate_test.dart `
    test/path_clear_stop_diagnosis_test.dart test/coverage_aware_stop_guidance_test.dart `
    test/generic_geometry_confidence_authority_test.dart test/camera_track_association_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Motion origin or safety regressions failed' }
  & 'tools/ncnn/.venv/Scripts/python.exe' -m unittest discover -s tool/blender -p test_pixel_exact_surface_envelope.py
  if ($LASTEXITCODE -ne 0) { throw 'Exact first-return regressions failed' }
  if ($WriteValidation) {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_motion_origin.py --write
  } else {
    & 'tools/ncnn/.venv/Scripts/python.exe' tool/model_benchmark/verify_motion_origin.py
  }
  if ($LASTEXITCODE -ne 0) { throw 'Motion origin or prior integrity contract failed' }
} finally {
  Pop-Location
}
