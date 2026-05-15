import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/external_hazard.dart';
import '../models/indoor_trail.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../utils/alert_filter.dart' show AlertCategory;
import 'compass_service.dart';
import 'field_logger.dart';
import 'indoor_trail_store.dart';
import 'particle_trail_localizer.dart';
import 'settings_service.dart';
import 'step_service.dart';

enum IndoorTrailReplayState { idle, replaying, lost, arrived, error }

/// Drives turn-by-turn-ish prompts from a previously recorded
/// [IndoorTrail]. The replay layer is intentionally conservative —
/// when the particle filter's confidence drops below the lost-threshold
/// it announces "trail lost" rather than guessing a next turn. Per the
/// growth-direction plan: failure states clearly say *trail lost*
/// rather than giving false turns.
///
/// This service NEVER calls TTS directly. It emits
/// [ExternalHazardEvent] payloads via [onHazard] so the host can route
/// them through `AlertManager.handleExternalHazard` and inherit the
/// unified cooldowns / verbosity / alertFrequency gating.
class IndoorTrailReplay {
  IndoorTrailReplay({
    required this.compass,
    required this.steps,
    IndoorTrailStore? store,
    ParticleTrailLocalizer? localizer,
    Duration pollInterval = const Duration(milliseconds: 250),
  })  : _store = store ?? IndoorTrailStore.instance,
        _localizer = localizer ?? ParticleTrailLocalizer(),
        _pollInterval = pollInterval;

  final CompassService compass;
  final StepService steps;
  final IndoorTrailStore _store;
  final ParticleTrailLocalizer _localizer;
  final Duration _pollInterval;

  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _pollTimer;

  /// Receives every prompt or lost-trail announcement.
  void Function(ExternalHazardEvent event)? onHazard;

  /// Fires when the replay reaches the recorded destination.
  void Function(IndoorTrail trail)? onArrived;

  /// Fires when the replay enters the lost state.
  void Function()? onLost;

  IndoorTrailReplayState _state = IndoorTrailReplayState.idle;
  IndoorTrailReplayState get state => _state;

  IndoorTrail? _trail;
  IndoorTrail? get trail => _trail;

  int _baseStepCount = 0;
  int _lastSeenStepCount = 0;
  double _magMagEma = 0;
  bool _hasMag = false;

  /// Last announced step index (rounded). Suppresses repeat prompts at
  /// the same trail position.
  int _lastAnnouncedIndex = -1;

  /// Threshold on particle stddev (in step units) that flips the
  /// session into the lost state. Conservative: the filter must agree
  /// within ~1 step's worth of uncertainty for prompts to fire.
  static const double _kLostStdThreshold = 4.0;

  /// Effective sample size below this fraction of the total particle
  /// count counts as "lost" too.
  static const double _kLostEssFraction = 0.20;

  /// How many consecutive lost-state observations before announcing.
  /// Prevents single-frame outliers from triggering the lost prompt.
  static const int _kLostFramesRequired = 3;

  int _lostStreak = 0;
  bool _lostAnnounced = false;

  /// Begin replaying [trail]. Returns false if the feature flag is off
  /// or another session is already active.
  Future<bool> start(IndoorTrail trail) async {
    if (!Settings.instance.indoorTrailMemory) {
      FieldLogger.instance.logIndoorTrail('replay_blocked_flag_off');
      return false;
    }
    if (_state == IndoorTrailReplayState.replaying) return false;
    if (trail.samples.length < 2) {
      FieldLogger.instance.logIndoorTrail('replay_blocked_short', data: {
        'samples': trail.samples.length,
      });
      return false;
    }

    _trail = trail;
    _baseStepCount = steps.steps;
    _lastSeenStepCount = _baseStepCount;
    _lastAnnouncedIndex = -1;
    _lostStreak = 0;
    _lostAnnounced = false;
    _magMagEma = 0;
    _hasMag = false;

    _localizer.reset();
    _attachSensors();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
    _state = IndoorTrailReplayState.replaying;

    FieldLogger.instance.logIndoorTrail('replay_start', data: {
      'id': trail.id,
      'samples': trail.samples.length,
    });

    _emitLocalized(
      key: 'trail_replay_started',
      fallback: 'Trail replay started.',
      priority: SpeechPriority.info,
      category: AlertCategory.navigationHint,
      urgency: 0.4,
    );
    return true;
  }

  /// Look up a trail by name and start replaying it. Convenience for
  /// the voice command "go to {name}".
  Future<bool> startByName(String name) async {
    final t = await _store.findByName(name);
    if (t == null) {
      FieldLogger.instance.logIndoorTrail('replay_not_found', data: {
        'name': name,
      });
      _emitLocalized(
        key: 'trail_not_found',
        fallback: 'Trail not found.',
        priority: SpeechPriority.info,
        category: AlertCategory.navigationHint,
        urgency: 0.3,
      );
      return false;
    }
    return start(t);
  }

  /// Stop replay and detach sensors. Idempotent.
  Future<void> stop() async {
    if (_state == IndoorTrailReplayState.idle) return;
    _state = IndoorTrailReplayState.idle;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _detachSensors();
    _trail = null;
    FieldLogger.instance.logIndoorTrail('replay_stop');
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _detachSensors();
    _state = IndoorTrailReplayState.idle;
  }

  // -- Internals --------------------------------------------------------

