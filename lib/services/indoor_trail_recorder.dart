import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/indoor_trail.dart';
import 'compass_service.dart';
import 'field_logger.dart';
import 'indoor_gate.dart';
import 'indoor_trail_store.dart';
import 'settings_service.dart';
import 'step_service.dart';

/// State machine of a single recording session.
enum IndoorTrailRecorderState { idle, recording, paused, finished, error }

/// Captures step-cadence samples (heading, magnetic magnitude, IMU
/// summaries) while the user walks a fixed indoor route, then hands the
/// finished trail to `IndoorTrailStore`.
///
/// Hard requirements per the growth-direction plan:
///   - Only starts when [SettingsService.indoorTrailMemory] is `true`.
///   - Refuses to start when `IndoorGate` reports `IndoorState.street`
///     *and* GPS quality is good; recording only makes sense indoors
///     or when GPS is unreliable.
///   - Persists nothing until [stop] is called.
///   - Stays an opt-in tool: never auto-records.
class IndoorTrailRecorder {
  IndoorTrailRecorder({
    required this.compass,
    required this.steps,
    required this.indoorGate,
    IndoorTrailStore? store,
    Duration pollInterval = const Duration(milliseconds: 250),
  })  : _store = store ?? IndoorTrailStore.instance,
        _pollInterval = pollInterval;

  final CompassService compass;
  final StepService steps;
  final IndoorGate indoorGate;
  final IndoorTrailStore _store;
  final Duration _pollInterval;

  /// Snapshot of the most recent IMU samples. Smoothed via a small
  /// exponential moving average to suppress single-frame outliers.
  double _accelMagEma = 0;
  double _gyroMagEma = 0;
  double _magMagEma = 0;
  bool _hasMag = false;
  double? _pressureHpa;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  Timer? _pollTimer;

  IndoorTrailRecorderState _state = IndoorTrailRecorderState.idle;
  IndoorTrailRecorderState get state => _state;

  String _name = '';
  String _langCode = 'ru';
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _baseStepCount = 0;
  int _lastSeenStepCount = 0;
  final List<IndoorTrailSample> _samples = <IndoorTrailSample>[];
  String? _pendingLandmark;

  int get sampleCount => _samples.length;
  bool get isActive =>
      _state == IndoorTrailRecorderState.recording ||
      _state == IndoorTrailRecorderState.paused;

  /// Start a recording. [name] is the user-visible target (e.g.
  /// "pharmacy"). [langCode] is the two-letter language the name was
  /// spoken in, used by replay to localise prompts.
  ///
  /// Returns `false` if the feature flag is off, if a recording is
  /// already in progress, or if [allowOutdoor] is `false` and the
  /// IndoorGate currently reports a confident "street" state.
  Future<bool> start({
    required String name,
    required String langCode,
    bool allowOutdoor = false,
  }) async {
    if (_state == IndoorTrailRecorderState.recording ||
        _state == IndoorTrailRecorderState.paused) {
      return false;
    }
    if (!Settings.instance.indoorTrailMemory) {
      FieldLogger.instance
          .logIndoorTrail('start_blocked_flag_off');
      return false;
    }
    if (!allowOutdoor && indoorGate.state == IndoorState.street) {
      FieldLogger.instance.logIndoorTrail('start_blocked_outdoor');
      return false;
    }
    if (name.trim().isEmpty) {
      FieldLogger.instance.logIndoorTrail('start_blocked_empty_name');
      return false;
    }

    _name = name.trim();
    _langCode = langCode;
    _startedAt = DateTime.now();
    _baseStepCount = steps.steps;
    _lastSeenStepCount = _baseStepCount;
    _samples.clear();
    _pendingLandmark = null;
    _accelMagEma = 0;
    _gyroMagEma = 0;
    _magMagEma = 0;
    _hasMag = false;
    _pressureHpa = null;

    _state = IndoorTrailRecorderState.recording;

    _attachSensors();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());

