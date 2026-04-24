import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'device_capability.dart';
import '../models/strings.dart';
import 'settings_service.dart';

class FieldLogger {
  FieldLogger._();
  static final FieldLogger instance = FieldLogger._();

  bool _active = false;
  IOSink? _sink;
  String? _sessionPath;
  int _eventCount = 0;
  final Stopwatch _sessionSw = Stopwatch();

  bool get active => _active;
  String? get sessionPath => _sessionPath;
  int get eventCount => _eventCount;

  Future<void> startSession({
    String? deviceModel,
    int? androidSdk,
    String? depthTier,
    int? batteryPct,
  }) async {
    if (_active) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/bagdar_field_logs');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('${logDir.path}/session_$ts.jsonl');
      _sink = file.openWrite(mode: FileMode.append);
      _sessionPath = file.path;
      _eventCount = 0;
      _sessionSw
        ..reset()
        ..start();
      _active = true;

      log('session_start', {
        'device': deviceModel ?? 'unknown',
        'android': androidSdk ?? 0,
        'depthTier': depthTier ?? 'unknown',
        'language': AppStrings.current.name,
        'guideDog': Settings.instance.guideDogMode,
        'batteryPct': batteryPct ?? -1,
        'buildVersion': '1.0.0+1',
      });
    } catch (e) {
      debugPrint('FieldLogger: failed to start session: $e');
    }
  }

  void log(String event, [Map<String, dynamic>? data]) {
    if (!_active || _sink == null) return;
    final entry = <String, dynamic>{
      'ts': DateTime.now().millisecondsSinceEpoch,
      'elapsed': _sessionSw.elapsedMilliseconds,
      'event': event,
    };
    if (data != null) entry['data'] = data;
    try {
      _sink!.writeln(jsonEncode(entry));
      _eventCount++;
    } catch (_) {}
  }

  void logDetection({
    required int frameCount,
    required int trackCount,
    required int inferenceMs,
    double? maxConf,
  }) {
    log('detection', {
      'frame': frameCount,
      'tracks': trackCount,
      'inferMs': inferenceMs,
      if (maxConf != null) 'maxConf': (maxConf * 100).round(),
    });
  }

  void logTtsSay({
    required String text,
    required String priority,
    double? pan,
    int? trackId,
  }) {
    log('tts_say', {
      'text': text,
      'priority': priority,
      if (pan != null) 'pan': (pan * 100).round() / 100,
      if (trackId != null) 'trackId': trackId,
    });
  }

  void logDepthHazard({
    required String type,
    required double score,
    double? coverage,
  }) {
    log('depth_hazard', {
      'type': type,
      'score': (score * 100).round(),
      if (coverage != null) 'coverage': (coverage * 100).round(),
    });
  }

  void logAeTransition({required bool started, int? frames}) {
    log('ae_transition', {
      'started': started,
      if (frames != null) 'frames': frames,
    });
  }

  void logWeatherGate(String transition, {double? variance, double? avgLuma}) {
    log('weather_gate', {
      'transition': transition,
      if (variance != null) 'variance': variance.round(),
      if (avgLuma != null) 'avgLuma': avgLuma.round(),
    });
  }

  void logIndoorGate(String transition, {double? gpsAccuracy}) {
    log('indoor_gate', {
      'transition': transition,
      if (gpsAccuracy != null) 'gpsAcc': gpsAccuracy.round(),
    });
  }

  void logThermal(String severity, {int? detectIntervalMs}) {
    log('thermal', {
      'severity': severity,
      if (detectIntervalMs != null) 'intervalMs': detectIntervalMs,
    });
  }

  void logLifecycle(String event, {String? resumeType, int? blindMs}) {
    log('lifecycle', {
      'action': event,
      if (resumeType != null) 'resumeType': resumeType,
      if (blindMs != null) 'blindMs': blindMs,
    });
  }

  void logFrozenFrame() => log('frozen_frame');

  void logDroplet({required int dirtyRegions, required bool warned}) {
    log('droplet', {
      'dirty': dirtyRegions,
      'warned': warned,
    });
  }

  void logFpMarker([String? note]) {
    log('fp_marker', {if (note != null && note.isNotEmpty) 'note': note});
  }

  void logFnMarker([String? note]) {
    log('fn_marker', {if (note != null && note.isNotEmpty) 'note': note});
  }

  Future<void> stopSession() async {
    if (!_active) return;
    _sessionSw.stop();
    log('session_end', {
      'totalEvents': _eventCount,
      'durationSec': _sessionSw.elapsedMilliseconds ~/ 1000,
    });
    _active = false;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    debugPrint('FieldLogger: session saved to $_sessionPath '
        '($_eventCount events, ${_sessionSw.elapsedMilliseconds ~/ 1000}s)');
  }
}
