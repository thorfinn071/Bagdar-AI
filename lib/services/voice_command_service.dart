import 'dart:async';

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
  showHelp,
  sos,
  cancelFall,
  speechRateFaster,
  speechRateSlower,
  volumeUp,
  volumeDown,
  langRussian,
  langKazakh,
  langEnglish,
  batteryStatus,
  tutorialSkip,
  tutorialRepeat,
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
  void Function(String error)? onError;

  static final List<String> _ruSorted = _ruCommands.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  static final List<String> _kkSorted = _kkCommands.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  static final List<String> _enSorted = _enCommands.keys.toList()
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
    'справка': VoiceCommand.showHelp,
    'помощь': VoiceCommand.showHelp,
    'жесты': VoiceCommand.showHelp,
    'подсказка': VoiceCommand.showHelp,
    'что умеешь': VoiceCommand.showHelp,
    'как пользоваться': VoiceCommand.showHelp,
    'быстрее говори': VoiceCommand.speechRateFaster,
    'быстрее': VoiceCommand.speechRateFaster,
    'медленнее говори': VoiceCommand.speechRateSlower,
    'медленнее': VoiceCommand.speechRateSlower,
    'громче': VoiceCommand.volumeUp,
    'тише': VoiceCommand.volumeDown,
    'русский язык': VoiceCommand.langRussian,
    'язык русский': VoiceCommand.langRussian,
    'казахский язык': VoiceCommand.langKazakh,
    'язык казахский': VoiceCommand.langKazakh,
    'английский язык': VoiceCommand.langEnglish,
    'язык английский': VoiceCommand.langEnglish,
    'батарея': VoiceCommand.batteryStatus,
    'заряд': VoiceCommand.batteryStatus,
    'пропусти': VoiceCommand.tutorialSkip,
    'пропустить': VoiceCommand.tutorialSkip,
    'пропустим': VoiceCommand.tutorialSkip,
    'повтори': VoiceCommand.tutorialRepeat,
    'повторить': VoiceCommand.tutorialRepeat,
    'еще раз': VoiceCommand.tutorialRepeat,
    'ещё раз': VoiceCommand.tutorialRepeat,
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
    'отбой',
    'прекрати',
    'я в порядке',
    'всё хорошо',
    'все хорошо',
    'я в норме',
    'ложная тревога',
    'это ошибка',
    'нет проблемы',
    'нет проблем',
    'не случилось',
    'это не падение',
    'ничего не случилось',
    'я не падал',
    'я не упал',
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
    'көмек': VoiceCommand.showHelp,
    'анықтама': VoiceCommand.showHelp,
    'қимылдар': VoiceCommand.showHelp,
    'нұсқау': VoiceCommand.showHelp,
    'жылдамырақ сөйле': VoiceCommand.speechRateFaster,
    'жылдамырақ': VoiceCommand.speechRateFaster,
    'баяуырақ сөйле': VoiceCommand.speechRateSlower,
    'баяуырақ': VoiceCommand.speechRateSlower,
    'қаттырақ': VoiceCommand.volumeUp,
    'ақырынырақ': VoiceCommand.volumeDown,
    'орыс тілі': VoiceCommand.langRussian,
    'қазақ тілі': VoiceCommand.langKazakh,
    'ағылшын тілі': VoiceCommand.langEnglish,
    'батарея': VoiceCommand.batteryStatus,
    'заряд': VoiceCommand.batteryStatus,
    'өткіз': VoiceCommand.tutorialSkip,
    'өткізіп жібер': VoiceCommand.tutorialSkip,
    'қайтала': VoiceCommand.tutorialRepeat,
    'тағы': VoiceCommand.tutorialRepeat,
    'тағы бір рет': VoiceCommand.tutorialRepeat,
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
    'қате',
    'мәселе жоқ',
    'еш нәрсе болмады',
    'мен құламадым',
    'құлаған жоқпын',
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

  static const Map<String, VoiceCommand> _enCommands = {
    'what is around': VoiceCommand.scanAll,
    "what's around": VoiceCommand.scanAll,
    'what is on the left': VoiceCommand.scanLeft,
    "what's on the left": VoiceCommand.scanLeft,
    'what is on the right': VoiceCommand.scanRight,
    "what's on the right": VoiceCommand.scanRight,
    'what is ahead': VoiceCommand.scanForward,
    "what's ahead": VoiceCommand.scanForward,
    'street mode': VoiceCommand.modeStreet,
    'cane mode': VoiceCommand.modeCane,
    'scan mode': VoiceCommand.modeScan,
    'describe': VoiceCommand.scanAll,
    'scan': VoiceCommand.scanAll,
    'left': VoiceCommand.scanLeft,
    'right': VoiceCommand.scanRight,
    'ahead': VoiceCommand.scanForward,
    'forward': VoiceCommand.scanForward,
    'read text': VoiceCommand.readText,
    'read': VoiceCommand.readText,
    'text': VoiceCommand.readText,
    'black screen': VoiceCommand.togglePitchBlackUi,
    'dark screen': VoiceCommand.togglePitchBlackUi,
    'turn off screen': VoiceCommand.togglePitchBlackUi,
    'screen off': VoiceCommand.togglePitchBlackUi,
    'guide dog mode': VoiceCommand.toggleGuideDogMode,
    'guide dog': VoiceCommand.toggleGuideDogMode,
    'mode': VoiceCommand.toggleMode,
    'save place': VoiceCommand.saveWaypoint,
    'save here': VoiceCommand.saveWaypoint,
    'remember place': VoiceCommand.saveWaypoint,
    'i am here': VoiceCommand.saveWaypoint,
    'stop navigation': VoiceCommand.stopNavigation,
    'cancel route': VoiceCommand.stopNavigation,
    'where am i': VoiceCommand.whereAmI,
    'how far': VoiceCommand.navStatus,
    'how much left': VoiceCommand.navStatus,
    'nearest stop': VoiceCommand.nearestStop,
    'closest stop': VoiceCommand.nearestStop,
    'i boarded': VoiceCommand.confirmBoarded,
    'on the bus': VoiceCommand.confirmBoarded,
    'download map': VoiceCommand.downloadMap,
    'load map': VoiceCommand.downloadMap,
    'gestures': VoiceCommand.showHelp,
    'show help': VoiceCommand.showHelp,
    'show gestures': VoiceCommand.showHelp,
    'commands list': VoiceCommand.showHelp,
    'how to use': VoiceCommand.showHelp,
    'what can you do': VoiceCommand.showHelp,
    'speak faster': VoiceCommand.speechRateFaster,
    'faster': VoiceCommand.speechRateFaster,
    'speak slower': VoiceCommand.speechRateSlower,
    'slower': VoiceCommand.speechRateSlower,
    'louder': VoiceCommand.volumeUp,
    'volume up': VoiceCommand.volumeUp,
    'quieter': VoiceCommand.volumeDown,
    'volume down': VoiceCommand.volumeDown,
    'russian language': VoiceCommand.langRussian,
    'kazakh language': VoiceCommand.langKazakh,
    'english language': VoiceCommand.langEnglish,
    'battery': VoiceCommand.batteryStatus,
    'battery level': VoiceCommand.batteryStatus,
    'skip': VoiceCommand.tutorialSkip,
    'skip it': VoiceCommand.tutorialSkip,
    'repeat': VoiceCommand.tutorialRepeat,
    'again': VoiceCommand.tutorialRepeat,
    'one more time': VoiceCommand.tutorialRepeat,
  };

  static const Set<String> _enSosExact = {
    'sos',
    'help',
    'emergency',
    'call for help',
    'call help',
    'call an ambulance',
    'call 911',
    'call 112',
  };

  static const Set<String> _enCancelFallExact = {
    'stop',
    'cancel',
    'abort',
    'i am fine',
    "i'm fine",
    'i am okay',
    "i'm okay",
    'i am ok',
    "i'm ok",
    'false alarm',
    'no problem',
    'no problems',
    'nothing happened',
    "it's a mistake",
    'mistake',
    "i didn't fall",
    'i did not fall',
  };

  static const List<String> _enNavPrefixes = [
    'take me to ',
    'navigate to ',
    'go to ',
    'lead me to ',
    'directions to ',
    'route to ',
  ];

  static const List<String> _enTransitPrefixes = [
    'bus to ',
    'by bus to ',
    'take the bus to ',
    'transit to ',
  ];

  static const List<String> _enBusRoutePrefixes = [
    'bus routes at ',
    'routes at ',
    'buses at ',
    'which buses at ',
  ];

  static const List<String> _enBusSchedulePrefixes = [
    'schedule ',
    'bus schedule ',
    'when does bus ',
    'when is bus ',
  ];

  
  bool _continuous = false;
  DateTime _continuousDeadline = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> init({String locale = 'ru-RU'}) async {
    _locale = locale;
    try {
      _available = await _stt.initialize(
        onError: (e) {
          _setListening(false);
          onError?.call(e.errorMsg);
          _maybeRelistenContinuous();
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _setListening(false);
            _maybeRelistenContinuous();
          }
        },
      );
    } catch (e) {
      _available = false;
    }
    return _available;
  }

  void _maybeRelistenContinuous() {
    if (!_continuous) return;
    if (DateTime.now().isAfter(_continuousDeadline)) {
      _continuous = false;
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!_continuous) return;
      if (_listening) return;
      unawaited(_listenInternal());
    });
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

  Future<bool> startListening({
    Duration listenFor = const Duration(seconds: 6),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    if (!_available) return false;
    if (_listening) return true;

    final hasPerm = await Permission.microphone.isGranted;
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    return _listenInternal(listenFor: listenFor, pauseFor: pauseFor);
  }

  Future<bool> _listenInternal({
    Duration listenFor = const Duration(seconds: 6),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    try {
      await _stt.listen(
        localeId: _locale,
        pauseFor: pauseFor,
        listenFor: listenFor,
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

  Future<bool> startContinuousListening({
    required Duration sessionDuration,
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 5),
  }) async {
    _continuous = true;
    _continuousDeadline = DateTime.now().add(sessionDuration);
    return startListening(listenFor: listenFor, pauseFor: pauseFor);
  }

  Future<void> stopListening() async {
    _continuous = false;
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
    final isEn = _locale.startsWith('en');

    final Set<String> cancelSet;
    final Set<String> sosSet;
    final List<String> navPrefixes;
    final List<String> transitPrefixes;
    final List<String> busRoutePrefixes;
    final List<String> busSchedulePrefixes;
    final Map<String, VoiceCommand> commands;
    final List<String> sorted;
    if (isEn) {
      cancelSet = _enCancelFallExact;
      sosSet = _enSosExact;
      navPrefixes = _enNavPrefixes;
      transitPrefixes = _enTransitPrefixes;
      busRoutePrefixes = _enBusRoutePrefixes;
      busSchedulePrefixes = _enBusSchedulePrefixes;
      commands = _enCommands;
      sorted = _enSorted;
    } else if (isKk) {
      cancelSet = _kkCancelFallExact;
      sosSet = _kkSosExact;
      navPrefixes = _kkNavPrefixes;
      transitPrefixes = _kkTransitPrefixes;
      busRoutePrefixes = _kkBusRoutePrefixes;
      busSchedulePrefixes = _kkBusSchedulePrefixes;
      commands = _kkCommands;
      sorted = _kkSorted;
    } else {
      cancelSet = _ruCancelFallExact;
      sosSet = _ruSosExact;
      navPrefixes = _ruNavPrefixes;
      transitPrefixes = _ruTransitPrefixes;
      busRoutePrefixes = _ruBusRoutePrefixes;
      busSchedulePrefixes = _ruBusSchedulePrefixes;
      commands = _ruCommands;
      sorted = _ruSorted;
    }

    if (cancelSet.contains(lower)) {
      onCommand?.call(VoiceCommand.cancelFall);
      return;
    }
    if (sosSet.contains(lower)) {
      onCommand?.call(VoiceCommand.sos);
      return;
    }

    for (final prefix in navPrefixes) {
      if (lower.startsWith(prefix)) {
        final dest = lower.substring(prefix.length).trim();
        if (dest.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.navigateTo, dest);
          return;
        }
      }
    }

    for (final prefix in transitPrefixes) {
      if (lower.startsWith(prefix)) {
        final dest = lower.substring(prefix.length).trim();
        if (dest.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.transitTo, dest);
          return;
        }
      }
    }

    for (final prefix in busRoutePrefixes) {
      if (lower.startsWith(prefix)) {
        final arg = lower.substring(prefix.length).trim();
        if (arg.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.busRoute, arg);
          return;
        }
      }
    }

    for (final prefix in busSchedulePrefixes) {
      if (lower.startsWith(prefix)) {
        final arg = lower.substring(prefix.length).trim();
        if (arg.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.busSchedule, arg);
          return;
        }
      }
    }

    for (final key in sorted) {
      if (lower.contains(key)) {
        onCommand?.call(commands[key]!);
        return;
      }
    }

    onCommand?.call(VoiceCommand.unknown);
  }

  @visibleForTesting
  void processWordsForTesting(String words, {String? localeOverride}) {
    final saved = _locale;
    if (localeOverride != null) _locale = localeOverride;
    try {
      _processResult(words);
    } finally {
      _locale = saved;
    }
  }
}
