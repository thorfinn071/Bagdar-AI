import 'dart:async';

import 'package:flutter/foundation.dart';

import 'field_logger.dart';

/// Logical resources owned by exactly one subsystem at a time. The
/// camera-side safety pipeline owns `camera` for the duration of its
/// session and must always be granted priority — the coordinator never
/// returns `false` for camera requests originating from the safety
/// pipeline. All other resources can be denied if a higher-priority
/// owner currently holds the lease.
enum SensorResource {
  /// Microphone capture. Held by `AudioCaptureBroker` while AWM / reverb
  /// classifier / ambient classifier / ASR consume the live mic stream.
  /// FMCW sonar requires exclusive ownership; it cannot share with the
  /// other consumers because chirp playback would pollute their input.
  microphone,

  /// Loudspeaker / TTS audio sink. Held by `TtsService` during speech;
  /// the FMCW sonar prototype must wait for an open speaker before
  /// emitting chirps to avoid stepping on critical alerts.
  speaker,

  /// Camera frame stream. Owned by the safety pipeline. Listed only so
  /// the coordinator can refuse other subsystems (VLM scene Q&A,
  /// passive scan jobs) from claiming the stream.
  camera,

  /// BLE central role (advertise/scan/connect). Mesh-net and OSCP both
  /// want this; on most chipsets only one foreground BLE session is
  /// practical, so requests serialise here.
  bluetoothCentral,

  /// On-device ML model load slot for *optional* large models (VLM,
  /// Whisper-tiny, sonar DSP scratch). Independent of the always-on
  /// YOLO + MiDaS slots, which are not managed here.
  optionalModelSlot,

  /// Long-running training / adapter optimisation jobs. Only one at a
  /// time; gated by charger + Wi-Fi + thermal headroom.
  trainingJob,
}

/// Priorities. The highest priority outstanding request wins. Equal
/// priority requests are first-come-first-served.
enum SessionPriority {
  /// Critical safety subsystems (camera pipeline, SOS audio). Never
  /// preempted.
  safetyCritical,

  /// Active navigation / alerting features (TTS, AWM, ASR command).
  /// Briefly preempts background work but yields to safety.
  foregroundFeature,

  /// Passive on-demand experiments (sonar pre-flight, VLM Q&A). Yields
  /// to anything above.
  optional,

  /// Background maintenance (federated training, log compression).
  /// Yields to everything else and only runs when the device is
  /// charging and idle.
  background,
}

/// Snapshot reasons for a denied request, used by services to log the
/// failure mode without exposing the active holder's identity.
enum SessionDenyReason {
  /// Resource is currently held by a higher- or equal-priority owner.
  alreadyHeld,

  /// Device capability missing or feature flag off — see service log.
  unavailable,

  /// Battery / thermal / memory budget refused the lease at this time.
  budgetExhausted,
}

class SessionLease {
  /// Stable identifier for the granted lease. Used as the argument to
  /// [SensorSessionCoordinator.release].
  final int id;
  final SensorResource resource;
  final SessionPriority priority;
  final String owner;
  final DateTime grantedAt;

  SessionLease._({
    required this.id,
    required this.resource,
    required this.priority,
    required this.owner,
    required this.grantedAt,
  });

  bool get isReleased => _released;
  bool _released = false;

  @override
  String toString() =>
      'SessionLease(id=$id, res=$resource, '
      'prio=$priority, owner=$owner)';
}

class SessionGrant {
  final SessionLease? lease;
  final SessionDenyReason? denyReason;
  final String? denyDetail;

  const SessionGrant.granted(this.lease) : denyReason = null, denyDetail = null;

  const SessionGrant.denied(this.denyReason, [this.denyDetail]) : lease = null;

  bool get isGranted => lease != null;
}

