import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/language_pack.dart';
import 'field_logger.dart';
import 'language_pack_manager.dart';
import 'settings_service.dart';
import 'voice_adaptation_store.dart';
import 'vosk_kk_recognizer.dart';

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
  togglePaymentSms,
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
  verbosityMinimal,
  verbosityNormal,
  verbosityDetailed,
  alertsRare,
  alertsNormal,
  alertsFrequent,
  sosTriggerTripleTap,
  sosTriggerShake,
  hapticStrong,
  hapticWeak,
  settingsHelp,
  tutorialSkip,
  tutorialRepeat,
  rememberObject,
  findObject,
  cancelFind,
  forgetObject,
  restartPipeline,
  themeDark,
  themeLight,
  themeHighContrast,
  themeWarm,
  manageLanguagePacks,
  enableKkV2,
  disableKkV2,

  recordTrail,
  replayTrail,
  stopTrailRecord,
  addTrailLandmark,
  deleteTrail,

  toggleBazaarMode,
  toggleLivestockMode,

  toggleVoiceAdaptation,
  clearAdaptationData,

  toggleMeshBuddy,

  recordNearMiss,

  toggleSonar,
  dominantHandRight,
  dominantHandLeft,
  allowPermission,
  confirm,
  cancel,
  back,
  unknown,
}

class VoiceCommandService {
  final SpeechToText _stt = SpeechToText();
  final VoskKkRecognizer _vosk = VoskKkRecognizer.instance;

  bool _available = false;
  bool _listening = false;
  bool _hadResult = false;

  /// Active when the Kazakh stack v2 feature flag is on, the current locale
  /// is kk-*, and the vosk-kk language pack is installed locally. When true,
  /// `_listenInternal` routes through `_vosk` instead of `speech_to_text`.
  bool _useVoskForKk = false;

  /// Latest async reconciliation in flight; used to avoid stacked swaps when
  /// `setLocale` is called rapidly.
  Future<void>? _reconcileFuture;

  String _locale = 'ru-RU';

  void Function(VoiceCommand)? onCommand;
  void Function(VoiceCommand cmd, String destination)? onNavCommand;
  void Function(bool listening)? onListeningStateChanged;
  void Function(String error)? onError;
  VoidCallback? onListenDone;

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
    'включи платежи': VoiceCommand.togglePaymentSms,
    'выключи платежи': VoiceCommand.togglePaymentSms,
    'платежные уведомления': VoiceCommand.togglePaymentSms,
    'уведомления о платежах': VoiceCommand.togglePaymentSms,
    'смс платежи': VoiceCommand.togglePaymentSms,
    'платежи': VoiceCommand.togglePaymentSms,
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
    'минимальная подробность': VoiceCommand.verbosityMinimal,
    'обычная подробность': VoiceCommand.verbosityNormal,
    'детальная подробность': VoiceCommand.verbosityDetailed,
    'редкие алерты': VoiceCommand.alertsRare,
    'обычные алерты': VoiceCommand.alertsNormal,
    'частые алерты': VoiceCommand.alertsFrequent,
    'изменить sos на тройной тап': VoiceCommand.sosTriggerTripleTap,
    'изменить sos на встряхивание': VoiceCommand.sosTriggerShake,
    'сильная вибрация': VoiceCommand.hapticStrong,
    'слабая вибрация': VoiceCommand.hapticWeak,
    'помоги с настройками': VoiceCommand.settingsHelp,
    'пропусти': VoiceCommand.tutorialSkip,
    'пропустить': VoiceCommand.tutorialSkip,
    'пропустим': VoiceCommand.tutorialSkip,
    'повтори': VoiceCommand.tutorialRepeat,
    'повторить': VoiceCommand.tutorialRepeat,
    'еще раз': VoiceCommand.tutorialRepeat,
    'ещё раз': VoiceCommand.tutorialRepeat,
    'перезапусти распознавание': VoiceCommand.restartPipeline,
    'перезапусти': VoiceCommand.restartPipeline,
    'сбрось': VoiceCommand.restartPipeline,
    'тёмная тема': VoiceCommand.themeDark,
    'темная тема': VoiceCommand.themeDark,
    'светлая тема': VoiceCommand.themeLight,
    'высокий контраст': VoiceCommand.themeHighContrast,
    'тёплая тема': VoiceCommand.themeWarm,
    'теплая тема': VoiceCommand.themeWarm,
    'языковые пакеты': VoiceCommand.manageLanguagePacks,
    'управление пакетами': VoiceCommand.manageLanguagePacks,
    'управление языками': VoiceCommand.manageLanguagePacks,
    'настройки языков': VoiceCommand.manageLanguagePacks,
    'включи улучшенное распознавание': VoiceCommand.enableKkV2,
    'улучшенное распознавание': VoiceCommand.enableKkV2,
    'новое казахское распознавание': VoiceCommand.enableKkV2,
    'выключи улучшенное распознавание': VoiceCommand.disableKkV2,
    'обычное казахское распознавание': VoiceCommand.disableKkV2,
    'старое распознавание': VoiceCommand.disableKkV2,

