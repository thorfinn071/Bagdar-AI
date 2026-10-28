import '../../models/a11y_prefs.dart';
import '../../models/strings.dart';
import '../../theme/bagdar_tokens.dart';

enum VoiceSettingsPage {
  menu,
  speech,
  rate,
  volume,
  appearance,
  moreThemes,
  review,
}

enum VoiceSettingsIntent {
  speech,
  appearance,
  overview,
  rate,
  volume,
  slower,
  normal,
  faster,
  quieter,
  louder,
  dark,
  light,
  more,
  contrast,
  warm,
  save,
  cancel,
  back,
  repeat,
}

enum VoiceSettingKind { rate, volume, theme }

class VoiceSettingChange {
  final VoiceSettingKind kind;
  final double? number;
  final BagdarThemeName? theme;
  const VoiceSettingChange.rate(double value)
    : kind = VoiceSettingKind.rate,
      number = value,
      theme = null;
  const VoiceSettingChange.volume(double value)
    : kind = VoiceSettingKind.volume,
      number = value,
      theme = null;
  const VoiceSettingChange.theme(BagdarThemeName value)
    : kind = VoiceSettingKind.theme,
      number = null,
      theme = value;
  bool get valid => switch (kind) {
    VoiceSettingKind.rate =>
      number != null &&
          number!.isFinite &&
          number! >= kSpeechRateMin &&
          number! <= kSpeechRateMax,
    VoiceSettingKind.volume =>
      number != null &&
          number!.isFinite &&
          number! >= kTtsVolumeMin &&
          number! <= kTtsVolumeMax,
    VoiceSettingKind.theme => theme != null,
  };
}

class VoiceSettingsSnapshot {
  final double rate, volume, earconVolume;
  final BagdarThemeName theme;
  final AppLanguage language;
  final HapticStrength haptics;
  final bool earconEnabled;
  const VoiceSettingsSnapshot({
    required this.rate,
    required this.volume,
    required this.theme,
    required this.language,
    required this.haptics,
    required this.earconEnabled,
    required this.earconVolume,
  });
}

abstract interface class VoiceSettingsGateway {
  VoiceSettingsSnapshot read();

  /// True confirms persistence only, never hearing, calibration or admission.
  Future<bool> save(VoiceSettingChange change);
}

