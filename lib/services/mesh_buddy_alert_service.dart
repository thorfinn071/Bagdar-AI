import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';
import '../models/external_hazard.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../utils/alert_filter.dart' show AlertCategory;
import 'device_capability.dart';
import 'field_logger.dart';
import 'sensor_session_coordinator.dart';
import 'settings_service.dart';

/// BLE mesh-net buddy alert payload. PII-free by design.
///
/// Each payload describes one hazard reported by a nearby Bagdar peer:
/// type, severity, approximate location (lat/lon hash or local venue),
/// age, TTL, hop count, and dedupe hash. No account / device identity.
class MeshBuddyPayload {
  final String hazardType;
  final double severity;
  final double? lat;
  final double? lng;
  final int ageMs;
  final int ttl;
  final int hopCount;
  final String dedupeHash;
  final DateTime receivedAt;

  const MeshBuddyPayload({
    required this.hazardType,
    required this.severity,
    required this.ageMs,
    required this.ttl,
    required this.hopCount,
    required this.dedupeHash,
    required this.receivedAt,
    this.lat,
    this.lng,
  });

  factory MeshBuddyPayload.fromBytes(Uint8List data) {
    final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    return MeshBuddyPayload(
      hazardType: json['ht'] as String? ?? 'unknown',
      severity: (json['sv'] as num?)?.toDouble() ?? 0.5,
      lat: (json['la'] as num?)?.toDouble(),
      lng: (json['lo'] as num?)?.toDouble(),
      ageMs: (json['ag'] as num?)?.toInt() ?? 0,
      ttl: (json['tt'] as num?)?.toInt() ?? 3,
      hopCount: (json['hc'] as num?)?.toInt() ?? 0,
      dedupeHash: json['dh'] as String? ?? '',
      receivedAt: DateTime.now(),
    );
  }

  Uint8List toBytes() {
    final map = <String, dynamic>{
      'ht': hazardType,
      'sv': (severity * 100).round() / 100,
      'ag': ageMs,
      'tt': ttl,
      'hc': hopCount,
      'dh': dedupeHash,
      if (lat != null) 'la': (lat! * 10000).round() / 10000,
      if (lng != null) 'lo': (lng! * 10000).round() / 10000,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  bool get isExpired => ttl <= 0 || ageMs > kMeshMaxAgeTtlMs;
  bool get isTooOld => ageMs > kMeshMaxPayloadAgeMs;
}

/// Service that manages BLE peer-network discovery and hazard exchange.
///
/// Phase 2 — Direction 3. Depends on `flutter_blue_plus` or equivalent
/// native `BleBuddyPlugin` for BLE central/peripheral roles. This
/// service does NOT implement the native BLE logic — it relies on a
/// `MethodChannel` (`bagdar/ble_buddy`) whose native side handles
/// advertising, scanning, GATT payload exchange, Android 12+ Bluetooth
/// permissions, and TTL/hop control.
///
/// The service is a pure Dart consumer: it receives parsed payloads,
/// deduplicates, filters by distance/age, and emits soft-prior hazard
/// events through [onHazard] for `AlertManager.handleExternalHazard`.
///
/// Risk gate: disabled automatically if BLE causes battery drain, scan
/// throttling, foreground-service issues, or unreliable permission UX.
/// The app remains fully usable without this service.
class MeshBuddyAlertService {
  MeshBuddyAlertService._();

  static final MeshBuddyAlertService instance = MeshBuddyAlertService._();

  static const MethodChannel _channel = MethodChannel('bagdar/ble_buddy');

  void Function(ExternalHazardEvent event)? onHazard;

  bool _active = false;
  bool _pluginAvailable = false;
  SessionLease? _bleLease;

  final LinkedHashSet<String> _seenHashes = LinkedHashSet<String>();
  final Map<String, DateTime> _lastAnnouncedAt = {};

  bool get isActive => _active;
  bool get isAvailable => _pluginAvailable;

  /// Start BLE buddy discovery. No-op if the feature flag is off, the
  /// device lacks BLE central, or the plugin is not registered.
  Future<bool> start({double? userLat, double? userLng}) async {
    if (_active) return true;
    if (!Settings.instance.meshBuddyAlerts) {
      FieldLogger.instance.logMeshBuddy('start_blocked_flag_off');
      return false;
    }

    try {
      final caps = DeviceCapabilityProbe.cached;
      if (!caps.meshFeasible) {
        FieldLogger.instance.logMeshBuddy('start_blocked_no_ble');
        return false;
      }
    } catch (_) {
      FieldLogger.instance.logMeshBuddy('start_blocked_probe_failed');
      return false;
    }

    final grant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.bluetoothCentral,
      priority: SessionPriority.foregroundFeature,
      owner: 'MeshBuddyAlertService',
    );
    if (!grant.isGranted) {
      FieldLogger.instance.logMeshBuddy('start_blocked_ble_busy', data: {
        'reason': grant.denyReason?.name ?? 'unknown',
      });
      return false;
    }
    _bleLease = grant.lease;

    try {
      final ok = await _channel.invokeMethod<bool>('startBuddyMesh') ?? false;
      if (!ok) {
        SensorSessionCoordinator.instance.release(_bleLease);
        _bleLease = null;
        FieldLogger.instance.logMeshBuddy('start_plugin_failed');
        return false;
      }
      _pluginAvailable = true;
      _active = true;

      _channel.setMethodCallHandler(_handleNativeCall);

      FieldLogger.instance.logMeshBuddy('started');
      return true;
    } on MissingPluginException {
      SensorSessionCoordinator.instance.release(_bleLease);
      _bleLease = null;
      _pluginAvailable = false;
      FieldLogger.instance.logMeshBuddy('start_plugin_missing');
      return false;
    } catch (e) {
      SensorSessionCoordinator.instance.release(_bleLease);
      _bleLease = null;
      FieldLogger.instance.logMeshBuddy('start_error', data: {
        'error': e.toString(),
      });
      return false;
    }
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await _channel.invokeMethod<void>('stopBuddyMesh');
    } catch (_) {}
    SensorSessionCoordinator.instance.release(_bleLease);
    _bleLease = null;
    _seenHashes.clear();
    FieldLogger.instance.logMeshBuddy('stopped');
  }