/// Arbitrates mutually-exclusive use of mic, speaker, camera, BLE,
/// optional model slots, and training jobs across the runtime. New
/// growth-direction services (sonar, mesh-net, OSCP, VLM, ASR
/// adaptation, federated training) must route every claim through this
/// coordinator so that, for example, the FMCW sonar prototype can never
/// start chirping while the acoustic world model is listening for
/// dogs, or while TTS is speaking a critical alert.
///
/// The coordinator is intentionally lightweight: it does *not* know how
/// to start or stop any subsystem. Services own their own
/// start/stop/dispose; the coordinator only answers "may I run right
/// now?" and notifies the current holder when a higher-priority caller
/// has preempted them via [preemptions].
class SensorSessionCoordinator {
  SensorSessionCoordinator._();

  static final SensorSessionCoordinator instance = SensorSessionCoordinator._();

  int _nextLeaseId = 1;
  final Map<SensorResource, SessionLease> _active =
      <SensorResource, SessionLease>{};

  final StreamController<SessionLease> _preemptionController =
      StreamController<SessionLease>.broadcast();

  /// Fires when an existing lease has been preempted by a higher-priority
  /// request. Subsystems must stop using the resource immediately on
  /// receipt; failure to do so is a programming error.
  Stream<SessionLease> get preemptions => _preemptionController.stream;

  /// Convenience guard helpers --------------------------------------------

  bool isHeldBy(SensorResource resource, String owner) {
    final lease = _active[resource];
    return lease != null && lease.owner == owner;
  }

  String? currentHolder(SensorResource resource) => _active[resource]?.owner;

  SessionPriority? currentPriority(SensorResource resource) =>
      _active[resource]?.priority;

  /// Request a lease on [resource] at [priority] for [owner]. Returns a
  /// granted lease, or a deny reason. Higher-priority callers preempt
  /// lower-priority holders. Equal-priority requests are denied while
  /// the holder is active.
  SessionGrant request({
    required SensorResource resource,
    required SessionPriority priority,
    required String owner,
  }) {
    final existing = _active[resource];
    if (existing != null) {
      if (existing.owner == owner) {
        return SessionGrant.granted(existing);
      }

      if (priority.index < existing.priority.index) {
        _preempt(existing);
      } else {
        FieldLogger.instance.log('session_denied', {
          'resource': resource.name,
          'owner': owner,
          'priority': priority.name,
          'holder': existing.owner,
          'holderPrio': existing.priority.name,
        });
        return SessionGrant.denied(
          SessionDenyReason.alreadyHeld,
          existing.owner,
        );
      }
    }

    final lease = SessionLease._(
      id: _nextLeaseId++,
      resource: resource,
      priority: priority,
      owner: owner,
      grantedAt: DateTime.now(),
    );
    _active[resource] = lease;
    FieldLogger.instance.log('session_granted', {
      'resource': resource.name,
      'owner': owner,
      'priority': priority.name,
      'leaseId': lease.id,
    });
    return SessionGrant.granted(lease);
  }

  /// Release a lease. Idempotent. Safe to call after the lease has
  /// already been preempted.
  void release(SessionLease? lease) {
    if (lease == null) return;
    final current = _active[lease.resource];
    if (current == null || current.id != lease.id) {
      lease._released = true;
      return;
    }
    _active.remove(lease.resource);
    lease._released = true;
    FieldLogger.instance.log('session_released', {
      'resource': lease.resource.name,
      'owner': lease.owner,
      'leaseId': lease.id,
    });
  }

  /// Force-release every lease. Test-only; production callers should
  /// rely on the natural service-disposal lifecycle.
  @visibleForTesting
  void resetForTesting() {
    for (final lease in _active.values) {
      lease._released = true;
    }
    _active.clear();
  }

  void _preempt(SessionLease lease) {
    lease._released = true;
    _active.remove(lease.resource);
    FieldLogger.instance.log('session_preempted', {
      'resource': lease.resource.name,
      'owner': lease.owner,
      'leaseId': lease.id,
    });
    try {
      _preemptionController.add(lease);
    } catch (e) {
      debugPrint('SensorSessionCoordinator: preemption notify failed: $e');
    }
  }

  /// Dispose the singleton's stream. Intended for tests. Production
  /// hangs onto the singleton for the lifetime of the process.
  @visibleForTesting
  Future<void> disposeForTesting() async {
    resetForTesting();
    await _preemptionController.close();
  }
}