String voiceSettingsText(String key, AppLanguage language) {
  const strings = {
    'title': ['Голосовые настройки', 'Дауыстық баптаулар', 'Voice settings'],
    'intro': [
      'Это короткий диалог настроек. Изменение применяется только после команды «Сохранить».',
      'Бұл қысқа баптау диалогы. Өзгеріс тек «Сақтау» пәрменінен кейін қолданылады.',
      'This is a short settings dialogue. Changes apply only after you say Save.',
    ],
    'menu': [
      'Скажите: речь, оформление или обзор.',
      'Айтыңыз: сөйлеу, көрініс немесе шолу.',
      'Say: speech, appearance or overview.',
    ],
    'speech': [
      'Скажите: темп, громкость или назад.',
      'Айтыңыз: қарқын, дыбыс деңгейі немесе артқа.',
      'Say: rate, volume or back.',
    ],
    'rate': [
      'Скажите: медленнее, обычный или быстрее.',
      'Айтыңыз: баяуырақ, қалыпты немесе жылдамырақ.',
      'Say: slower, normal or faster.',
    ],
    'volume': [
      'Скажите: тише, обычная или громче.',
      'Айтыңыз: бәсеңірек, қалыпты немесе қаттырақ.',
      'Say: quieter, normal or louder.',
    ],
    'appearance': [
      'Скажите: тёмная, светлая или ещё.',
      'Айтыңыз: қараңғы, жарық немесе тағы.',
      'Say: dark, light or more.',
    ],
    'moreThemes': [
      'Скажите: контрастная, тёплая или назад.',
      'Айтыңыз: контрастты, жылы немесе артқа.',
      'Say: contrast, warm or back.',
    ],
    'review': [
      'Скажите: сохранить, отменить или назад.',
      'Айтыңыз: сақтау, болдырмау немесе артқа.',
      'Say: save, cancel or back.',
    ],
    'current': ['Сейчас', 'Қазір', 'Current'],
    'proposed': ['Выбрано', 'Таңдалды', 'Selected'],
    'rateLabel': ['Темп речи', 'Сөйлеу қарқыны', 'Speech rate'],
    'volumeLabel': [
      'Громкость речи',
      'Сөйлеу дыбысының деңгейі',
      'Speech volume',
    ],
    'themeLabel': ['Тема', 'Тақырып', 'Theme'],
    'languageLabel': ['Язык', 'Тіл', 'Language'],
    'signalsLabel': ['Сигналы', 'Белгілер', 'Signals'],
    'hapticsLabel': ['Вибрация', 'Діріл', 'Vibration'],
    'readOnly': [
      'Язык и сигналы здесь только читаются; изменить их можно в экранных настройках.',
      'Тіл мен белгілер мұнда тек оқылады; оларды экран баптауларында өзгертуге болады.',
      'Language and signals are read here; use the screen settings to change them.',
    ],
    'listening': [
      'Слушаю ответ на текущий вопрос',
      'Қазіргі сұрақтың жауабын тыңдап тұрмын',
      'Listening for this question',
    ],
    'saved': ['Сохранено', 'Сақталды', 'Saved'],
    'saving': [
      'Сохраняю выбранное значение',
      'Таңдалған мән сақталуда',
      'Saving the chosen value',
    ],
    'off': [
      'Микрофон выключен. Для новой настройки выберите «Начать голосовую настройку».',
      'Микрофон өшірілді. Жаңа баптау үшін «Дауыстық баптауды бастау» элементін таңдаңыз.',
      'Microphone off. For another change, choose Start voice settings.',
    ],
    'savePending': [
      'Запись уже началась. Проверьте итог в экранных настройках.',
      'Жазу басталып кетті. Нәтижені экран баптауларынан тексеріңіз.',
      'Saving has already started. Check the result in screen settings.',
    ],
    'saveFailed': [
      'Сохранение не подтверждено. Проверьте значение в экранных настройках.',
      'Сақтау расталмады. Мәнді экран баптауларынан тексеріңіз.',
      'Saving was not confirmed. Check the value in screen settings.',
    ],
    'cancelled': [
      'Выбор отменён. Изменения не применены.',
      'Таңдау болдырылмады. Өзгерістер қолданылмады.',
      'Selection cancelled. Changes were not applied.',
    ],
    'unknown': [
      'Ответ не подходит к этому вопросу.',
      'Жауап осы сұраққа сәйкес емес.',
      'That answer does not match this question.',
    ],
    'same': [
      'Это значение уже установлено.',
      'Бұл мән бұрыннан орнатылған.',
      'That value is already set.',
    ],
    'limit': [
      'Короткий сеанс завершён. Для продолжения включите ввод заново.',
      'Қысқа сеанс аяқталды. Жалғастыру үшін енгізуді қайта қосыңыз.',
      'The short session has ended. Activate input again to continue.',
    ],
    'start': [
      'Начать голосовую настройку',
      'Дауыстық баптауды бастау',
      'Start voice settings',
    ],
    'close': ['Закрыть настройки', 'Баптауларды жабу', 'Close settings'],
  };
  return strings[key]![language.index];
}

String voiceThemeName(BagdarThemeName theme, AppLanguage language) =>
    (switch (theme) {
      BagdarThemeName.dark => ['тёмная', 'қараңғы', 'dark'],
      BagdarThemeName.light => ['светлая', 'жарық', 'light'],
      BagdarThemeName.highContrast => ['контрастная', 'контрастты', 'contrast'],
      BagdarThemeName.warm => ['тёплая', 'жылы', 'warm'],
    })[language.index];

String voiceSettingValue(VoiceSettingChange change, AppLanguage language) {
  final label = voiceSettingsText(switch (change.kind) {
    VoiceSettingKind.rate => 'rateLabel',
    VoiceSettingKind.volume => 'volumeLabel',
    VoiceSettingKind.theme => 'themeLabel',
  }, language);
  return '$label: ${voiceSettingOnlyValue(change, language)}';
}

String voiceSettingOnlyValue(VoiceSettingChange change, AppLanguage language) =>
    switch (change.kind) {
      VoiceSettingKind.rate =>
        change.number!
            .toStringAsFixed(1)
            .replaceAll('.', language == AppLanguage.en ? '.' : ','),
      VoiceSettingKind.volume => '${(change.number! * 100).round()}%',
      VoiceSettingKind.theme => voiceThemeName(change.theme!, language),
    };