    'стоп маршрут': VoiceCommand.stopTrailRecord,
    'остановить маршрут': VoiceCommand.stopTrailRecord,
    'стоп запись маршрута': VoiceCommand.stopTrailRecord,

    'режим базар': VoiceCommand.toggleBazaarMode,
    'базарный режим': VoiceCommand.toggleBazaarMode,
    'режим рынок': VoiceCommand.toggleBazaarMode,
    'режим животные': VoiceCommand.toggleLivestockMode,
    'режим скот': VoiceCommand.toggleLivestockMode,

    'адаптация голоса': VoiceCommand.toggleVoiceAdaptation,
    'включи адаптацию': VoiceCommand.toggleVoiceAdaptation,
    'выключи адаптацию': VoiceCommand.toggleVoiceAdaptation,
    'удалить данные адаптации': VoiceCommand.clearAdaptationData,
    'очистить адаптацию': VoiceCommand.clearAdaptationData,

    'сеть помощников': VoiceCommand.toggleMeshBuddy,
    'режим помощников': VoiceCommand.toggleMeshBuddy,
    'меш сеть': VoiceCommand.toggleMeshBuddy,

    'опасная ситуация': VoiceCommand.recordNearMiss,
    'записать опасность': VoiceCommand.recordNearMiss,
    'было опасно': VoiceCommand.recordNearMiss,

    'эхолот': VoiceCommand.toggleSonar,
    'режим эхолота': VoiceCommand.toggleSonar,
    'сонар': VoiceCommand.toggleSonar,
    'правая': VoiceCommand.dominantHandRight,
    'правая рука': VoiceCommand.dominantHandRight,
    'правша': VoiceCommand.dominantHandRight,
    'левая': VoiceCommand.dominantHandLeft,
    'левая рука': VoiceCommand.dominantHandLeft,
    'левша': VoiceCommand.dominantHandLeft,
    'улица': VoiceCommand.modeStreet,
    'трость': VoiceCommand.modeCane,
    'сканирование': VoiceCommand.modeScan,
    'разрешить': VoiceCommand.allowPermission,
    'разреши': VoiceCommand.allowPermission,
    'да': VoiceCommand.confirm,
    'нет': VoiceCommand.cancel,
    'назад': VoiceCommand.back,
    'русский': VoiceCommand.langRussian,
    'казахский': VoiceCommand.langKazakh,
    'английский': VoiceCommand.langEnglish,
    'қазақша': VoiceCommand.langKazakh,
    'қазақ': VoiceCommand.langKazakh,
    'қазақ тілі': VoiceCommand.langKazakh,
    'казакша': VoiceCommand.langKazakh,
    'казак тили': VoiceCommand.langKazakh,
    'казак': VoiceCommand.langKazakh,
    'орысша': VoiceCommand.langRussian,
    'орыс': VoiceCommand.langRussian,
    'орыс тілі': VoiceCommand.langRussian,
    'english': VoiceCommand.langEnglish,
    'инглиш': VoiceCommand.langEnglish,
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

  static const List<String> _ruRecordTrailPrefixes = [
    'запиши маршрут до ',
    'запиши маршрут в ',
    'запиши путь до ',
    'запиши путь в ',
    'запомни маршрут до ',
    'запомни маршрут в ',
    'запомни путь до ',
  ];

  static const List<String> _ruReplayTrailPrefixes = [
    'веди по маршруту ',
    'веди по маршруту до ',
    'повтори маршрут до ',
    'повтори маршрут ',
    'маршрут внутри до ',
    'маршрут внутри ',
  ];

  static const List<String> _ruLandmarkPrefixes = [
    'ориентир ',
    'отметка ',
    'точка ',
  ];