  void _attachSensors() {
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
      debugPrint('IndoorTrailReplay: magnetometer attach failed: $e');
    }
  }

  Future<void> _detachSensors() async {
    await _magSub?.cancel();
    _magSub = null;
  }

  void _tick() {
    final trail = _trail;
    if (trail == null || _state != IndoorTrailReplayState.replaying) return;
    if (!_hasMag) return;

    final current = steps.steps;
    final delta = current - _lastSeenStepCount;
    if (delta < 0) {
      // Step counter reset under us. Treat as no new steps.
      _lastSeenStepCount = current;
      return;
    }
    _lastSeenStepCount = current;
    if (delta == 0) return;

    final loc = _localizer.update(
      trail: trail,
      stepDelta: delta,
      headingDeg: compass.heading,
      magMicroT: _magMagEma,
    );

    final isLost = loc.stdIndex >= _kLostStdThreshold ||
        loc.effectiveSampleSize <
            _kLostEssFraction * _kParticleCountReference;

    if (isLost) {
      _lostStreak++;
      if (_lostStreak >= _kLostFramesRequired && !_lostAnnounced) {
        _state = IndoorTrailReplayState.lost;
        _lostAnnounced = true;
        FieldLogger.instance.logIndoorTrail('lost', data: {
          'std': loc.stdIndex,
          'ess': loc.effectiveSampleSize,
        });
        try {
          onLost?.call();
        } catch (_) {}
        _emitLocalized(
          key: 'trail_lost',
          fallback: 'Trail lost. Stop and reorient.',
          priority: SpeechPriority.warning,
          category: AlertCategory.navigationHint,
          urgency: 0.7,
        );
      }
      return;
    }

    // Recovered from a lost streak: keep going but don't re-announce.
    _lostStreak = 0;
    if (_state == IndoorTrailReplayState.lost) {
      _state = IndoorTrailReplayState.replaying;
      _lostAnnounced = false;
      FieldLogger.instance.logIndoorTrail('recovered');
    }

    if (loc.atDestination) {
      _state = IndoorTrailReplayState.arrived;
      FieldLogger.instance.logIndoorTrail('arrived', data: {'id': trail.id});
      _pollTimer?.cancel();
      _pollTimer = null;
      _detachSensors();
      try {
        onArrived?.call(trail);
      } catch (_) {}
      _emitLocalized(
        key: 'trail_arrived',
        fallback: 'You have arrived at the saved place.',
        priority: SpeechPriority.warning,
        category: AlertCategory.navigationHint,
        urgency: 0.8,
      );
      return;
    }

    final idx = loc.meanIndex.round().clamp(0, trail.sampleCount - 1);
    if (idx == _lastAnnouncedIndex) return;
    _lastAnnouncedIndex = idx;

    _emitNextPrompt(trail, idx);
  }

  void _emitNextPrompt(IndoorTrail trail, int idx) {
    // Determine the next significant heading change ahead of `idx` and
    // verbalise it. We deliberately keep instructions sparse (every
    // 5 steps minimum) to avoid spamming the user.
    final lookahead = math.min(idx + 5, trail.sampleCount - 1);
    if (lookahead == idx) return;

    final current = trail.samples[idx];
    final ahead = trail.samples[lookahead];
    final turnDeg = _angleDiff(ahead.headingDeg, current.headingDeg);
    final stepsLeft = (trail.sampleCount - 1) - idx;

    String key;
    String fallback;
    double urgency;
    if (turnDeg.abs() < 20) {
      key = 'trail_continue_straight';
      fallback = 'Continue straight, $stepsLeft steps left.';
      urgency = 0.3;
    } else if (turnDeg < -20 && turnDeg > -60) {
      key = 'trail_slight_left';
      fallback = 'Slightly left in a few steps.';
      urgency = 0.5;
    } else if (turnDeg > 20 && turnDeg < 60) {
      key = 'trail_slight_right';
      fallback = 'Slightly right in a few steps.';
      urgency = 0.5;
    } else if (turnDeg <= -60) {
      key = 'trail_turn_left';
      fallback = 'Turn left.';
      urgency = 0.65;
    } else {
      key = 'trail_turn_right';
      fallback = 'Turn right.';
      urgency = 0.65;
    }

    var text = S.alert(key);
    if (text == key || text.isEmpty) {
      text = fallback;
    }

    if (current.landmark != null && current.landmark!.isNotEmpty) {
      text = '${current.landmark}. $text';
    }

    onHazard?.call(ExternalHazardEvent(
      source: ExternalHazardSource.indoorTrail,
      text: text,
      priority: SpeechPriority.info,
      category: AlertCategory.navigationHint,
      pan: 0.0,
      urgency: urgency,
      at: DateTime.now(),
      correlationId: '${trail.id}#$idx',
    ));
  }

  void _emitLocalized({
    required String key,
    required String fallback,
    required SpeechPriority priority,
    required AlertCategory category,
    required double urgency,
  }) {
    var text = S.alert(key);
    if (text == key || text.isEmpty) {
      text = fallback;
    }
    onHazard?.call(ExternalHazardEvent(
      source: ExternalHazardSource.indoorTrail,
      text: text,
      priority: priority,
      category: category,
      urgency: urgency,
      at: DateTime.now(),
    ));
  }

  /// Rough particle-count reference matching `ParticleTrailLocalizer`'s
  /// default. The replay layer doesn't read it from the localizer to
  /// keep the abstraction one-directional; used only for the ESS
  /// threshold ratio.
  static const double _kParticleCountReference = 200.0;

  static double _angleDiff(double a, double b) {
    var d = (a - b) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  // -- Test hooks -------------------------------------------------------

  @visibleForTesting
  void debugSetMag(double micros) {
    _magMagEma = micros;
    _hasMag = true;
  }

  @visibleForTesting
  void debugTick() => _tick();
}
