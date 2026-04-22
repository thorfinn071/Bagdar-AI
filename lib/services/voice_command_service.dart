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
  togglePitchBlackUi,
  toggleGuideDogMode,
  toggleMode,
  saveWaypoint,
  navigateTo,
  transitTo,
  stopNavigation,
  whereAmI,
  navStatus,
  nearestStop,
  confirmBoarded,
  busRoute,
  busSchedule,
  downloadMap,
  sos,
  cancelFall,
  unknown,
}

class VoiceCommandService {
  final SpeechToText _stt = SpeechToText();

  bool _available = false;
  bool _listening = false;

  String _locale = 'ru-RU';

  void Function(VoiceCommand)? onCommand;
  void Function(VoiceCommand cmd, String destination)? onNavCommand;
  void Function(bool listening)? onListeningStateChanged;

  static final List<String> _ruSorted = _ruCommands.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  static final List<String> _kkSorted = _kkCommands.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  static const Map<String, VoiceCommand> _ruCommands = {
    'что вокруг': VoiceCommand.scanAll,
    'что слева': VoiceCommand.scanLeft,
    'что справа': VoiceCommand.scanRight,
    'что впереди': VoiceCommand.scanForward,
    'режим улица': VoiceCommand.modeStreet,
    'режим трость': VoiceCommand.modeCane,
    'режим сканирование': VoiceCommand.modeScan,
    'опиши': VoiceCommand.scanAll,
    'сканируй': VoiceCommand.scanAll,
    'слева': VoiceCommand.scanLeft,
    'справа': VoiceCommand.scanRight,
    'впереди': VoiceCommand.scanForward,
    'прямо': VoiceCommand.scanForward,
    'читай': VoiceCommand.readText,
    'прочитай': VoiceCommand.readText,
    'текст': VoiceCommand.readText,
    'черный экран': VoiceCommand.togglePitchBlackUi,
    'черный режим': VoiceCommand.togglePitchBlackUi,
    'экран черный': VoiceCommand.togglePitchBlackUi,
    'темный экран': VoiceCommand.togglePitchBlackUi,
    'погаси экран': VoiceCommand.togglePitchBlackUi,
    'режим поводыря': VoiceCommand.toggleGuideDogMode,
    'поводырь': VoiceCommand.toggleGuideDogMode,
    'собака поводырь': VoiceCommand.toggleGuideDogMode,
    'режим': VoiceCommand.toggleMode,
    'сохрани место': VoiceCommand.saveWaypoint,
    'я здесь': VoiceCommand.saveWaypoint,
    'запомни место': VoiceCommand.saveWaypoint,
    'стоп навигация': VoiceCommand.stopNavigation,
    'отмена маршрута': VoiceCommand.stopNavigation,
    'где я': VoiceCommand.whereAmI,
    'сколько осталось': VoiceCommand.navStatus,
    'ближайшая остановка': VoiceCommand.nearestStop,
    'я сел': VoiceCommand.confirmBoarded,
    'я в автобусе': VoiceCommand.confirmBoarded,
    'скачай карту': VoiceCommand.downloadMap,
    'скачать карту': VoiceCommand.downloadMap,
    'загрузи карту': VoiceCommand.downloadMap,
  };

  static const Set<String> _ruSosExact = {
    'сос',
    'sos',
    'спасите',
    'помогите срочно',
    'помоги срочно',
    'вызови помощь',
    'вызови скорую',
    'звони сто двенадцать',
    'звони 112',
  };

  static const Set<String> _ruCancelFallExact = {
    'стоп',
    'отмена',
    'отменить',
    'отмени',
    'я в порядке',
    'всё хорошо',
    'все хорошо',
    'я в норме',
    'ложная тревога',
  };

  static const List<String> _ruNavPrefixes = [
    'веди в ',
    'веди меня в ',
    'навигация в ',
    'направь в ',
    'направь меня в ',
    'дорогу к ',
    'дорогу в ',
    'маршрут до ',
    'маршрут в ',
  ];

  static const List<String> _ruTransitPrefixes = [
    'автобус до ',
    'автобус в ',
    'автобусом до ',
    'автобусом в ',
    'транспорт до ',
    'транспортом до ',
    'на автобусе до ',
    'на автобусе в ',
  ];

  static const List<String> _ruBusRoutePrefixes = [
    'маршруты автобуса ',
    'маршрут автобуса ',
    'маршруты на остановке ',
    'какие автобусы на ',
  ];

  static const List<String> _ruBusSchedulePrefixes = [
    'расписание ',
    'расписание автобуса ',
    'когда автобус ',
  ];