  static const List<String> _ruDeleteTrailPrefixes = [
    'удали маршрут ',
    'удалить маршрут ',
    'забудь маршрут ',
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

  static const List<String> _ruRememberPrefixes = [
    'запомни этот ',
    'запомни эту ',
    'запомни эта ',
    'запомни эти ',
    'запомни мои ',
    'запомни мой ',
    'запомни моя ',
    'запомни мою ',
    'запомни моё ',
    'запомни мое ',
    'запомни ',
  ];

  static const List<String> _ruFindPrefixes = [
    'найди мои ',
    'найди мой ',
    'найди моя ',
    'найди мою ',
    'найди моё ',
    'найди мое ',
    'найди ',
    'ищи ',
    'где мои ',
    'где мой ',
    'где моя ',
    'где мою ',
    'где моё ',
    'где мое ',
  ];

  static const List<String> _ruForgetPrefixes = [
    'забудь мои ',
    'забудь мой ',
    'забудь моя ',
    'забудь мою ',
    'забудь моё ',
    'забудь мое ',
    'забудь ',
    'удали ',
  ];

  static const Set<String> _ruCancelFindExact = {
    'прекрати поиск',
    'стоп поиск',
    'стоп поиска',
    'отмена поиска',
    'отмени поиск',
    'хватит искать',
    'прекрати искать',
  };

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
    'төлемдерді қос': VoiceCommand.togglePaymentSms,
    'төлемдерді өшір': VoiceCommand.togglePaymentSms,
    'төлем хабарламасы': VoiceCommand.togglePaymentSms,
    'смс төлем': VoiceCommand.togglePaymentSms,
    'төлемдер': VoiceCommand.togglePaymentSms,
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
    'қысқа толықтық': VoiceCommand.verbosityMinimal,
    'қалыпты толықтық': VoiceCommand.verbosityNormal,
    'толық толықтық': VoiceCommand.verbosityDetailed,
    'сирек ескертулер': VoiceCommand.alertsRare,
    'қалыпты ескертулер': VoiceCommand.alertsNormal,
    'жиі ескертулер': VoiceCommand.alertsFrequent,
    'sos үш рет түрту': VoiceCommand.sosTriggerTripleTap,
    'sos сілку': VoiceCommand.sosTriggerShake,
    'күшті діріл': VoiceCommand.hapticStrong,
    'әлсіз діріл': VoiceCommand.hapticWeak,
    'баптауларға көмектес': VoiceCommand.settingsHelp,
    'өткіз': VoiceCommand.tutorialSkip,
    'өткізіп жібер': VoiceCommand.tutorialSkip,
    'қайтала': VoiceCommand.tutorialRepeat,
    'тағы': VoiceCommand.tutorialRepeat,
    'тағы бір рет': VoiceCommand.tutorialRepeat,
    'тануды қайта қос': VoiceCommand.restartPipeline,
    'қайта қосу': VoiceCommand.restartPipeline,
    'қайта бастау': VoiceCommand.restartPipeline,
    'қара тақырып': VoiceCommand.themeDark,
    'ашық тақырып': VoiceCommand.themeLight,
    'жоғары контраст': VoiceCommand.themeHighContrast,
    'жылы тақырып': VoiceCommand.themeWarm,
    'тіл пакеттері': VoiceCommand.manageLanguagePacks,
    'пакеттерді басқару': VoiceCommand.manageLanguagePacks,
    'тіл басқару': VoiceCommand.manageLanguagePacks,
    'жетілдірілген тану': VoiceCommand.enableKkV2,
    'жаңа қазақша тану': VoiceCommand.enableKkV2,
    'қарапайым қазақша тану': VoiceCommand.disableKkV2,
    'ескі тану': VoiceCommand.disableKkV2,

    'маршрутты тоқтат': VoiceCommand.stopTrailRecord,
    'жазуды тоқтат': VoiceCommand.stopTrailRecord,

    'базар режимі': VoiceCommand.toggleBazaarMode,
    'нарық режимі': VoiceCommand.toggleBazaarMode,
    'мал режимі': VoiceCommand.toggleLivestockMode,
    'жануарлар режимі': VoiceCommand.toggleLivestockMode,

    'дауыс бейімдеу': VoiceCommand.toggleVoiceAdaptation,
    'бейімдеу деректерін жою': VoiceCommand.clearAdaptationData,

    'көмекшілер желісі': VoiceCommand.toggleMeshBuddy,
    'көмекшілер режимі': VoiceCommand.toggleMeshBuddy,

    'қауіпті жағдай': VoiceCommand.recordNearMiss,
    'қауіпті жаз': VoiceCommand.recordNearMiss,

    'эхолот': VoiceCommand.toggleSonar,
    'эхолот режимі': VoiceCommand.toggleSonar,
    'сонар': VoiceCommand.toggleSonar,
    'оң': VoiceCommand.dominantHandRight,
    'оң қол': VoiceCommand.dominantHandRight,
    'оңқай': VoiceCommand.dominantHandRight,
    'сол': VoiceCommand.dominantHandLeft,
    'сол қол': VoiceCommand.dominantHandLeft,
    'солқай': VoiceCommand.dominantHandLeft,
    'көше': VoiceCommand.modeStreet,
    'таяқ': VoiceCommand.modeCane,
    'сканерлеу': VoiceCommand.modeScan,
    'рұқсат': VoiceCommand.allowPermission,
    'рұқсат ету': VoiceCommand.allowPermission,
    'иә': VoiceCommand.confirm,
    'жоқ': VoiceCommand.cancel,
    'артқа': VoiceCommand.back,
    'орыс': VoiceCommand.langRussian,
    'орысша': VoiceCommand.langRussian,
    'русский': VoiceCommand.langRussian,
    'русский язык': VoiceCommand.langRussian,
    'қазақ': VoiceCommand.langKazakh,
    'қазақша': VoiceCommand.langKazakh,
    'ағылшын': VoiceCommand.langEnglish,
    'english': VoiceCommand.langEnglish,
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
    'мен жақсымын',
    'мен дұрыспын',
    'жалған дабыл',
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

  static const List<String> _kkRecordTrailPrefixes = [
    'маршрутты жаз ',
    'жолды жаз ',
    'маршрутты есте сақта ',
  ];

  static const List<String> _kkReplayTrailPrefixes = [
    'маршрутпен жүр ',
    'маршрутты қайтала ',
    'ішкі маршрут ',
  ];

  static const List<String> _kkLandmarkPrefixes = ['белгі ', 'нүкте '];

  static const List<String> _kkDeleteTrailPrefixes = [
    'маршрутты жой ',
    'маршрутты өшір ',
  ];

  static const List<String> _kkRememberPrefixes = [
    'есте сақтап қой ',
    'есте сақта ',
    'есте сақтап ',
  ];

  static const List<String> _kkFindPrefixes = [
    'қайда менің ',
    'қайда мені ',
    'ізде ',
    'тап ',
  ];

  static const List<String> _kkForgetPrefixes = ['ұмыт ', 'жой ', 'өшір '];

  static const Set<String> _kkCancelFindExact = {
    'іздеуді тоқтат',
    'іздеу тоқта',
    'іздеуді тоқтатыңыз',
    'іздеуді доғар',
    'іздеу бас тарт',
  };

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
    'enable payments': VoiceCommand.togglePaymentSms,
    'disable payments': VoiceCommand.togglePaymentSms,
    'payment notifications': VoiceCommand.togglePaymentSms,
    'payment sms': VoiceCommand.togglePaymentSms,
    'sms payments': VoiceCommand.togglePaymentSms,
    'payments': VoiceCommand.togglePaymentSms,
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
    'minimal verbosity': VoiceCommand.verbosityMinimal,
    'normal verbosity': VoiceCommand.verbosityNormal,
    'detailed verbosity': VoiceCommand.verbosityDetailed,
    'rare alerts': VoiceCommand.alertsRare,
    'normal alerts': VoiceCommand.alertsNormal,
    'frequent alerts': VoiceCommand.alertsFrequent,
    'set sos to triple tap': VoiceCommand.sosTriggerTripleTap,
    'set sos to shake': VoiceCommand.sosTriggerShake,
    'strong vibration': VoiceCommand.hapticStrong,
    'weak vibration': VoiceCommand.hapticWeak,
    'help with settings': VoiceCommand.settingsHelp,
    'skip': VoiceCommand.tutorialSkip,
    'skip it': VoiceCommand.tutorialSkip,
    'repeat': VoiceCommand.tutorialRepeat,
    'again': VoiceCommand.tutorialRepeat,
    'one more time': VoiceCommand.tutorialRepeat,
    'restart recognition': VoiceCommand.restartPipeline,
    'restart': VoiceCommand.restartPipeline,
    'reset': VoiceCommand.restartPipeline,
    'dark theme': VoiceCommand.themeDark,
    'light theme': VoiceCommand.themeLight,
    'high contrast': VoiceCommand.themeHighContrast,
    'warm theme': VoiceCommand.themeWarm,
    'language packs': VoiceCommand.manageLanguagePacks,
    'manage packs': VoiceCommand.manageLanguagePacks,
    'manage language packs': VoiceCommand.manageLanguagePacks,
    'enhanced kazakh': VoiceCommand.enableKkV2,
    'new kazakh recognition': VoiceCommand.enableKkV2,
    'standard kazakh': VoiceCommand.disableKkV2,
    'legacy kazakh recognition': VoiceCommand.disableKkV2,

    'stop trail': VoiceCommand.stopTrailRecord,
    'stop recording trail': VoiceCommand.stopTrailRecord,
    'stop trail recording': VoiceCommand.stopTrailRecord,

    'bazaar mode': VoiceCommand.toggleBazaarMode,
    'market mode': VoiceCommand.toggleBazaarMode,
    'livestock mode': VoiceCommand.toggleLivestockMode,
    'animal mode': VoiceCommand.toggleLivestockMode,

    'voice adaptation': VoiceCommand.toggleVoiceAdaptation,
    'toggle adaptation': VoiceCommand.toggleVoiceAdaptation,
    'clear adaptation data': VoiceCommand.clearAdaptationData,
    'delete adaptation data': VoiceCommand.clearAdaptationData,

    'buddy network': VoiceCommand.toggleMeshBuddy,
    'mesh network': VoiceCommand.toggleMeshBuddy,
    'toggle buddy': VoiceCommand.toggleMeshBuddy,

    'near miss': VoiceCommand.recordNearMiss,
    'record hazard': VoiceCommand.recordNearMiss,
    'record near miss': VoiceCommand.recordNearMiss,
    'it was dangerous': VoiceCommand.recordNearMiss,

    'sonar': VoiceCommand.toggleSonar,
    'sonar mode': VoiceCommand.toggleSonar,
    'echolocation': VoiceCommand.toggleSonar,
    'right hand': VoiceCommand.dominantHandRight,
    'left hand': VoiceCommand.dominantHandLeft,
    'street': VoiceCommand.modeStreet,
    'cane': VoiceCommand.modeCane,
    'allow': VoiceCommand.allowPermission,
    'grant': VoiceCommand.allowPermission,
    'yes': VoiceCommand.confirm,
    'no': VoiceCommand.cancel,
    'back': VoiceCommand.back,
    'russian': VoiceCommand.langRussian,
    'русский': VoiceCommand.langRussian,
    'kazakh': VoiceCommand.langKazakh,
    'қазақ': VoiceCommand.langKazakh,
    'english': VoiceCommand.langEnglish,
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

  static const List<String> _enRecordTrailPrefixes = [
    'record trail to ',
    'record path to ',
    'record indoor trail to ',
    'remember trail to ',
    'save trail to ',
  ];

  static const List<String> _enReplayTrailPrefixes = [
    'replay trail to ',
    'follow trail to ',
    'indoor go to ',
    'indoor trail to ',
    'follow trail ',
  ];

  static const List<String> _enLandmarkPrefixes = ['landmark ', 'mark '];

  static const List<String> _enDeleteTrailPrefixes = [
    'delete trail ',
    'remove trail ',
    'forget trail ',
  ];

  static const List<String> _enRememberPrefixes = [
    'remember my ',
    'remember the ',
    'remember this ',
    'remember these ',
    'remember ',
  ];

  static const List<String> _enFindPrefixes = [
    'find my ',
    'find the ',
    'find ',
    'where is my ',
    'where is the ',
    'where are my ',
    'where are the ',
    'locate my ',
    'locate the ',
    'locate ',
  ];

  static const List<String> _enForgetPrefixes = [
    'forget my ',
    'forget the ',
    'forget ',
    'delete my ',
    'delete the ',
    'delete ',
  ];

  static const Set<String> _enCancelFindExact = {
    'stop find',
    'stop finding',
    'stop searching',
    'stop search',
    'cancel find',
    'cancel search',
    'cancel searching',
    'end search',
  };

  bool _continuous = false;
  int _inputGeneration = 0;
  Future<void>? _pendingListen;

  /// Explicit, acknowledged transfer to the local ordinary-command input.
  /// Legacy stopListening remains the emergency path's existing contract.
  Future<bool> releaseMicrophone() async {
    ++_inputGeneration;
    _continuous = false;
    _continuousDeadline = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _pendingListen?.timeout(const Duration(seconds: 2));
      if (_useVoskForKk && _vosk.isListening) {
        await _vosk.stop().timeout(const Duration(seconds: 2));
      }
      if (_available) await _stt.cancel().timeout(const Duration(seconds: 2));
      _setListening(false);
      return true;
    } catch (_) {
      return false;
    }
  }
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
            final hadResult = _hadResult;
            _setListening(false);
            if (_continuous) {
              _maybeRelistenContinuous();
            } else if (!hadResult) {
              onListenDone?.call();
            }
          }
        },
      );
    } catch (e) {
      _available = false;
    }

    unawaited(_reconcileVoskRouting());
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
    if (_locale == bcp47) return;
    _locale = bcp47;

    unawaited(_reconcileVoskRouting());
  }

  /// Returns true if the kk-via-Vosk routing is currently active. Exposed
  /// for diagnostics and tests; do not gate user-facing behavior on this
  /// (the routing falls back transparently when Vosk is unavailable).
  @visibleForTesting
  bool get useVoskForKk => _useVoskForKk;

  /// Build the closed-set grammar passed to Vosk. Includes every kk
  /// command phrase, SOS shouts, cancel-fall acknowledgments, cancel-find
  /// acknowledgments, and the [VoskKkRecognizer.unknownToken] sentinel so
  /// out-of-grammar speech is rejected cleanly instead of force-fit.
  ///
  /// Open-class commands (nav-with-destination, remember/find/forget with
  /// arbitrary noun) are not represented in this grammar; users who need
  /// them with v2 enabled fall back to `speech_to_text` automatically when
  /// the model rejects their utterance, since the routing layer hands
  /// `_vosk.unknownToken` results back as `VoiceCommand.unknown` and the
  /// dispatcher will retry on the next listen window.
  @visibleForTesting
  static List<String> buildKkClosedGrammar() {
    final phrases = <String>{};
    phrases.addAll(_kkCommands.keys);
    phrases.addAll(_kkSosExact);
    phrases.addAll(_kkCancelFallExact);
    phrases.addAll(_kkCancelFindExact);
    phrases.add(VoskKkRecognizer.unknownToken);
    return phrases.where((p) => p.trim().isNotEmpty).toList(growable: false);
  }

  bool _shouldUseVoskForKk() {
    if (!_locale.startsWith('kk')) return false;
    if (!Settings.instance.isReady) return false;
    if (!Settings.instance.enableKazakhStackV2) return false;
    if (!LanguagePackManager.instance.isInstalled(LanguagePackIds.voskKk)) {
      return false;
    }
    return true;
  }

  Future<void> _reconcileVoskRouting() async {
    final pending = _reconcileFuture;
    if (pending != null) {
      await pending;
    }
    final completer = Completer<void>();
    _reconcileFuture = completer.future;
    try {
      final shouldUse = _shouldUseVoskForKk();
      if (shouldUse == _useVoskForKk && (!shouldUse || _vosk.isReady)) {
        return;
      }
      if (shouldUse) {
        final ok = await _initVoskIfNeeded();
        _useVoskForKk = ok;
        FieldLogger.instance.log('vosk_kk_routing', {
          'enabled': ok,
          'locale': _locale,
        });
      } else {
        if (_vosk.isListening) {
          await _vosk.stop();
        }
        _useVoskForKk = false;
      }
    } finally {
      if (!completer.isCompleted) completer.complete();
      if (identical(_reconcileFuture, completer.future)) {
        _reconcileFuture = null;
      }
    }
  }

  Future<bool> _initVoskIfNeeded() async {
    final pack = LanguagePackManager.instance.getInstalled(
      LanguagePackIds.voskKk,
    );
    if (pack == null || pack.localPath.isEmpty) return false;
    _vosk
      ..onResult = _onVoskResult
      ..onError = (err) => onError?.call('vosk_kk:$err');
    final ok = await _vosk.init(
      pack.localPath,
      grammar: buildKkClosedGrammar(),
    );
    return ok;
  }

  void _onVoskResult(String text) {
    final cleaned = text.trim();

    _processResult(cleaned);

    if (!_continuous && _vosk.isListening) {
      unawaited(_vosk.stop());
      _setListening(false);
    }
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
    final generation = _inputGeneration;
    if (!_available) return false;
    if (_listening) return true;

    final hasPerm = await Permission.microphone.isGranted;
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) return false;
    }

    if (generation != _inputGeneration) return false;
    return _listenInternal(listenFor: listenFor, pauseFor: pauseFor);
  }

  Future<bool> _listenInternal({
    Duration listenFor = const Duration(seconds: 6),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    final generation = _inputGeneration;
    _hadResult = false;
    if (_useVoskForKk) {
      return _listenWithVosk(listenFor: listenFor);
    }
    final acknowledgement = Completer<void>();
    _pendingListen = acknowledgement.future;
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
          if (generation == _inputGeneration && result.finalResult) {
            _hadResult = true;
            _processResult(result.recognizedWords);
          }
        },
      );
      if (generation != _inputGeneration) return false;
      _setListening(true);
      return true;
    } catch (e) {
      _setListening(false);
      return false;
    } finally {
      acknowledgement.complete();
      if (identical(_pendingListen, acknowledgement.future)) {
        _pendingListen = null;
      }
    }
  }

  Future<bool> _listenWithVosk({required Duration listenFor}) async {
    if (!_vosk.isReady) {
      final ok = await _initVoskIfNeeded();
      if (!ok) {
        _useVoskForKk = false;
        return _listenInternal(listenFor: listenFor);
      }
    }
    final started = await _vosk.start();
    if (!started) {
      _setListening(false);
      return false;
    }
    _setListening(true);
    if (!_continuous) {
      Future<void>.delayed(listenFor, () async {
        if (_continuous) return;
        if (_vosk.isListening) {
          await _vosk.stop();
          _setListening(false);
        }
      });
    }
    return true;
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

  void extendContinuousDeadline(Duration newSessionDuration) {
    if (!_continuous) return;
    final newDeadline = DateTime.now().add(newSessionDuration);
    if (newDeadline.isAfter(_continuousDeadline)) {
      _continuousDeadline = newDeadline;
    } else {
      _continuousDeadline = newDeadline;
    }
  }

  DateTime get continuousDeadline => _continuousDeadline;

  bool get isContinuousActive =>
      _continuous && DateTime.now().isBefore(_continuousDeadline);

  Future<void> stopListening() async {
    _continuous = false;

    _continuousDeadline = DateTime.fromMillisecondsSinceEpoch(0);
    if (_useVoskForKk && _vosk.isListening) {
      await _vosk.stop();
      _setListening(false);
      return;
    }
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
    unawaited(_vosk.dispose());
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

    final isKk = _locale.startsWith('kk');
    final isEn = _locale.startsWith('en');

    final Set<String> cancelSet;
    final Set<String> sosSet;
    final Set<String> cancelFindSet;
    final List<String> navPrefixes;
    final List<String> transitPrefixes;
    final List<String> busRoutePrefixes;
    final List<String> busSchedulePrefixes;
    final List<String> rememberPrefixes;
    final List<String> findPrefixes;
    final List<String> forgetPrefixes;
    final List<String> recordTrailPrefixes;
    final List<String> replayTrailPrefixes;
    final List<String> landmarkPrefixes;
    final List<String> deleteTrailPrefixes;
    final Map<String, VoiceCommand> commands;
    final List<String> sorted;
    if (isEn) {
      cancelSet = _enCancelFallExact;
      sosSet = _enSosExact;
      cancelFindSet = _enCancelFindExact;
      navPrefixes = _enNavPrefixes;
      transitPrefixes = _enTransitPrefixes;
      busRoutePrefixes = _enBusRoutePrefixes;
      busSchedulePrefixes = _enBusSchedulePrefixes;
      rememberPrefixes = _enRememberPrefixes;
      findPrefixes = _enFindPrefixes;
      forgetPrefixes = _enForgetPrefixes;
      recordTrailPrefixes = _enRecordTrailPrefixes;
      replayTrailPrefixes = _enReplayTrailPrefixes;
      landmarkPrefixes = _enLandmarkPrefixes;
      deleteTrailPrefixes = _enDeleteTrailPrefixes;
      commands = _enCommands;
      sorted = _enSorted;
    } else if (isKk) {
      cancelSet = _kkCancelFallExact;
      sosSet = _kkSosExact;
      cancelFindSet = _kkCancelFindExact;
      navPrefixes = _kkNavPrefixes;
      transitPrefixes = _kkTransitPrefixes;
      busRoutePrefixes = _kkBusRoutePrefixes;
      busSchedulePrefixes = _kkBusSchedulePrefixes;
      rememberPrefixes = _kkRememberPrefixes;
      findPrefixes = _kkFindPrefixes;
      forgetPrefixes = _kkForgetPrefixes;
      recordTrailPrefixes = _kkRecordTrailPrefixes;
      replayTrailPrefixes = _kkReplayTrailPrefixes;
      landmarkPrefixes = _kkLandmarkPrefixes;
      deleteTrailPrefixes = _kkDeleteTrailPrefixes;
      commands = _kkCommands;
      sorted = _kkSorted;
    } else {
      cancelSet = _ruCancelFallExact;
      sosSet = _ruSosExact;
      cancelFindSet = _ruCancelFindExact;
      navPrefixes = _ruNavPrefixes;
      transitPrefixes = _ruTransitPrefixes;
      busRoutePrefixes = _ruBusRoutePrefixes;
      busSchedulePrefixes = _ruBusSchedulePrefixes;
      rememberPrefixes = _ruRememberPrefixes;
      findPrefixes = _ruFindPrefixes;
      forgetPrefixes = _ruForgetPrefixes;
      recordTrailPrefixes = _ruRecordTrailPrefixes;
      replayTrailPrefixes = _ruReplayTrailPrefixes;
      landmarkPrefixes = _ruLandmarkPrefixes;
      deleteTrailPrefixes = _ruDeleteTrailPrefixes;
      commands = _ruCommands;
      sorted = _ruSorted;
    }

    if (cancelSet.contains(lower) ||
        _matchesFallCancelKeyword(lower, isKk: isKk, isEn: isEn)) {
      onCommand?.call(VoiceCommand.cancelFall);
      return;
    }
    if (cancelFindSet.contains(lower)) {
      onCommand?.call(VoiceCommand.cancelFind);
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
          _recordAdaptation(lower, 'transitTo');
          onNavCommand?.call(VoiceCommand.transitTo, dest);
          return;
        }
      }
    }

    for (final prefix in recordTrailPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          _recordAdaptation(lower, 'recordTrail');
          onNavCommand?.call(VoiceCommand.recordTrail, name);
          return;
        }
      }
    }

    for (final prefix in replayTrailPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          _recordAdaptation(lower, 'replayTrail');
          onNavCommand?.call(VoiceCommand.replayTrail, name);
          return;
        }
      }
    }

    for (final prefix in landmarkPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          _recordAdaptation(lower, 'addTrailLandmark');
          onNavCommand?.call(VoiceCommand.addTrailLandmark, name);
          return;
        }
      }
    }

    for (final prefix in deleteTrailPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          _recordAdaptation(lower, 'deleteTrail');
          onNavCommand?.call(VoiceCommand.deleteTrail, name);
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
        final cmd = commands[key]!;
        _recordAdaptation(lower, cmd.name);
        onCommand?.call(cmd);
        return;
      }
    }

    for (final prefix in rememberPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.rememberObject, name);
          return;
        }
      }
    }

    for (final prefix in findPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.findObject, name);
          return;
        }
      }
    }

    for (final prefix in forgetPrefixes) {
      if (lower.startsWith(prefix)) {
        final name = lower.substring(prefix.length).trim();
        if (name.isNotEmpty) {
          onNavCommand?.call(VoiceCommand.forgetObject, name);
          return;
        }
      }
    }

    onCommand?.call(VoiceCommand.unknown);
  }

  /// Fire-and-forget: record successful voice command for future
  /// on-device ASR adaptation (Phase 1 / Direction 12).
  void _recordAdaptation(String transcript, String commandId) {
    unawaited(
      VoiceAdaptationStore.instance.record(
        locale: _locale,
        transcript: transcript,
        commandId: commandId,
      ),
    );
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

  static const List<String> _ruCancelFallKeywords = <String>[
    'порядк',
    'норм',
    'хорош',
    'ложн',
    'не пада',
    'не упа',
    'не упал',
    'ничего не случил',
    'это не паден',
    'нет проблем',
    'не страшно',
    'все ок',
    'всё ок',
    'я ок',
    'ошибк',
  ];

  static const List<String> _kkCancelFallKeywords = <String>[
    'жақсы',
    'дұрыс',
    'жалған',
    'құлама',
    'құлаған жоқ',
    'мәселе жоқ',
    'еш нәрсе',
  ];

  static const List<String> _enCancelFallKeywords = <String>[
    'fine',
    'okay',
    " ok",
    'ok ',
    "i'm ok",
    'i am ok',
    "didn't fall",
    'did not fall',
    'no problem',
    'no problems',
    'false alarm',

    'nothing happened',
    'all good',
    'i am good',
  ];

  static bool _matchesFallCancelKeyword(
    String lower, {
    required bool isKk,
    required bool isEn,
  }) {
    final keywords = isEn
        ? _enCancelFallKeywords
        : isKk
        ? _kkCancelFallKeywords
        : _ruCancelFallKeywords;
    for (final kw in keywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }
}
