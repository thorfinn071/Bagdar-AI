import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/constants.dart';
import '../../models/strings.dart';

enum SosResult {
  
  sent,
  
  sentFallback,
  
  
  sentWithoutLocation,
  
  noContact,
  
  
  noLocation,
  
  launchFailed,
  
  error,
}

class SosService {
  static const String _prefsKey = 'vg_sos_contact';
  static const MethodChannel _smsChannel = MethodChannel('bagdar/sms');

  static const String emergencyFallbackNumber = '112';

  /// Returns the current step counter total. The H9 fallback uses the
  /// delta between this value at SOS time and the value captured at the
  /// last GPS fix to infer how far the user has walked indoors.
  final int Function()? stepProvider;

  /// Returns the current compass heading in degrees (0–360, 0 = north).
  /// The H9 fallback snapshots this at the last GPS fix so the SMS can
  /// say "+N steps northwest of last known location".
  final double Function()? headingProvider;

  /// Returns an opportunistic snapshot of the device's network context:
  /// `wifiSsid`, `wifiBssid`, `cellId`, `carrier`. Implemented by the
  /// platform layer; missing keys are skipped.
  final Future<Map<String, String>> Function()? networkContextProvider;

  String? _contactNumber;
  Position? _cachedPosition;
  DateTime? _cachedPositionAt;
  int? _stepsAtCachedPosition;
  double? _headingAtCachedPosition;
  String? _plannedDestination;
  Map<String, String>? _lastNetworkContext;
  DateTime? _lastNetworkContextAt;

  Timer? _followUpTimer;
  int _pendingFollowUpCount = 0;

  static const Duration kFollowUpDelay = Duration(seconds: 5);
  static const Duration kNetworkContextMaxAge = Duration(minutes: 10);

  SosService({
    this.stepProvider,
    this.headingProvider,
    this.networkContextProvider,
  });

