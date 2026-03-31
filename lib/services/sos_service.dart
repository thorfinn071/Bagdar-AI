import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/strings.dart';

enum SosResult { sent, noContact, noLocation, launchFailed, error }

class SosService {
  static const String _prefsKey = 'vg_sos_contact';

  String? _contactNumber;

  String? get contactNumber => _contactNumber;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _contactNumber = prefs.getString(_prefsKey);
      debugPrint('SosService: contact=${_contactNumber ?? "not set"}');
    } catch (e) {
      debugPrint('SosService: init error: $e');
    }
  }

  Future<bool> setContact(String phoneNumber) async {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      debugPrint('SosService: invalid phone number "$phoneNumber"');
      return false;
    }
    _contactNumber = phoneNumber;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, phoneNumber);
    debugPrint('SosService: contact set to $phoneNumber');
    return true;
  }

  Future<SosResult> sendSos() async {
    if (_contactNumber == null || _contactNumber!.isEmpty) {
      return SosResult.noContact;
    }

    String message;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {}

      if (position != null) {
        final lat = position.latitude;
        final lng = position.longitude;
        final mapsUrl = 'https://maps.google.com/?q=$lat,$lng';
        message = '${S.get('sos_message')} $mapsUrl';
      } else {
        message = '${S.get('sos_message')} (${S.get('sos_no_gps')})';
      }

      final smsUri = Uri(
        scheme: 'sms',
        path: _contactNumber,
        queryParameters: {'body': message},
      );

      final launched = await launchUrl(smsUri);
      if (!launched) {
        debugPrint('SosService: launchUrl returned false — SMS app not opened');
        return SosResult.launchFailed;
      }
      debugPrint('SosService: SOS sent to $_contactNumber'
          '${position == null ? " (no GPS)" : ""}');
      return SosResult.sent;
    } catch (e) {
      debugPrint('SosService: sendSos error: $e');
      return SosResult.error;
    }
  }
}