  void dispose() {
    unawaited(stop());
    _lastAnnouncedAt.clear();
  }

  /// Inject a payload for testing or when received from the native side.
  void handlePayload(MeshBuddyPayload payload) {
    if (!_active) return;
    if (payload.isExpired || payload.isTooOld) {
      FieldLogger.instance.logMeshBuddy('payload_expired', data: {
        'hash': payload.dedupeHash,
        'ageMs': payload.ageMs,
      });
      return;
    }

    if (_seenHashes.contains(payload.dedupeHash)) return;
    _seenHashes.add(payload.dedupeHash);
    if (_seenHashes.length > 200) {
      final toRemove = _seenHashes.take(100).toList();
      _seenHashes.removeAll(toRemove);
    }

    final now = DateTime.now();
    final lastAt = _lastAnnouncedAt[payload.hazardType];
    if (lastAt != null && now.difference(lastAt) < kMeshBuddyCooldown) return;
    _lastAnnouncedAt[payload.hazardType] = now;

    final text = _localizeHazard(payload);
    if (text.isEmpty) return;

    try {
      onHazard?.call(ExternalHazardEvent(
        source: ExternalHazardSource.meshBuddy,
        text: text,
        priority: SpeechPriority.info,
        category: AlertCategory.acousticEvent,
        urgency: (payload.severity * 0.6).clamp(0.0, 0.7),
        at: now,
        correlationId: 'mesh_${payload.dedupeHash}',
      ));
    } catch (e) {
      FieldLogger.instance.logMeshBuddy('emit_error', data: {
        'error': e.toString(),
      });
    }
  }

  String _localizeHazard(MeshBuddyPayload payload) {
    final key = 'mesh_hazard_${payload.hazardType}';
    final text = S.alert(key);
    if (text == key) {
      return S.alert('mesh_hazard_generic');
    }
    return text;
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onBuddyPayload':
        try {
          // Flutter codec: ByteArray → Uint8List; do not change to List<Byte>.
          assert(call.arguments is Uint8List,
              'onBuddyPayload must be Uint8List — do not refactor native side to List<Byte>');
          final data = call.arguments as Uint8List;
          final payload = MeshBuddyPayload.fromBytes(data);
          handlePayload(payload);
        } catch (e) {
          debugPrint('MeshBuddyAlertService: payload parse error: $e');
        }
        break;
      case 'onBuddyError':
        final msg = call.arguments as String? ?? 'unknown';
        FieldLogger.instance.logMeshBuddy('native_error', data: {
          'error': msg,
        });
        if (msg.contains('battery') || msg.contains('throttle')) {
          await stop();
        }
        break;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _seenHashes.clear();
    _lastAnnouncedAt.clear();
    _active = false;
    _pluginAvailable = false;
  }
}