  static const Map<String, VoiceCommand> _kkCommands = {
    'айналада не бар': VoiceCommand.scanAll,
    'солда не бар': VoiceCommand.scanLeft,
    'оңда не бар': VoiceCommand.scanRight,
    'алда не бар': VoiceCommand.scanForward,
    'көше режим': VoiceCommand.modeStreet,
    'таяқ режим': VoiceCommand.modeCane,
    'сканерлеу режим': VoiceCommand.modeScan,
    'сипатта': VoiceCommand.scanAll,
    'солда': VoiceCommand.scanLeft,
    'оңда': VoiceCommand.scanRight,
    'алда': VoiceCommand.scanForward,
    'тура': VoiceCommand.scanForward,
    'оқы': VoiceCommand.readText,
    'оқыңыз': VoiceCommand.readText,
    'мәтін': VoiceCommand.readText,
    'қара экран': VoiceCommand.togglePitchBlackUi,
    'қара режим': VoiceCommand.togglePitchBlackUi,
    'экран қара': VoiceCommand.togglePitchBlackUi,
    'экранды өшір': VoiceCommand.togglePitchBlackUi,
    'жолбасшы ит режимі': VoiceCommand.toggleGuideDogMode,
    'жолбасшы ит': VoiceCommand.toggleGuideDogMode,
    'жетекші ит': VoiceCommand.toggleGuideDogMode,
    'режим': VoiceCommand.toggleMode,
    'орынды сақта': VoiceCommand.saveWaypoint,
    'осы жерді сақта': VoiceCommand.saveWaypoint,
    'мен осындамын': VoiceCommand.saveWaypoint,
    'навигацияны тоқтат': VoiceCommand.stopNavigation,
    'маршрутты болдырма': VoiceCommand.stopNavigation,
    'мен қайдамын': VoiceCommand.whereAmI,
    'қанша қалды': VoiceCommand.navStatus,
    'жақын аялдама': VoiceCommand.nearestStop,
    'мен отырдым': VoiceCommand.confirmBoarded,
    'мен автобустамын': VoiceCommand.confirmBoarded,
    'картаны жүкте': VoiceCommand.downloadMap,
    'карта жүктеу': VoiceCommand.downloadMap,
  };

  static const Set<String> _kkSosExact = {
    'сос',
    'sos',
    'жедел көмек',
    'шұғыл көмек',
    '112 ге қоңырау',
    '112 қоңырау',
    'жәрдем шұғыл',
  };

  static const Set<String> _kkCancelFallExact = {
    'тоқта',
    'болдырма',
    'болдырмау',
    'мен жақсымын',
    'мен дұрыспын',
    'жалған дабыл',
  };

  static const List<String> _kkNavPrefixes = [
    'маған жол көрсет ',
    'мені бағытта ',
    'навигация ',
    'маршрут ',
    'жол көрсет ',
  ];

  static const List<String> _kkTransitPrefixes = [
    'автобуспен ',
    'автобус ',
    'көлікпен ',
  ];

  static const List<String> _kkBusRoutePrefixes = [
    'автобус маршруттары ',
    'аялдамадағы маршруттар ',
    'қандай автобустар ',
  ];

  static const List<String> _kkBusSchedulePrefixes = [
    'кесте ',
    'автобус кестесі ',
    'автобус қашан ',
  ];

  
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
  bool get isListening => _listening;

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> startListening() async {
    if (!_available) return false;
    if (_listening) return true;

    final hasPerm = await Permission.microphone.isGranted;
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    try {
      await _stt.listen(
        localeId: _locale,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 6),
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
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
    try {
      await _stt.stop();
    } catch (_) {}
    _setListening(false);
  }

  void dispose() {
    try {
      _stt.cancel();
    } catch (_) {}
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

    final isKk = _locale.startsWith('kk');

    final cancelSet = isKk ? _kkCancelFallExact : _ruCancelFallExact;
    if (cancelSet.contains(lower)) {
      onCommand?.call(VoiceCommand.cancelFall);
      return;
    }
    final sosSet = isKk ? _kkSosExact : _ruSosExact;
    if (sosSet.contains(lower)) {
      onCommand?.call(VoiceCommand.sos);
      return;
    }

    final navPrefixes = isKk ? _kkNavPrefixes : _ruNavPrefixes;
    for (final prefix in navPrefixes) {
      if (lower.startsWith(prefix)) {
        final dest = lower.substring(prefix.length).trim();
        if (dest.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.navigateTo, dest);
          return;
        }
      }
    }

    final transitPrefixes = isKk ? _kkTransitPrefixes : _ruTransitPrefixes;
    for (final prefix in transitPrefixes) {
      if (lower.startsWith(prefix)) {
        final dest = lower.substring(prefix.length).trim();
        if (dest.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.transitTo, dest);
          return;
        }
      }
    }

    final busRoutePrefixes = isKk ? _kkBusRoutePrefixes : _ruBusRoutePrefixes;
    for (final prefix in busRoutePrefixes) {
      if (lower.startsWith(prefix)) {
        final arg = lower.substring(prefix.length).trim();
        if (arg.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.busRoute, arg);
          return;
        }
      }
    }

    final busSchedulePrefixes = isKk
        ? _kkBusSchedulePrefixes
        : _ruBusSchedulePrefixes;
    for (final prefix in busSchedulePrefixes) {
      if (lower.startsWith(prefix)) {
        final arg = lower.substring(prefix.length).trim();
        if (arg.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.busSchedule, arg);
          return;
        }
      }
    }

    final commands = isKk ? _kkCommands : _ruCommands;
    final sorted = isKk ? _kkSorted : _ruSorted;

    for (final key in sorted) {
      if (lower.contains(key)) {
        onCommand?.call(commands[key]!);
        return;
      }
    }

    onCommand?.call(VoiceCommand.unknown);
  }
}