  String? get contactNumber => _contactNumber;
  String? get plannedDestination => _plannedDestination;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _contactNumber = prefs.getString(_prefsKey);
      debugPrint('SosService: contact=${_contactNumber ?? "not set"}');
    } catch (e) {
      debugPrint('SosService: init error: $e');
    }
  }

  void updateCachedPosition(Position pos) {
    _cachedPosition = pos;
    _cachedPositionAt = DateTime.now();
    _stepsAtCachedPosition = stepProvider?.call();
    _headingAtCachedPosition = headingProvider?.call();
  }

  /// Caches the destination of the active navigation route so that SOS
  /// SMS can include it as a hint when GPS is unavailable (H9). Pass
  /// `null` when the route is cancelled or arrives.
  void setPlannedDestination(String? destination) {
    _plannedDestination = (destination != null && destination.trim().isNotEmpty)
        ? destination.trim()
        : null;
  }

  /// Opportunistically refreshes the cached Wi-Fi / cell-tower fingerprint
  /// used as an SMS fallback locator when GPS is unavailable. Silently
  /// no-ops if the platform did not return anything within `timeout`.
  Future<void> refreshNetworkContext({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final provider = networkContextProvider;
    if (provider == null) return;
    try {
      final snapshot = await provider().timeout(timeout);
      if (snapshot.isNotEmpty) {
        _lastNetworkContext = Map<String, String>.unmodifiable(snapshot);
        _lastNetworkContextAt = DateTime.now();
      }
    } catch (_) {}
  }

  @visibleForTesting
  Map<String, String>? get cachedNetworkContextForTesting => _lastNetworkContext;

  @visibleForTesting
  void setCachedNetworkContextForTesting(Map<String, String>? ctx) {
    _lastNetworkContext = ctx == null ? null : Map<String, String>.unmodifiable(ctx);
    _lastNetworkContextAt = ctx == null ? null : DateTime.now();
  }

  Future<bool> setContact(String phoneNumber) async {
    final cleaned = phoneNumber.trim();
    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      debugPrint('SosService: invalid phone number "$phoneNumber"');
      return false;
    }
    _contactNumber = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, cleaned);
    debugPrint('SosService: contact set to $cleaned');
    return true;
  }

  Future<SosResult> sendSos({int retries = kSosRetries}) async {
    final attemptTargets = <String>[];
    final contact = _contactNumber;
    final hasUserContact = contact != null && contact.isNotEmpty;
    if (hasUserContact) attemptTargets.add(contact);
    attemptTargets.add(emergencyFallbackNumber);

    final position = await _resolvePosition();
    if (position == null) {
      await refreshNetworkContext();
    }
    final fallback = _buildFallbackContext(positionMissing: position == null);
    final message = buildMessageText(
      latitude: position?.latitude,
      longitude: position?.longitude,
      positionTimestamp: position?.timestamp,
      accuracyMeters: position?.accuracy,
      plannedDestination: fallback.plannedDestination,
      networkContext: fallback.networkContext,
      stepsFromLastFix: fallback.stepsFromLastFix,
      headingFromLastFix: fallback.headingFromLastFix,
    );

    
    SosResult last = SosResult.error;
    for (var attempt = 0; attempt <= retries; attempt++) {
      for (var i = 0; i < attemptTargets.length; i++) {
        final target = attemptTargets[i];
        final isFallback = i > 0 || !hasUserContact;
        last = await _tryDeliver(target, message, isFallback: isFallback);
        if (last == SosResult.sent || last == SosResult.sentFallback) {
          
          
          final gpsMissing = position == null;
          if (gpsMissing) return SosResult.sentWithoutLocation;
          return last;
        }
      }
      if (attempt < retries) {
        await Future.delayed(kSosRetryDelay);
      }
    }
    final callTarget = hasUserContact ? contact : emergencyFallbackNumber;
    try {
      final launched = await launchUrl(
        buildTelUri(callTarget),
        mode: LaunchMode.externalApplication,
      );
      if (launched) {
        return hasUserContact ? SosResult.sent : SosResult.sentFallback;
      }
    } catch (_) {}
    return last;
  }

  Future<SosResult> _tryDeliver(
    String target,
    String message, {
    required bool isFallback,
  }) async {
    try {
      final directSent = await _sendSmsDirect(target, message);
      if (directSent) {
        debugPrint(
          'SosService: delivered to $target via native SMS'
          '${isFallback ? " (fallback)" : ""}',
        );
        return isFallback ? SosResult.sentFallback : SosResult.sent;
      }
      final launched = await launchUrl(
        buildSmsUri(target, message),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint('SosService: launchUrl failed for $target');
        return SosResult.launchFailed;
      }
      return isFallback ? SosResult.sentFallback : SosResult.sent;
    } catch (e) {
      debugPrint('SosService: delivery error to $target: $e');
      return SosResult.error;
    }
  }

  static String buildMessageText({
    double? latitude,
    double? longitude,
    DateTime? positionTimestamp,
    double? accuracyMeters,
    String? preamble,
    String? plannedDestination,
    Map<String, String>? networkContext,
    int? stepsFromLastFix,
    double? headingFromLastFix,
  }) {
    final parts = <String>[];
    if (preamble != null && preamble.isNotEmpty) parts.add(preamble);
    parts.add(S.get('sos_message'));

    if (latitude != null && longitude != null) {
      final lat = latitude.toStringAsFixed(6);
      final lng = longitude.toStringAsFixed(6);
      parts.add('https://maps.google.com/?q=$lat,$lng');

      if (positionTimestamp != null) {
        final ageMin = DateTime.now().difference(positionTimestamp).inMinutes;
        if (ageMin >= 2) {
          parts.add(
            '${S.get('sos_position_stale')} $ageMin '
            '${S.get('sos_position_unit_min')}',
          );
        }
      }
      if (accuracyMeters != null && accuracyMeters > 0) {
        parts.add('±${accuracyMeters.round()}m');
      }
    } else {
      parts.add('(${S.get('sos_no_gps')})');
      if (stepsFromLastFix != null && stepsFromLastFix > 0) {
        final dirKey = headingFromLastFix == null
            ? null
            : _cardinalKey(headingFromLastFix);
        final dir = dirKey == null ? '' : ' ${S.get(dirKey)}';
        parts.add(
          '+$stepsFromLastFix ${S.get('sos_steps_from_last')}$dir '
          '${S.get('sos_of_last_known')}',
        );
      }
    }

    if (plannedDestination != null && plannedDestination.isNotEmpty) {
      parts.add('${S.get('sos_planned_destination')} $plannedDestination');
    }

    if (networkContext != null && networkContext.isNotEmpty) {
      final ssid = networkContext['wifiSsid'];
      final bssid = networkContext['wifiBssid'];
      final cellId = networkContext['cellId'];
      final carrier = networkContext['carrier'];
      if (ssid != null && ssid.isNotEmpty) {
        final bssidSuffix = (bssid != null && bssid.isNotEmpty)
            ? ' ($bssid)'
            : '';
        parts.add('${S.get('sos_near_wifi')} $ssid$bssidSuffix');
      } else if (bssid != null && bssid.isNotEmpty) {
        parts.add('${S.get('sos_near_wifi')} $bssid');
      }
      if (cellId != null && cellId.isNotEmpty) {
        final carrierPrefix = (carrier != null && carrier.isNotEmpty)
            ? '$carrier '
            : '';
        parts.add('${S.get('sos_near_cell')} $carrierPrefix$cellId');
      } else if (carrier != null && carrier.isNotEmpty) {
        parts.add('${S.get('sos_near_cell')} $carrier');
      }
    }

    return parts.join(' ');
  }

  static const List<String> _cardinalKeys = [
    'sos_dir_n',
    'sos_dir_ne',
    'sos_dir_e',
    'sos_dir_se',
    'sos_dir_s',
    'sos_dir_sw',
    'sos_dir_w',
    'sos_dir_nw',
  ];

  static String _cardinalKey(double bearingDeg) {
    final normalized = ((bearingDeg % 360) + 360) % 360;
    final idx = (((normalized + 22.5) / 45).floor()) % 8;
    return _cardinalKeys[idx];
  }

  _FallbackContext _buildFallbackContext({required bool positionMissing}) {
    String? destination = _plannedDestination;
    Map<String, String>? network;
    int? steps;
    double? heading;
    if (positionMissing) {
      final ctx = _lastNetworkContext;
      final ctxAt = _lastNetworkContextAt;
      if (ctx != null && ctxAt != null) {
        final age = DateTime.now().difference(ctxAt);
        if (age <= kNetworkContextMaxAge) {
          network = ctx;
        }
      }
      final stepsNow = stepProvider?.call();
      if (stepsNow != null && _stepsAtCachedPosition != null) {
        final delta = stepsNow - _stepsAtCachedPosition!;
        if (delta > 0) steps = delta;
      }
      heading = _headingAtCachedPosition;
    }
    return _FallbackContext(
      plannedDestination: destination,
      networkContext: network,
      stepsFromLastFix: steps,
      headingFromLastFix: heading,
    );
  }

  static Uri buildSmsUri(String contactNumber, String message) {
    return Uri(
      scheme: 'sms',
      path: _normalizePhoneNumber(contactNumber),
      queryParameters: {'body': message},
    );
  }

  static Uri buildTelUri(String contactNumber) {
    return Uri(scheme: 'tel', path: _normalizePhoneNumber(contactNumber));
  }

  static String _normalizePhoneNumber(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  Future<bool> _sendSmsDirect(String contact, String message) async {
    if (!_isAndroid) {
      return false;
    }

    try {
      final currentStatus = await Permission.sms.status;
      final granted =
          currentStatus.isGranted || (await Permission.sms.request()).isGranted;
      if (!granted) {
        debugPrint('SosService: SMS permission denied');
        return false;
      }

      final sent = await _smsChannel.invokeMethod<bool>('sendSms', {
        'phoneNumber': _normalizePhoneNumber(contact),
        'message': message,
      });
      if (sent == true) {
        debugPrint('SosService: sendSms completed via native channel');
        return true;
      }
      debugPrint('SosService: native sendSms returned false');
      return false;
    } on PlatformException catch (e) {
      debugPrint('SosService: native sendSms failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('SosService: native sendSms error: $e');
      return false;
    }
  }

  /// Schedules a follow-up SMS to be sent shortly (after [kFollowUpDelay]) so
  /// it lands after the primary SOS. Each call increments the queued-fall
  /// counter; a single SMS goes out summarising the count. Used by the H7
  /// second-fall-during-SOS-lockout flow in `FallDetector`.
  void queueFollowUpFall() {
    _pendingFollowUpCount++;
    if (_followUpTimer?.isActive == true) return;
    _followUpTimer = Timer(kFollowUpDelay, _flushFollowUp);
  }

  /// Cancels any queued follow-up SMS. Called by the host on cleanup or when
  /// the user explicitly silences SOS handling.
  void cancelQueuedFollowUp() {
    _followUpTimer?.cancel();
    _followUpTimer = null;
    _pendingFollowUpCount = 0;
  }

  bool get hasQueuedFollowUp => (_followUpTimer?.isActive ?? false);
  int get pendingFollowUpCount => _pendingFollowUpCount;

  Future<void> _flushFollowUp() async {
    final count = _pendingFollowUpCount;
    _pendingFollowUpCount = 0;
    _followUpTimer = null;
    if (count == 0) return;
    final position = await _resolvePosition();
    if (position == null) {
      await refreshNetworkContext();
    }
    final fallback = _buildFallbackContext(positionMissing: position == null);
    final base = S.get('sos_user_fallen_again');
    final preamble = count == 1 ? base : '$base (×$count)';
    final message = buildMessageText(
      latitude: position?.latitude,
      longitude: position?.longitude,
      positionTimestamp: position?.timestamp,
      accuracyMeters: position?.accuracy,
      preamble: preamble,
      plannedDestination: fallback.plannedDestination,
      networkContext: fallback.networkContext,
      stepsFromLastFix: fallback.stepsFromLastFix,
      headingFromLastFix: fallback.headingFromLastFix,
    );
    final contact = _contactNumber;
    final hasUserContact = contact != null && contact.isNotEmpty;
    final target = hasUserContact ? contact : emergencyFallbackNumber;
    try {
      await _tryDeliver(target, message, isFallback: !hasUserContact);
    } catch (e) {
      debugPrint('SosService: follow-up SMS delivery error: $e');
    }
  }

  Future<Position?> _resolvePosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return lastKnown;
        }
      } catch (_) {}
      final cached = _cachedPosition;
      final cachedAt = _cachedPositionAt;
      if (cached == null || cachedAt == null) {
        return null;
      }
      if (DateTime.now().difference(cachedAt) > kSosCachedPositionMaxAge) {
        return null;
      }
      return cached;
    }
  }
}

class _FallbackContext {
  final String? plannedDestination;
  final Map<String, String>? networkContext;
  final int? stepsFromLastFix;
  final double? headingFromLastFix;

  const _FallbackContext({
    required this.plannedDestination,
    required this.networkContext,
    required this.stepsFromLastFix,
    required this.headingFromLastFix,
  });
}
