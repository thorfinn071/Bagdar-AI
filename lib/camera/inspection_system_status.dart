import '../core/core_health.dart';
import '../models/strings.dart';
import 'inspection_scene_status.dart';

/// A readable service snapshot, never an admission or a clear-path decision.
class InspectionSystemStatus {
  final String summary;
  final List<String> details;
  final InspectionSceneStatus scene;

  const InspectionSystemStatus(
    this.summary,
    this.details, {
    this.scene = const InspectionSceneStatus.notChecked(),
  });

  String get observationText =>
      S.get('inspection_observation_${scene.observation.name}');
  String get clearanceText =>
      S.get('inspection_clearance_${scene.clearance.name}');
  String get movementText => S.get('inspection_movement_stationary_only');

  String get spokenText =>
      '${S.get('core_health_status')}. $observationText. $clearanceText. '
      '$movementText. $summary. ${details.join('. ')}';

  factory InspectionSystemStatus.fromHealth(
    CoreHealthSnapshot health, {
    required bool cameraReady,
    required bool permissionDenied,
    InspectionSceneStatus scene = const InspectionSceneStatus.notChecked(),
  }) {
    String state(CoreComponent component) {
      final value = health.components[component]?.state;
      return S.get('inspection_state_${value?.name ?? 'unchecked'}');
    }

    final camera = permissionDenied
        ? S.get('inspection_permission_denied')
        : !cameraReady
        ? S.get('inspection_camera_waiting')
        : {
            for (final c in [
              CoreComponent.cameraPermission,
              CoreComponent.cameraSession,
              CoreComponent.imageStream,
            ])
              state(c),
          }.join(', ');
    final run = permissionDenied || !cameraReady
        ? 'camera_unavailable'
        : health.runState.name;
    return InspectionSystemStatus(
      S.get('inspection_run_$run'),
      [
        '${S.get('inspection_camera')}: $camera',
        '${S.get('inspection_objects')}: ${state(CoreComponent.semanticObjects)}',
        '${S.get('inspection_geometry')}: ${state(CoreComponent.genericGeometry)}',
        '${S.get('inspection_audio')}: ${state(CoreComponent.alertAudio)}',
        '${S.get('inspection_haptics')}: ${state(CoreComponent.haptics)}',
      ],
      scene: cameraReady && !permissionDenied
          ? scene
          : const InspectionSceneStatus.unavailable(),
    );
  }
}