    FieldLogger.instance.logIndoorTrail('start', data: {
      'lang': langCode,
      'indoor': indoorGate.state.name,
    });
    return true;
  }

  /// Pause without dropping captured samples.
  void pause() {
    if (_state != IndoorTrailRecorderState.recording) return;
    _state = IndoorTrailRecorderState.paused;
    FieldLogger.instance.logIndoorTrail('pause');
  }

  /// Resume a paused recording.
  void resume() {
    if (_state != IndoorTrailRecorderState.paused) return;
    _state = IndoorTrailRecorderState.recording;
    _lastSeenStepCount = steps.steps;
    FieldLogger.instance.logIndoorTrail('resume');
  }

  /// Stop recording and persist the trail. Returns the saved record on
  /// success, or null when no samples were captured / persistence
  /// failed.
  Future<IndoorTrail?> stop() async {
    if (_state == IndoorTrailRecorderState.idle ||
        _state == IndoorTrailRecorderState.finished) {
      return null;
    }
    _state = IndoorTrailRecorderState.finished;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _detachSensors();

    if (_samples.isEmpty) {
      FieldLogger.instance.logIndoorTrail('stop_empty');
      return null;
    }

    final id = IndoorTrail.makeId(_name, _startedAt);
    final trail = IndoorTrail(
      id: id,
      name: _name,
      langCode: _langCode,
      createdAt: _startedAt,
      samples: List<IndoorTrailSample>.unmodifiable(_samples),
    );
    final saved = await _store.save(trail);
    return saved;
  }

  /// Abort recording without persisting anything.
  Future<void> cancel() async {
    if (!isActive) return;
    _state = IndoorTrailRecorderState.idle;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _detachSensors();
    _samples.clear();
    FieldLogger.instance.logIndoorTrail('cancel');
  }

  /// Tag the *next* captured sample with a short voice landmark string
  /// (e.g. "elevator", "lobby"). One landmark per sample; subsequent
  /// calls before the next step replace the pending tag.
  void addLandmark(String landmark) {
    final s = landmark.trim();
    if (s.isEmpty) return;
    _pendingLandmark = s.length > 64 ? s.substring(0, 64) : s;
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    unawaited(_detachSensors());
    _state = IndoorTrailRecorderState.idle;
  }

  
  void _attachSensors() {
    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 80),
      ).listen((event) {
        final m = math.sqrt(event.x * event.x +
            event.y * event.y +
            event.z * event.z);
        _accelMagEma = _accelMagEma == 0 ? m : _accelMagEma * 0.7 + m * 0.3;
      }, onError: (_) {});
    } catch (e) {
      debugPrint('IndoorTrailRecorder: accel attach failed: $e');
    }
    try {
      _gyroSub = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 80),
      ).listen((event) {
        final m = math.sqrt(event.x * event.x +
            event.y * event.y +
            event.z * event.z);
        _gyroMagEma = _gyroMagEma == 0 ? m : _gyroMagEma * 0.7 + m * 0.3;
      }, onError: (_) {});
    } catch (e) {
      debugPrint('IndoorTrailRecorder: gyro attach failed: $e');
    }
    try {
      _magSub = magnetometerEventStream(
        samplingPeriod: const Duration(milliseconds: 120),
      ).listen((event) {
        final m = math.sqrt(event.x * event.x +
            event.y * event.y +
            event.z * event.z);
        _magMagEma = _magMagEma == 0 ? m : _magMagEma * 0.6 + m * 0.4;
        _hasMag = true;
      }, onError: (_) {});
    } catch (e) {
      debugPrint('IndoorTrailRecorder: magnetometer attach failed: $e');
    }
  }

  Future<void> _detachSensors() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _magSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _magSub = null;
  }

  void _tick() {
    if (_state != IndoorTrailRecorderState.recording) return;
    final current = steps.steps;
    if (current == _lastSeenStepCount) return;
    final deltaSteps = current - _lastSeenStepCount;
    _lastSeenStepCount = current;
    if (deltaSteps <= 0) return;
    if (!_hasMag) {
      
      
      return;
    }
    final stepIndex = current - _baseStepCount;
    final sample = IndoorTrailSample(
      stepIndex: stepIndex,
      headingDeg: compass.heading,
      magMicroT: _magMagEma,
      accelMag: _accelMagEma,
      gyroMag: _gyroMagEma,
      pressureHpa: _pressureHpa,
      landmark: _pendingLandmark,
      at: DateTime.now(),
    );
    _samples.add(sample);
    _pendingLandmark = null;
  }

  
  @visibleForTesting
  void debugInjectSample(IndoorTrailSample s) {
    _samples.add(s);
    _lastSeenStepCount = _baseStepCount + s.stepIndex;
  }

  @visibleForTesting
  IndoorTrailRecorderState debugForceState(IndoorTrailRecorderState s) =>
      _state = s;

  @visibleForTesting
  void debugSetSensorReadings({
    required double accelMag,
    required double gyroMag,
    required double magMicroT,
  }) {
    _accelMagEma = accelMag;
    _gyroMagEma = gyroMag;
    _magMagEma = magMicroT;
    _hasMag = true;
  }
}