VoiceSettingsIntent? parseVoiceSettings(
  String text,
  AppLanguage language,
  VoiceSettingsPage page,
) {
  final normalized = text
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[.!?,;:]+$'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final words = switch (language) {
    AppLanguage.ru => const {
      'речь': VoiceSettingsIntent.speech,
      'оформление': VoiceSettingsIntent.appearance,
      'обзор': VoiceSettingsIntent.overview,
      'темп': VoiceSettingsIntent.rate,
      'громкость': VoiceSettingsIntent.volume,
      'медленнее': VoiceSettingsIntent.slower,
      'обычный': VoiceSettingsIntent.normal,
      'обычная': VoiceSettingsIntent.normal,
      'быстрее': VoiceSettingsIntent.faster,
      'тише': VoiceSettingsIntent.quieter,
      'громче': VoiceSettingsIntent.louder,
      'тёмная': VoiceSettingsIntent.dark,
      'темная': VoiceSettingsIntent.dark,
      'светлая': VoiceSettingsIntent.light,
      'ещё': VoiceSettingsIntent.more,
      'еще': VoiceSettingsIntent.more,
      'контрастная': VoiceSettingsIntent.contrast,
      'тёплая': VoiceSettingsIntent.warm,
      'теплая': VoiceSettingsIntent.warm,
      'сохранить': VoiceSettingsIntent.save,
      'отменить': VoiceSettingsIntent.cancel,
      'выключить микрофон': VoiceSettingsIntent.cancel,
      'назад': VoiceSettingsIntent.back,
      'повтори': VoiceSettingsIntent.repeat,
    },
    AppLanguage.kk => const {
      'сөйлеу': VoiceSettingsIntent.speech,
      'көрініс': VoiceSettingsIntent.appearance,
      'шолу': VoiceSettingsIntent.overview,
      'қарқын': VoiceSettingsIntent.rate,
      'дыбыс деңгейі': VoiceSettingsIntent.volume,
      'баяуырақ': VoiceSettingsIntent.slower,
      'қалыпты': VoiceSettingsIntent.normal,
      'жылдамырақ': VoiceSettingsIntent.faster,
      'бәсеңірек': VoiceSettingsIntent.quieter,
      'қаттырақ': VoiceSettingsIntent.louder,
      'қараңғы': VoiceSettingsIntent.dark,
      'жарық': VoiceSettingsIntent.light,
      'тағы': VoiceSettingsIntent.more,
      'контрастты': VoiceSettingsIntent.contrast,
      'жылы': VoiceSettingsIntent.warm,
      'сақтау': VoiceSettingsIntent.save,
      'болдырмау': VoiceSettingsIntent.cancel,
      'микрофонды өшір': VoiceSettingsIntent.cancel,
      'артқа': VoiceSettingsIntent.back,
      'қайтала': VoiceSettingsIntent.repeat,
    },
    AppLanguage.en => const {
      'speech': VoiceSettingsIntent.speech,
      'appearance': VoiceSettingsIntent.appearance,
      'overview': VoiceSettingsIntent.overview,
      'rate': VoiceSettingsIntent.rate,
      'volume': VoiceSettingsIntent.volume,
      'slower': VoiceSettingsIntent.slower,
      'normal': VoiceSettingsIntent.normal,
      'faster': VoiceSettingsIntent.faster,
      'quieter': VoiceSettingsIntent.quieter,
      'louder': VoiceSettingsIntent.louder,
      'dark': VoiceSettingsIntent.dark,
      'light': VoiceSettingsIntent.light,
      'more': VoiceSettingsIntent.more,
      'contrast': VoiceSettingsIntent.contrast,
      'warm': VoiceSettingsIntent.warm,
      'save': VoiceSettingsIntent.save,
      'cancel': VoiceSettingsIntent.cancel,
      'turn off microphone': VoiceSettingsIntent.cancel,
      'back': VoiceSettingsIntent.back,
      'repeat': VoiceSettingsIntent.repeat,
    },
  };
  final intent = words[normalized];
  final allowed = switch (page) {
    VoiceSettingsPage.menu => {
      VoiceSettingsIntent.speech,
      VoiceSettingsIntent.appearance,
      VoiceSettingsIntent.overview,
    },
    VoiceSettingsPage.speech => {
      VoiceSettingsIntent.rate,
      VoiceSettingsIntent.volume,
    },
    VoiceSettingsPage.rate => {
      VoiceSettingsIntent.slower,
      VoiceSettingsIntent.normal,
      VoiceSettingsIntent.faster,
    },
    VoiceSettingsPage.volume => {
      VoiceSettingsIntent.quieter,
      VoiceSettingsIntent.normal,
      VoiceSettingsIntent.louder,
    },
    VoiceSettingsPage.appearance => {
      VoiceSettingsIntent.dark,
      VoiceSettingsIntent.light,
      VoiceSettingsIntent.more,
    },
    VoiceSettingsPage.moreThemes => {
      VoiceSettingsIntent.contrast,
      VoiceSettingsIntent.warm,
    },
    VoiceSettingsPage.review => {VoiceSettingsIntent.save},
  };
  return allowed.contains(intent) ||
          {
            VoiceSettingsIntent.back,
            VoiceSettingsIntent.repeat,
            VoiceSettingsIntent.cancel,
          }.contains(intent)
      ? intent
      : null;
}
