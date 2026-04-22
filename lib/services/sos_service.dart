import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/strings.dart';

enum SosResult {
  sent,
  sentFallback,
  noContact,
  noLocation,
  launchFailed,
  error,
}

class SosService {
  static const String _prefsKey = 'vg_sos_contact';
  static const MethodChannel _smsChannel = MethodChannel('bagdar/sms');

  static const String emergencyFallbackNumber = '112';

  String? _contactNumber;
  Position? _cachedPosition;

  String? get contactNumber => _contactNumber;

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

  Future<SosResult> sendSos({int retries = 1}) async {
    final attemptTargets = <String>[];
    final contact = _contactNumber;
    final hasUserContact = contact != null && contact.isNotEmpty;
    if (hasUserContact) attemptTargets.add(contact);
    attemptTargets.add(emergencyFallbackNumber);

    final position = await _resolvePosition();
    final message = buildMessageText(
      latitude: position?.latitude,
      longitude: position?.longitude,
      positionTimestamp: position?.timestamp,
      accuracyMeters: position?.accuracy,
    );

    
    SosResult last = SosResult.error;
    for (var attempt = 0; attempt <= retries; attempt++) {
      for (var i = 0; i < attemptTargets.length; i++) {
        final target = attemptTargets[i];
        final isFallback = i > 0 || !hasUserContact;
        last = await _tryDeliver(target, message, isFallback: isFallback);
        if (last == SosResult.sent || last == SosResult.sentFallback) {
          final gpsMissing = position == null;
          if (gpsMissing) return SosResult.noLocation;
          return last;
        }
      }
      if (attempt < retries) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
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
  }) {
    final parts = <String>[S.get('sos_message')];

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
    }
    return parts.join(' ');
  }

  static Uri buildSmsUri(String contactNumber, String message) {
    return Uri(
      scheme: 'sms',
      path: _normalizePhoneNumber(contactNumber),
      queryParameters: {'body': message},
    );
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
      return _cachedPosition; 
    }
  }
}
