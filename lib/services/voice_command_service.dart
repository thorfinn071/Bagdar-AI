import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceCommand {
  scanAll,
  scanLeft,
  scanRight,
  scanForward,
  readText,
  modeStreet,
  modeCane,
  modeScan,
  toggleMode,
  saveWaypoint,
  unknown,
}

class VoiceCommandService {
  final SpeechToText _stt = SpeechToText();

  bool _available  = false;
  bool _listening  = false;

  String _locale = 'ru-RU';

  void Function(VoiceCommand)? onCommand;
  void Function(bool listening)? onListeningStateChanged;

  static const Map<String, VoiceCommand> _ruCommands = {
    'что вокруг':           VoiceCommand.scanAll,
    'что слева':            VoiceCommand.scanLeft,
    'что справа':           VoiceCommand.scanRight,
    'что впереди':          VoiceCommand.scanForward,
    'режим улица':          VoiceCommand.modeStreet,
    'режим трость':         VoiceCommand.modeCane,
    'режим сканирование':   VoiceCommand.modeScan,
    'опиши':                VoiceCommand.scanAll,
    'сканируй':             VoiceCommand.scanAll,
    'слева':                VoiceCommand.scanLeft,
    'справа':               VoiceCommand.scanRight,
    'впереди':              VoiceCommand.scanForward,
    'прямо':                VoiceCommand.scanForward,
    'читай':                VoiceCommand.readText,
    'прочитай':             VoiceCommand.readText,
    'текст':                VoiceCommand.readText,
    'режим':                VoiceCommand.toggleMode,
    'сохрани место':        VoiceCommand.saveWaypoint,
    'я здесь':              VoiceCommand.saveWaypoint,
    'запомни место':        VoiceCommand.saveWaypoint,
  };

  static const Map<String, VoiceCommand> _kkCommands = {
    'айналада не бар':      VoiceCommand.scanAll,
    'солда не бар':         VoiceCommand.scanLeft,
    'оңда не бар':          VoiceCommand.scanRight,
    'алда не бар':          VoiceCommand.scanForward,
    'көше режим':           VoiceCommand.modeStreet,
    'таяқ режим':           VoiceCommand.modeCane,
    'сканерлеу режим':      VoiceCommand.modeScan,
    'сипатта':              VoiceCommand.scanAll,
    'солда':                VoiceCommand.scanLeft,
    'оңда':                 VoiceCommand.scanRight,
    'алда':                 VoiceCommand.scanForward,
    'тура':                 VoiceCommand.scanForward,
    'оқы':                  VoiceCommand.readText,
    'оқыңыз':               VoiceCommand.readText,
    'мәтін':                VoiceCommand.readText,
    'режим':                VoiceCommand.toggleMode,
    'орынды сақта':         VoiceCommand.saveWaypoint,
    'осы жерді сақта':      VoiceCommand.saveWaypoint,
    'мен осындамын':        VoiceCommand.saveWaypoint,
  };

  Future<bool> init({String locale = 'ru-RU'}) async {
    _locale = locale;
    try {
      _available = await _stt.initialize(
        onError: (e) {
          _setListening(false);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _setListening(false);
          }
        },
      );
    } catch (e) {
      _available = false;
    }
    return _available;
  }

  void setLocale(String bcp47) {
    _locale = bcp47;
  }

  bool get isAvailable => _available;
  bool get isListening  => _listening;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startListening() async {
    if (!_available)  return false;
    if (_listening)   return true;

    final hasPerm = await Permission.microphone.isGranted;
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    try {
      await _stt.listen(
        localeId:  _locale,
        pauseFor:  const Duration(seconds: 2),
        listenFor: const Duration(seconds: 6),
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError:  true,
        ),
        onResult: (result) {
          if (result.finalResult) {
            _processResult(result.recognizedWords);
          }
        },
      );
      _setListening(true);
      return true;
    } catch (e) {
      _setListening(false);
      return false;
    }
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    try { await _stt.stop(); } catch (_) {}
    _setListening(false);
  }

  void dispose() {
    try { _stt.cancel(); } catch (_) {}
  }

  void _setListening(bool v) {
    if (_listening == v) return;
    _listening = v;
    onListeningStateChanged?.call(v);
  }

  void _processResult(String words) {
    if (words.isEmpty) {
      onCommand?.call(VoiceCommand.unknown);
      return;
    }

    final lower = words.toLowerCase().trim();
    debugPrint('VoiceCommandService recognized: "$lower"');

    final commands = _locale.startsWith('kk')
        ? _kkCommands
        : _ruCommands;

    final sorted = commands.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sorted) {
      if (lower.contains(key)) {
        onCommand?.call(commands[key]!);
        return;
      }
    }

    onCommand?.call(VoiceCommand.unknown);
  }
}
