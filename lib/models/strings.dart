import 'a11y_prefs.dart';

enum AppLanguage { ru, kk, en }

typedef S = AppStrings;

class AppStrings {
  AppStrings._();

  static AppLanguage current = AppLanguage.ru;

  static AppLanguage? _alertLang;

  static AppLanguage get alertLanguage => _alertLang ?? current;

  static void setAlertLanguage(AppLanguage? lang) => _alertLang = lang;

  static String get ttsLang {
    if (current == AppLanguage.kk) return 'kk-KZ';
    if (current == AppLanguage.en) return 'en-US';
    return 'ru-RU';
  }

  static String get(String key, {Verbosity? verbosity}) {
    if (verbosity != null && verbosity != Verbosity.normal) {
      final suffix = verbosity == Verbosity.minimal ? '_minimal' : '_detailed';
      final variant =
          _ui[current]?['$key$suffix'] ?? _ui[AppLanguage.ru]?['$key$suffix'];
      if (variant != null) return variant;
    }
    return _ui[current]?[key] ?? _ui[AppLanguage.ru]?[key] ?? key;
  }

  static String alert(String key) =>
      _ui[alertLanguage]?[key] ?? _ui[AppLanguage.ru]?[key] ?? key;

  static String label(String yoloClass) =>
      _labels[current]?[yoloClass] ??
      _labels[AppLanguage.ru]?[yoloClass] ??
      yoloClass;

  static String alertLabel(String yoloClass) =>
      _labels[alertLanguage]?[yoloClass] ??
      _labels[AppLanguage.ru]?[yoloClass] ??
      yoloClass;

  static String dir(String key) =>
      _dirs[current]?[key] ?? _dirs[AppLanguage.ru]?[key] ?? key;

  static String alertDir(String key) =>
      _dirs[alertLanguage]?[key] ?? _dirs[AppLanguage.ru]?[key] ?? key;

  static void setLanguage(AppLanguage lang) => current = lang;
}

const Map<AppLanguage, Map<String, String>> _ui = {
  AppLanguage.ru: {
    'stop': 'Стоп',
    'close': 'близко',
    'approaching': 'приближается',
    'transport_approaching': 'Транспорт приближается',
    'object_approaching': 'Объект приближается',
    'synth_event_stop_left': 'Стоп! Слева',
    'synth_event_stop_right': 'Стоп! Справа',
    'synth_event_stop_center': 'Стоп! Прямо',
    'sign': 'Знак',
    'path_clear': 'Анализ активен.',
    'path_clear_cane': 'Анализ активен.',
    'path_clear_label': 'Анализ активен',
    'no_change': 'Обстановка не изменилась.',
    'nothing_seen': 'Ничего не вижу.',
    'nothing_here': 'Ничего нет',
    'left': 'слева',
    'right': 'справа',
    'forward_loc': 'впереди',
    'closest': 'Ближайший объект в',
    'meters': 'метрах',
    'approx_meters': 'м',
    'now_imminent': 'сейчас',
    'hazard_dead_zone': 'Опасность у ног',
    'hazard_step_down': 'Ступенька вниз',
    'hazard_step_up': 'Ступенька вверх',
    'hazard_pothole': 'Яма',
    'hazard_curb': 'Бордюр',
    'hazard_stairs_down': 'Лестница вниз. Остановитесь.',
    'hazard_overhead': 'Препятствие на уровне груди. Остановитесь.',
    'hazard_unknown': 'Препятствие',
    'hazard_glass_door': 'Возможно стеклянная дверь впереди. Будьте осторожны.',
    'hazard_slippery': 'Осторожно, возможно скользко.',
    'hazard_warning': 'Возможное препятствие —',
    'phone_tilted_sideways': 'Телефон наклонён.',

    'deviate': 'Отклонитесь',
    'passage': 'Проход',
    'maneuver_ok': 'Хорошо.',
    'nav_left': 'влево',
    'nav_right': 'вправо',
    'nav_slight_left': 'немного влево',
    'nav_slight_right': 'немного вправо',
    'straight': 'прямо',

    'corridor_blocked': 'Проход заблокирован.',
    'narrow': 'Узко.',

    'status_no_obstacle': 'Анализ активен',
    'status_analysis_active': 'Анализ активен',
    'spatial_analysis_limited':
        'Анализ пространства ограничен. Используйте трость.',
    'spatial_stop_sensing_unavailable':
        'Стойте. Анализ пространства недоступен.',
    'core_health_sound_unavailable':
        'Звук недоступен. Предупреждения вибрацией остаются.',
    'core_health_haptic_unavailable':
        'Вибрация недоступна. Голосовые предупреждения остаются.',
    'core_health_recovered': 'Система восстановилась.',
    'core_health_status': 'Состояние системы',
    'generic_obstacle_ahead': 'Препятствие впереди.',
    'generic_obstacle_stop': 'Стоп. Препятствие впереди.',
    'generic_obstacle_left': 'Препятствие слева.',
    'generic_obstacle_right': 'Препятствие справа.',
    'generic_obstacle_overhead': 'Стоп. Препятствие на уровне головы.',
    'generic_vehicle_ahead': 'Машина впереди.',
    'generic_vehicle_left': 'Машина слева.',
    'generic_vehicle_right': 'Машина справа.',
    'status_scanning': 'Сканирование...',
    'status_waiting': 'ожидание',
    'dist_safe': 'безопасно',
    'dist_attention': 'внимание',
    'dist_stop': 'стоп',
    'lbl_object': 'Объект',
    'lbl_status': 'Статус',
    'lbl_total_objects': 'Всего объектов',

    'scan_left': 'Слева',
    'scan_forward': 'Впереди',
    'scan_right': 'Справа',
    'scan_see': 'Вижу',

    'ocr_reading': 'Читаю...',
    'ocr_not_found': 'Текст не найден.',
    'ocr_camera_not_ready': 'Камера не готова.',

    'ocr_low_memory':
        'Не хватает памяти для распознавания текста. Закройте другие приложения и попробуйте снова.',
    'ocr_paddle_init_failed':
        'Не удалось запустить улучшенный распознаватель. Использую стандартный вариант.',

    'camera_unavailable': 'Камера недоступна.',
    'camera_not_found': 'Камера не найдена',
    'camera_started': 'Камера запущена',
    'system_ready': 'Система готова',
    'core_feature_unavailable': 'Эта функция недоступна в текущей сборке.',
    'init_failed':
        'Не удалось запустить систему. Остановитесь. Перезапустите приложение.',
    'camera_init_failed_critical':
        'Ошибка камеры. Распознавание недоступно. Перезапустите приложение.',
    'mode_changed': 'Режим',

    'calib_aim': 'Наведите камеру на человека для калибровки.',
    'calib_saved': 'Калибровка сохранена.',
    'calib_recommend':
        'Для точного определения расстояния рекомендуем калибровку в настройках.',

    'onb_welcome_tts':
        'Добро пожаловать в Bagdar. Выберите режим. '
        'Свайп вверх или вниз — режим, двойной тап — выбрать.',
    'onb_welcome_intro_tts':
        'Здравствуйте. Багдар — это голосовой помощник для незрячих, помогающий ориентироваться в пространстве и избегать препятствий. Начнем настройку. Выберите язык. Свайп вверх или вниз — изменить язык. Двойной тап — выбрать. Или назовите язык вслух: Русский, Казахский или Английский.',
    'onb_dominant_hand_tts':
        'Шаг первый. Выберите ведущую руку. Это влияет на расположение жестов на экране. Свайп вверх или вниз — изменить выбор. Двойной тап — подтвердить. Или скажите вслух: Правая, или Левая.',
    'onb_mode_tts':
        'Шаг второй. Выберите режим работы по умолчанию. Свайп вверх или вниз — изменить режим. Двойной тап — подтвердить. Или скажите: Улица, Трость, или Сканирование.',
    'onb_perm_tts':
        'Разрешение камеры. Двойной тап — открыть запрос системы. Найдите кнопку Разрешить. Или скажите вслух: Разрешить.',
    'onb_calib_tts':
        'Калибровка расстояния. Для повышения точности рекомендуется калибровка. Вы сможете выполнить её в настройках, наведя камеру на человека в двух метрах от вас. Двойной тап, чтобы продолжить.',
    'onb_ready_tts': 'Всё готово. Двойной тап — начать.',
    'onb_hand_right': 'Правая рука',
    'onb_hand_left': 'Левая рука',
    'onb_hand_changed': 'Ведущая рука изменена на {hand}',
    'onb_secondary_aid_tts':
        'Bagdar предупреждает о препятствиях, но может их пропустить. '
        'Продолжайте использовать белую трость или собаку-поводыря. '
        'Bagdar — дополнительное средство.',
    'onb_secondary_aid_check':
        'Bagdar — дополнительное средство, не замена трости',
    'onb_blind_intro':
        'Bagdar для незрячих. Управление жестами. '
        'Один тап — повторить. Двойной тап — продолжить. '
        'Свайп вправо — следующий шаг, влево — назад. '
        'Долгое нажатие — смена языка. '
        'Если рядом есть близкий человек, рекомендуется передать ему телефон для первоначальной настройки.',
    'onb_gesture_help':
        'Жесты онбординга. Один тап — повторить инструкцию. '
        'Двойной тап — основное действие. Свайп вправо или влево — навигация. '
        'Долгое нажатие — смена языка. Свайп вниз — пропустить онбординг. '
        'Два пальца на две секунды — экстренный выход.',
    'onb_mode_select_announce': 'Режим: {mode}. Двойной тап — выбрать.',
    'onb_skip_confirm':
        'Пропустить всю настройку приложения? Двойной тап подтвердит. Один тап отменит.',
    'onb_skip_cancelled': 'Отменено.',
    'onb_lang_switched': 'Язык: русский.',
    'onb_calib_saved_tts': 'Отлично! Калибровка сохранена. Нажмите Продолжить.',
    'onb_calib_skip_tts':
        'Калибровка пропущена. Вы сможете выполнить её позже в настройках.',
    'onb_welcome_title': 'Добро пожаловать\nв Bagdar',
    'onb_welcome_sub':
        'Выберите режим по умолчанию.\nЕго можно изменить в любой момент.',
    'onb_perm_title': 'Нужен доступ',
    'onb_perm_sub': 'Только камера обязательна.\nОстальное — по желанию.',
    'onb_calib_title': 'Точность расстояния',
    'onb_calib_sub':
        'Без калибровки погрешность ~40%.\nПосле — ~10%. Займёт 10 секунд.',
    'onb_calib_app_note':
        'Калибровку можно выполнить в Настройках после запуска приложения.',
    'onb_ready_title': 'Всё готово!',
    'onb_ready_sub': 'Bagdar настроен. Вот что умеет приложение:',
    'onb_btn_continue': 'Продолжить',
    'onb_btn_allow_camera': 'Разрешить камеру',
    'onb_btn_skip': 'Пропустить остальное',
    'onb_btn_calibrate': 'Я стою в 2 метрах — откалибровать',
    'onb_btn_skip_calib': 'Пропустить — настрою позже',
    'onb_btn_calib_later': 'Откалибрую в настройках',
    'onb_btn_start': 'Начать',
    'onb_btn_back_calib': 'Вернуться к калибровке',
    'onb_calib_done': 'Калибровка выполнена — точность улучшена!',
    'onb_calib_hint': 'Попросите кого-нибудь встать в 2 м от вас',
    'onb_check_alerts': 'Голосовые предупреждения об объектах',
    'onb_check_mode': 'выбран по умолчанию',
    'onb_check_calib': 'Калибровка камеры',
    'onb_check_calib_skip': 'Доступна в Настройках → Калибровка камеры',
    'onb_feat_scan': 'Кнопка «Что вокруг?» — описание сцены',
    'onb_feat_mode': 'Иконка режима — переключение Улица / Трость / Скан',
    'onb_feat_settings': 'Настройки — калибровка, GPU, Debug HUD',
    'onb_lang_title': 'Выберите язык',
    'onb_lang_sub': 'Язык можно изменить в настройках',
    'onb_mic_exhausted':
        'Я не слышу вашего ответа. Используйте жесты: '
        'проведите вверх или вниз для выбора, дважды коснитесь для подтверждения. '
        'Коснитесь экрана один раз, чтобы я повторил.',
    'onb_mode_choose_first':
        'Сначала выберите режим. Скажите: улица, трость или сканирование.',
    'onb_perm_talkback_guide':
        'Сейчас появятся системные диалоги разрешений. '
        'Их будет три: камера, микрофон и геолокация. '
        'Используйте TalkBack — проведите вправо до кнопки Разрешить и дважды коснитесь. '
        'Я подожду.',
    'onb_perm_tap_guide':
        'Сейчас появятся системные диалоги. '
        'В каждом нажмите кнопку Разрешить в нижней части экрана. '
        'Если рядом есть зрячий помощник, попросите его помочь. Я подожду.',
    'onb_perm_camera_ok': 'Камера разрешена.',
    'onb_perm_mic_ok': 'Микрофон разрешён.',
    'onb_perm_all_granted':
        'Все разрешения получены. Отлично! Переходим дальше.',
    'onb_perm_denied_retry':
        'Камера не разрешена. Без камеры приложение не видит препятствий. '
        'Скажите «разрешить» для повторной попытки, или «пропустить».',

    'tut_title': 'Обучение жестам',
    'tut_intro':
        'Сейчас вы научитесь управлять приложением. '
        'Следуйте голосовым подсказкам. '
        'В любой момент можно пропустить.',
    'tut_tap': 'Коснитесь экрана один раз.',
    'tut_tap_done':
        'Отлично. Одиночное касание — быстрый статус: режим и заряд.',
    'tut_double_tap': 'Теперь коснитесь дважды быстро.',
    'tut_double_tap_done': 'Отлично. Двойное касание открывает настройки.',
    'tut_long_press': 'Удерживайте палец на экране одну секунду.',
    'tut_long_press_done': 'Отлично. Долгое нажатие — голосовая команда.',
    'tut_swipe_horizontal': 'Проведите пальцем вправо или влево.',
    'tut_swipe_horizontal_done':
        'Отлично. Свайп по горизонтали переключает режим.',
    'tut_swipe_up': 'Теперь проведите пальцем вверх.',
    'tut_swipe_up_done': 'Отлично. Свайп вверх вызывает справку.',
    'tut_swipe_down_legacy': 'Теперь проведите пальцем вниз.',
    'tut_swipe_down_legacy_done': 'Отлично. Свайп вниз вызывает справку.',
    'tut_two_finger':
        'Приложите два пальца сразу и удерживайте полторы секунды.',
    'tut_two_finger_done': 'Отлично. Два пальца полторы секунды вызывают SOS.',
    'tut_finished':
        'Обучение завершено. Также доступны голосовые команды для SOS и справки.',
    'tut_skip': 'Пропустить',
    'tut_replay': 'Повторить обучение жестам',
    'tut_finish': 'Завершить',
    'tut_progress': 'Шаг {step} из {total}',
    'tut_fail_hint':
        'Не получается? Скажите "пропустить" чтобы перейти дальше. '
        'Или скажите "повтори" чтобы услышать инструкцию снова.',
    'tut_detail_tap':
        'Один раз быстро коснитесь экрана пальцем и сразу уберите. '
        'Это короткое касание, без удержания.',
    'tut_detail_doubleTap':
        'Дважды быстро коснитесь экрана. '
        'Между касаниями менее половины секунды.',
    'tut_detail_longPress':
        'Прижмите палец к экрану и удерживайте около одной секунды, '
        'пока не услышите подтверждение.',
    'tut_detail_swipeHorizontal':
        'Положите палец на экран и проведите слева направо или справа налево. '
        'Движение должно быть быстрым и непрерывным.',
    'tut_detail_swipeVertical':
        'Положите палец и проведите вверх или вниз быстрым движением.',
    'tut_detail_twoFinger':
        'Положите два пальца рядом на экран одновременно '
        'и удерживайте полторы секунды.',

    'mode_street': 'Улица',
    'mode_cane': 'Трость',
    'mode_scan': 'Сканирование',
    'mode_street_desc': 'Машины, люди, препятствия — полный стек алертов',
    'mode_cane_desc': 'Максимально частая вибрация, минимум речи',
    'mode_scan_desc': 'Словесное описание окружения каждые 4 секунды',

    'perm_camera': 'Камера',
    'perm_camera_reason': 'Основная функция приложения',
    'perm_camera_required': 'Обязательно',
    'perm_mic': 'Микрофон',
    'perm_mic_reason': 'Голосовые команды (будущая функция)',
    'perm_location': 'Геолокация',
    'perm_location_reason': 'SOS-режим — отправить локацию близким',
    'perm_optional': 'Позже',

    'settings': 'Настройки',
    'cancel': 'Отмена',
    'save': 'Готово',
    'ok': 'ОК',
    'settings_a11y_title': 'Специальные возможности',
    'settings_classic_gestures': 'Классические жесты',
    'settings_classic_gestures_desc':
        'Свайп вверх — шторка, свайп вниз — справка',
    'settings_speech_rate': 'Скорость речи',
    'settings_tts_volume': 'Громкость речи',
    'settings_earcon_volume': 'Громкость звуков',
    'settings_verbosity': 'Подробность',
    'verbosity_minimal': 'Кратко',
    'verbosity_normal': 'Обычно',
    'verbosity_detailed': 'Подробно',
    'settings_alert_frequency': 'Частота предупреждений',
    'freq_rare': 'Редко',
    'freq_normal': 'Обычно',
    'freq_frequent': 'Часто',
    'settings_haptic_strength': 'Интенсивность вибрации',
    'haptic_weak': 'Слабая',
    'haptic_normal': 'Средняя',
    'haptic_strong': 'Сильная',
    'settings_sos_trigger': 'Триггер SOS',
    'sos_trigger_two_finger': 'Два пальца 2 сек',
    'sos_trigger_triple_tap': 'Тройное касание',
    'sos_trigger_shake': 'Встряхивание',
    'settings_dominant_hand': 'Ведущая рука',
    'hand_right': 'Правая',
    'hand_left': 'Левая',

    'backup_section_title': 'Резервная копия настроек',
    'backup_show_qr': 'Показать QR настроек',
    'backup_show_qr_subtitle': 'Покажите близкому, чтобы перенести настройки',
    'backup_scan_qr': 'Сканировать QR настроек',
    'backup_scan_qr_subtitle': 'Считайте QR с другого устройства',
    'qr_dismiss': 'Закрыть',
    'qr_export_title': 'QR настроек',
    'qr_export_ready':
        'QR готов. Покажите близкому, чтобы перенести настройки.',
    'qr_export_hint': 'Покажите этот QR близкому или другому устройству.',
    'qr_export_footer': 'Контакт SOS не передаётся.',
    'qr_export_semantics': 'QR-код с настройками доступности',
    'qr_import_title': 'Сканирование QR',
    'qr_import_aim_camera': 'Наведите камеру на QR-код настроек.',
    'qr_import_aim_hint': 'Направьте камеру на QR-код.',
    'qr_import_torch': 'Вспышка',
    'qr_import_found': 'QR найден',
    'qr_import_version': 'версия',
    'qr_import_lang': 'язык',
    'qr_import_speech_rate': 'скорость речи',
    'qr_import_tts_volume': 'громкость речи',
    'qr_import_earcon_volume': 'громкость звуков',
    'qr_import_hold_to_apply':
        'Удерживайте кнопку 1,5 секунды, чтобы применить.',
    'qr_import_long_press': 'Удерживайте — Применить',
    'qr_import_applying': 'Применяю...',
    'qr_import_applied': 'Настройки применены.',
    'qr_import_failed': 'Не удалось применить QR. Попробуйте ещё раз.',
    'qr_import_retry': 'Сканировать снова',

    'voice_listening': 'Слушаю...',
    'voice_not_available': 'Голосовые команды недоступны.',
    'voice_no_permission': 'Нет доступа к микрофону.',
    'voice_unknown': 'Команда не распознана.',
    'voice_listen_error': 'Не услышал. Повторите.',
    'voice_hint': 'Удерживайте экран для голосовой команды.',
    'voice_commands_list':
        'Доступные команды: что вокруг, что слева, что справа, '
        'что впереди, читай, режим, черный экран.',
    'voice_settings_commands':
        'Команды настроек: быстрее, медленнее, громче, тише, '
        'минимальная подробность, обычная подробность, детальная подробность, '
        'редкие алерты, обычные алерты, частые алерты, '
        'изменить sos на тройной тап, изменить sos на встряхивание, '
        'сильная вибрация, слабая вибрация.',

    'obj_remember_listening': 'Запоминаю {name}. Поднесите ближе.',
    'obj_remember_saved': '{name} запомнено.',
    'obj_remember_failed': 'Не вижу объекта. Попробуйте ещё раз.',
    'obj_remember_capacity': 'Память заполнена. Сначала забудьте что-нибудь.',
    'obj_find_started': 'Ищу {name}.',
    'obj_find_position': '{name}, {dist} метра, {dir}.',
    'obj_find_position_no_dist': '{name}, {dir}.',
    'obj_find_lost': '{name} не вижу.',
    'obj_find_found': '{name} перед вами.',
    'obj_find_stopped': 'Поиск остановлен.',
    'obj_find_searching': 'Ищу {name}...',
    'obj_forget_done': '{name} забыто',
    'obj_forget_unknown': 'Не помню {name}.',
    'obj_unknown_target': 'Не помню такой предмет. Скажите запомни {name}.',
    'obj_busy_remembering': 'Сейчас запоминаю, подождите.',

    'fg_notification_title': 'Bagdar активен',
    'fg_notification_body': 'Навигация работает в фоне.',

    'battery_low':
        'Низкий заряд. Работаю в экономном режиме. Будьте особенно внимательны.',
    'battery_low_depth_off':
        'Низкий заряд. Обнаружение глубины работает в экономном режиме. Будьте особенно внимательны.',
    'battery_low_critical':
        'Критический заряд. Работаю в минимальном режиме. Будьте особенно внимательны.',
    'battery_moderate': 'Заряд средний — экономлю энергию.',
    'battery_normal': 'Заряд в норме.',
    'thermal_warning_warm':
        'Устройство нагревается. Частота сканирования снижена.',
    'thermal_warning_hot':
        'Система перегрета. Частота сканирования снижена, идите медленнее.',
    'thermal_warning_critical':
        'Критическая температура. Частота сканирования сильно снижена.',
    'thermal_ground_hazard_reduced':
        'Высокая температура. Обнаружение ям и ступеней временно снижено.',
    'thermal_warm_move_to_shade':
        'Устройство нагревается. Зайдите в тень, если возможно. '
        'При высокой температуре точность обнаружения снижается.',
    'running_detected': 'Вы бежите. Пожалуйста, замедлитесь для безопасности.',
    'battery_50_remaining': 'Заряд 50%. Работы осталось примерно на два часа.',
    'battery_30_warning': 'Заряд 30%. Рекомендуем сократить прогулку.',
    'battery_15_critical':
        'Заряд 15%. Обнаружение ям снижено. Используйте трость или запросите помощь.',
    'low_light_warning':
        'Слабое освещение. Точность обнаружения снижена. Будьте особенно осторожны.',
    'pitch_black_ui': 'Чёрный экран',
    'pitch_black_ui_desc':
        'Скрывает изображение камеры и весь интерфейс навигации.',
    'pitch_black_on': 'Чёрный экран включён.',
    'pitch_black_off': 'Чёрный экран выключен.',
    'audio_route_interrupted': 'Звук прерван. Проверьте наушники.',
    'audio_resumed': 'Звук восстановлен.',
    'tts_fallback_en':
        'Voice pack for your language is missing. Using English fallback.',
    'tts_fallback_ru': 'Казахский голос недоступен. Используется русский язык.',
    'fall_detector_unavailable':
        'Датчик падения недоступен. Автоматический SOS отключён.',
    'fall_detector_degraded':
        'Точность определения падений снижена. Гироскоп недоступен.',
    'yolo_unavailable':
        'Распознавание объектов недоступно. Обнаружение опасностей отключено.',
    'yolo_detector_not_responding': 'Детектор объектов не отвечает.',
    'test_alert_warning': 'Тест: внимание слева',
    'test_alert_critical': 'Тест: критично по центру',
    'lifecycle_background':
        'Приложение свёрнуто. Верните его на экран, иначе сканирование не работает',
    'lifecycle_resumed': 'Приложение восстановлено.',

    'night_mode_on': 'Ночной режим включён.',
    'night_mode_off': 'Ночной режим выключен.',

    'guide_dog_on': 'Режим поводыря включён.',
    'guide_dog_off': 'Режим поводыря выключен.',
    'hazard_low_curb': 'Низкая ступенька впереди.',
    'hazard_near_field': 'Объект под камерой.',
    'weather_low_vis': 'Плохая видимость. Уменьшена точность.',
    'weather_restored': 'Видимость восстановлена.',
    'indoor_mode_entered': 'Режим помещения.',
    'indoor_mode_exited': 'Режим улицы.',
    'camera_partial_blocked': 'Камера частично перекрыта. Проверьте объектив.',
    'group_ahead': 'Впереди группа: ',
    'camera_reinit': 'Камера перезапускается. Подождите.',
    'camera_droplet': 'Возможно, капля на объективе. Протрите.',
    'camera_smear': 'Объектив загрязнён. Протрите.',

    'waypoint_saved': 'Место сохранено',
    'waypoint_near': 'Вы рядом с',
    'waypoint_name_prompt': 'Название места',
    'waypoint_none': 'Нет сохранённых мест.',
    'waypoint_deleted': 'Место удалено.',

    'sos_sent': 'SOS отправлен.',
    'sos_queued': 'SOS поставлен в очередь, ожидаю подтверждение.',
    'sos_sent_no_location':
        'SOS отправлен, но местоположение не удалось определить.',
    'sos_indoor_warning': 'Вы в помещении. Координаты могут быть неточными.',
    'sos_no_contact': 'Контакт для SOS не задан. Настройте в настройках.',
    'sos_no_location': 'Не удалось определить местоположение.',
    'sos_no_gps': 'местоположение недоступно',
    'sos_settings': 'SOS контакт',
    'sos_message': 'Мне нужна помощь! Моё местоположение:',
    'sos_invalid_number': 'Некорректный номер телефона.',
    'sos_launch_failed': 'Не удалось открыть приложение для SMS.',
    'sos_error': 'Не удалось отправить SOS.',
    'sos_fall_detected':
        'Обнаружено падение. SOS будет отправлен через 15 секунд. Нажмите на экран для отмены.',
    'sos_fall_classb_detected':
        'Вы в порядке? Нажмите на экран для отмены. SOS будет отправлен через 30 секунд.',
    'sos_fall_countdown': 'SOS через',
    'sos_fall_seconds': 'секунд.',
    'sos_fall_cancelled': 'Отправка SOS отменена.',
    'sos_fall_sent': 'SOS отправлен после падения.',
    'sos_user_fallen_again': 'Внимание: пользователь упал снова.',
    'sos_fall_cancel_hint':
        'Скажите "я в порядке" или "ложная тревога". Прикоснитесь к экрану для отмены.',
    'sos_fall_voice_confirm_prompt': 'Подтвердите: скажите "я в порядке".',
    'sos_fall_voice_cancel_rejected':
        'Отмена не подтверждена. Продолжаю отсчёт.',
    'sos_fall_are_you_ok': 'Вы в порядке? Нажмите для подтверждения.',
    'sos_cancel_confirm': 'Коснитесь ещё раз для отмены SOS.',
    'sos_112_fallback':
        'Контакт не задан. SOS будет отправлен на экстренный номер 112.',
    'sos_position_stale': 'Местоположение устарело на',
    'sos_position_unit_min': 'минут',
    'sos_sending': 'Отправляю SOS...',
    'sos_retry': 'Повторная отправка SOS.',
    'sos_delivered': 'SOS доставлен.',
    'sos_composer_opened':
        'Открыто окно сообщения, кнопка «Отправить» — внизу справа.',
    'sos_dialer_opened': 'Открыт набиратель, нажмите зелёную кнопку вызова.',
    'sos_planned_destination': 'Направлялся к:',
    'sos_near_wifi': 'Рядом с Wi-Fi:',
    'sos_near_cell': 'Рядом с вышкой:',
    'sos_steps_from_last': 'шагов',
    'sos_of_last_known': 'от последней точки',
    'sos_dir_n': 'на север',
    'sos_dir_ne': 'на северо-восток',
    'sos_dir_e': 'на восток',
    'sos_dir_se': 'на юго-восток',
    'sos_dir_s': 'на юг',
    'sos_dir_sw': 'на юго-запад',
    'sos_dir_w': 'на запад',
    'sos_dir_nw': 'на северо-запад',
    'camera_blocked': 'Камера заблокирована. Проверьте объектив.',
    'camera_ae_transition': 'Камера адаптируется к свету. Будьте осторожны.',
    'camera_frozen':
        'Внимание, изображение с камеры не меняется. Перезапустите приложение.',
    'camera_stalled': 'Камера замолчала. Остановитесь, проверьте приложение.',
    'camera_resumed': 'Камера снова работает.',
    'shake_warning':
        'Сильно трясет камеру. Замедлитесь или держите телефон ровнее.',
    'nav_maybe_off_route': 'Возможно, вы отклоняетесь от маршрута.',
    'pitch_too_high': 'Наклоните телефон ниже для сканирования земли.',
    'pitch_too_low': 'Поднимите телефон чуть выше.',
    'pitch_misaligned_blind': 'Поднимите телефон — я не вижу дорогу.',
    'misalign_no_detections':
        'Давно нет распознавания объектов. Поднимите телефон вертикально.',
    'phone_abandoned': 'Bagdar лежит — проверьте телефон.',
    'winter_visibility_heartbeat': 'Плохая видимость — аккуратно.',
    'curtain_on': 'Экранная шторка включена. Экран скрыт.',
    'curtain_off': 'Экранная шторка выключена.',
    'help_summary':
        'Справка по управлению. '
        'Одно касание — быстрый статус. '
        'Двойное касание — настройки. '
        'Долгое нажатие одним пальцем — голосовая команда. '
        'Свайп вправо или влево — смена режима. '
        'Свайп вверх — эта справка. '
        'Свайп вниз — экранная шторка. '
        'Два пальца две секунды — экстренный вызов SOS. '
        'Или скажите сос для SOS, справка для этого сообщения.',
    'help_summary_classic':
        'Справка по управлению. '
        'Одно касание — быстрый статус. '
        'Двойное касание — настройки. '
        'Долгое нажатие одним пальцем — голосовая команда. '
        'Свайп вправо или влево — смена режима. '
        'Свайп вверх — экранная шторка. '
        'Свайп вниз — эта справка. '
        'Два пальца две секунды — экстренный вызов SOS. '
        'Или скажите сос для SOS, справка для этого сообщения.',
    'status_quick': 'Режим {mode}. Заряд {battery} процентов.',
    'status_quick_mode_only': 'Режим {mode}.',
    'gesture_weak': 'Свайп слишком слабый. Проведите пальцем быстрее.',
    'camera_screen_semantics':
        'Экран камеры Bagdar. '
        'Один тап — режим и заряд. '
        'Двойной тап — настройки. '
        'Удержание пальца — голосовая команда. '
        'Свайп вправо или влево — смена режима. '
        'Свайп вверх — справка. Свайп вниз — экранная шторка. '
        'Два пальца на полторы секунды — экстренный вызов SOS.',
    'camera_screen_semantics_classic':
        'Экран камеры Bagdar. '
        'Один тап — режим и заряд. '
        'Двойной тап — настройки. '
        'Удержание пальца — голосовая команда. '
        'Свайп вправо или влево — смена режима. '
        'Свайп вверх — экранная шторка. Свайп вниз — справка. '
        'Два пальца на полторы секунды — экстренный вызов SOS.',
    'tl_green_warning': 'Пожалуйста, убедитесь в безопасности по звуку машин.',
    'tl_green_wait':
        'Светофор зелёный. Не начинайте движение без подтверждения, что транспорт остановился.',
    'tl_green_cars_near': 'Светофор зелёный, рядом транспорт. Подождите.',
    'tl_vehicle':
        'Автомобильный светофор. Не ориентируйтесь по нему, слушайте звуки перехода.',

    'depth_unavailable': 'Обнаружение глубины недоступно.',
    'depth_unavailable_street':
        'Внимание: безопасность по препятствиям на уровне пола отключена на этом устройстве. Обнаружение бордюров, лестниц и ям не работает. Используйте трость.',
    'depth_session_disabled':
        'Обнаружение глубины отключено из-за ошибок. Лестницы и бордюры не объявляются до перезапуска. Идите осторожно.',
    'hazard_detection_resumed': 'Обнаружение препятствий возобновлено.',
    'depth_paused_explicit': 'Обнаружение лестниц и бордюров приостановлено.',
    'weather_depth_off_walking':
        'Видимость плохая. Лестницы и бордюры могут не определяться. Ступайте медленно.',
    'depth_degraded':
        'Качество глубины снизилось. Внимательнее к препятствиям.',
    'depth_recovered': 'Качество глубины восстановлено.',
    'depth_quality_low': 'Качество глубины низкое. Перехожу на MiDaS.',
    'reduced_mode_depth':
        'Сниженный режим: обнаружение глубины приостановлено.',
    'reduced_mode_restored': 'Обнаружение глубины восстановлено.',

    'camera_perm_title': 'Нет доступа к камере',
    'camera_perm_body':
        'Камера необходима для работы Bagdar.\n'
        'Откройте Настройки и разрешите доступ к камере.',
    'camera_perm_blind_intro':
        'Камера запрещена системой. '
        'Двойной тап — открыть настройки телефона. '
        'Один тап — отменить.',
    'camera_perm_denied_retry':
        'Доступ к камере отклонён. Без этого Bagdar не видит препятствий. '
        'Двойной тап — попробовать снова.',
    'calib_no_person':
        'Нет человека в кадре. Наведите камеру и попробуйте снова.',
    'calib_invalid_dist': 'Введите корректное расстояние (0–50 м)',

    'nav_destination': 'пункт назначения',
    'nav_route_built': 'Маршрут построен до',
    'nav_approx': 'Примерно',
    'nav_minutes': 'минут',
    'nav_arrived': 'Вы прибыли к',
    'nav_arrived_short': 'Прибыли.',
    'hud_riding': 'В пути',
    'hud_uturn': 'Разворот',
    'nav_arriving': 'Прибытие.',
    'nav_not_active': 'Навигация не активна.',
    'nav_remaining': 'Осталось',
    'nav_no_gps': 'GPS недоступен.',
    'nav_your_position': 'Ваше положение:',
    'nav_go_straight': 'Идите прямо',
    'nav_turn_left': 'Поверните налево',
    'nav_turn_right': 'Поверните направо',
    'nav_u_turn': 'Развернитесь',
    'nav_turn_around': 'Развернитесь',
    'nav_arrive': 'Прибытие',
    'nav_searching': 'Ищу место...',
    'nav_not_found': 'Место не найдено.',
    'nav_building_route': 'Строю маршрут...',
    'nav_route_failed': 'Не удалось построить маршрут.',
    'nav_stopped': 'Навигация остановлена.',
    'nav_no_api_key': 'Ключ 2GIS не задан. Настройте в настройках.',
    'nav_off_route': 'Вы отклонились от маршрута.',
    'nav_rerouting_try': 'Перестраиваю маршрут.',
    'nav_reroute_failed':
        'Не удалось перестроить маршрут. Остановитесь в безопасном месте и скажите где я.',
    'nav_reroute_ok': 'Новый маршрут готов.',
    'nav_bearing_return': 'Маршрут сзади, разверните телефон и скажите где я.',

    'nav_transit_route_built': 'Маршрут на транспорте до',
    'nav_walk': 'Пешком',
    'nav_take_bus': 'Садитесь на автобус номер',
    'nav_from_stop': 'от остановки',
    'nav_ride_stops': 'Проехать остановок:',
    'nav_wait_bus': 'Ждите автобус номер',
    'nav_at_stop': 'Вы на остановке',
    'nav_exit_now': 'Выходите сейчас! Остановка',
    'nav_stops_remaining': 'Осталось остановок:',
    'nav_boarding_confirmed': 'Вы сели. Отслеживаю остановки.',
    'nav_walking_to_stop': 'Идём к остановке.',
    'nav_waiting': 'Ждём транспорт.',
    'nav_waiting_for': 'Ждём автобус',
    'nav_riding': 'Едем на',
    'nav_walk_to_dest': 'Идём к месту назначения.',
    'nav_nearest_stop': 'Ближайшая остановка',
    'nav_gps_wait': 'Жду сигнал GPS...',
    'nav_gps_unreliable': 'GPS ненадёжен. Навигация приостановлена.',
    'nav_gps_restored': 'GPS восстановлен.',
    'nav_rerouting': 'Перестраиваю маршрут...',
    'nav_auto_boarded': 'Обнаружено движение. Слежу за остановками.',
    'nav_bus_interval': 'Следующий автобус примерно через',
    'nav_bus_minutes': 'минут.',
    'nav_bus_not_running': 'Автобус сейчас не работает.',

    'tl_red': 'Светофор красный. Подождите.',
    'tl_yellow': 'Светофор жёлтый. Подождите.',
    'tl_green': 'Светофор зелёный.',
    'tl_green_safe':
        'Светофор, возможно, зелёный. Прислушайтесь к звукам транспорта.',
    'tl_green_cars': 'Светофор зелёный, но транспорт рядом. Подождите.',
    'tl_unknown': 'Не могу определить цвет светофора. Будьте осторожны.',
    'tl_uncertain': 'Светофор плохо виден или не уверен. Будьте осторожны.',
    'tl_ahead': 'Впереди светофор.',

    'nav_api_key_label': 'Ключ API 2GIS',
    'nav_api_key_hint': 'Введите ключ API',
    'nav_api_key_saved': 'Ключ сохранён.',

    'nav_offline_ready': 'Оффлайн карта загружена.',
    'nav_offline_not_ready': 'Оффлайн карта не загружена. Используется онлайн.',
    'nav_download_map': 'Скачать карту',
    'nav_downloading_map': 'Скачиваю карту...',
    'nav_download_complete': 'Карта скачана.',
    'nav_download_failed': 'Не удалось скачать карту.',
    'nav_download_progress': 'Скачивание',
    'nav_delete_map': 'Удалить карту',
    'nav_map_deleted': 'Карта удалена.',
    'nav_select_city': 'Выберите город',
    'nav_city_astana': 'Астана',
    'nav_city_almaty': 'Алматы',
    'nav_no_map': 'Скачайте карту города для оффлайн навигации.',
    'nav_map_update': 'Доступно обновление карты.',
    'nav_map_stale':
        'Оффлайн карта может быть устаревшей. Проверьте обновление.',
    'nav_map_updated': 'Карта обновлена.',
    'nav_disk_space': 'Недостаточно места на диске.',
    'nav_surface_gravel': 'Грунтовая дорога.',
    'nav_surface_unpaved': 'Дорога без покрытия.',
    'nav_tactile_yes': 'Тактильная плитка.',
    'nav_steps_ahead': 'Впереди ступеньки.',
    'nav_no_sidewalk': 'Нет тротуара.',

    'gtfs_route_info': 'Маршрут',
    'gtfs_schedule': 'Расписание',
    'gtfs_working_hours': 'Время работы',
    'gtfs_interval': 'Интервал',
    'gtfs_minutes': 'минут',
    'gtfs_stops_count': 'Остановок',
    'gtfs_from': 'От',
    'gtfs_to': 'До',
    'gtfs_not_found': 'Маршрут не найден.',
    'gtfs_stale': 'Расписание может быть устаревшим. Проверьте обновление.',
    'gtfs_bus_routes': 'Маршруты автобусов на остановке',

    'tts_lang_title': 'Голос не найден',
    'tts_lang_body':
        'Голосовой пакет для выбранного языка не установлен. '
        'Откройте Настройки → Специальные возможности → '
        'Синтез речи и установите голос для нужного языка.',
    'tts_lang_open': 'Понятно',

    'sem_step_of': 'Шаг {step} из {total}',
    'sem_required': 'Обязательно',
    'sem_optional_perm': 'Необязательно',
    'sem_done': 'Выполнено',
    'sem_not_done': 'Не выполнено',
    'sem_on': 'включено',
    'sem_off': 'выключено',

    'tts_kk_guide_title': 'Установите казахский голос',
    'tts_kk_guide_body':
        'Для качественного казахского произношения установите голосовой пакет. '
        'Откройте Настройки → Специальные возможности → '
        'Синтез речи → Установить голосовые данные → Казахский.',
    'tts_kk_open_settings': 'Открыть настройки TTS',
    'tts_kk_not_available':
        'Казахский голос не найден. Голосовой помощник работает с русским акцентом.',

    'lang_switched': 'Язык изменён.',

    'pref_clear_path_announce': 'Озвучка «Путь свободен»',
    'pref_battery_announce': 'Озвучка заряда батареи',
    'pref_mode_announce': 'Озвучка смены режима',

    'vc_speed_up': 'Речь ускорена.',
    'vc_speed_down': 'Речь замедлена.',
    'vc_volume_up': 'Громкость увеличена.',
    'vc_volume_down': 'Громкость уменьшена.',
    'vc_battery_status': 'Заряд {battery} процентов.',

    'audio_tour':
        'Вы на главном экране. '
        'Камера уже работает и сканирует окружение. '
        'Проведите влево или вправо для смены режима. '
        'Удерживайте палец для голосовой команды. '
        'Проведите вверх для справки.',
    'audio_tour_done': 'Удачного пользования!',

    'onb_sos_title': 'Экстренный контакт',
    'onb_sos_sub':
        'Укажите номер близкого человека.\\nBagdar отправит SMS с вашим местоположением при экстренном вызове.',
    'onb_sos_tts':
        'Укажите номер для экстренных ситуаций. '
        'Bagdar отправит SMS с вашей локацией. '
        'Можно пропустить и настроить позже.',
    'onb_sos_placeholder': '+7 (___) ___-__-__',
    'onb_sos_save': 'Сохранить контакт',
    'onb_sos_skip': 'Настрою позже',

    'settings_calibration': 'Калибровка камеры',
    'settings_calibration_desc': 'Встаньте точно на 2 м от человека и нажмите',
    'settings_read_text': 'Прочитать текст',
    'settings_read_text_desc': 'OCR — распознавание текста в кадре',
    'settings_cpu_threads': 'CPU потоки',
    'settings_lang_label': 'Язык / Тіл',
    'settings_earcon_title': 'Звуковые сигналы',
    'settings_earcon_desc': 'Мгновенные тоны для событий',
    'settings_depth_active': 'Анализ глубины: активен',
    'settings_depth_not_ready': 'Анализ глубины: не готов',
    'settings_scan_left': 'Что слева?',
    'settings_scan_forward': 'Что впереди?',
    'settings_scan_right': 'Что справа?',
    'settings_haptic_test': 'Тест вибрации (режим Трость)',
    'settings_earcon_test': 'Тест звуковых сигналов',
    'settings_sos_not_set': 'Не задан',

    'path_clear_minimal': 'Анализ активен.',
    'hazard_stairs_down_minimal': 'Лестница. Стоп.',
    'hazard_overhead_minimal': 'Препятствие. Стоп.',
    'camera_blocked_minimal': 'Камера закрыта.',

    'scene_see_count': 'Вижу {count} объектов.',
    'scene_see_one': 'Вижу один объект.',
    'scene_see_none': 'Ничего не распознано.',
    'scene_object_entry': '{label} {direction}',
    'scene_object_dist': ', примерно {dist}',
    'scene_object_approaching': ', приближается',
    'scene_hazard_intro': 'На земле:',
    'scene_traffic_light': 'Светофор {color}.',
    'scene_color_red': 'красный',
    'scene_color_yellow': 'жёлтый',
    'scene_color_green': 'зелёный',
    'scene_ocr_read': 'Надпись: {text}.',
    'scene_left_only': 'Слева:',
    'scene_right_only': 'Справа:',
    'scene_ahead_only': 'Впереди:',
    'scene_narrating': 'Описываю...',
    'scene_cooldown': 'Подождите перед повторным описанием.',

    'sms_payment_received': 'Поступило',
    'sms_payment_sent': 'Списано',
    'sms_payment_from': 'от',
    'sms_balance': 'Баланс',
    'sms_currency_kzt': 'тенге',
    'sms_currency_rub': 'рублей',
    'sms_currency_usd': 'долларов',
    'sms_currency_eur': 'евро',
    'sms_notifications_enabled': 'Уведомления о платежах включены.',
    'sms_notifications_disabled': 'Уведомления о платежах выключены.',
    'sms_permission_denied':
        'Нет разрешения на чтение входящих СМС. Откройте настройки и разрешите доступ.',
    'acoustic_vehicle_left': 'Машина слева.',
    'acoustic_vehicle_right': 'Машина справа.',
    'acoustic_vehicle_behind': 'Звук машины.',
    'acoustic_horn': 'Сигнал!',
    'acoustic_siren': 'Сирена рядом.',
    'acoustic_dog': 'Собака рядом.',
    'acoustic_dog_left': 'Собака слева.',
    'acoustic_dog_right': 'Собака справа.',
    'acoustic_crowd_dense': 'Людное место.',
    'acoustic_construction': 'Стройка рядом.',
    'awm_enabled': 'Акустика включена.',
    'awm_disabled': 'Акустика выключена.',

    'shelf_camera_short': 'Камера',
    'shelf_read_short': 'Читать',
    'shelf_navigate_short': 'Куда',
    'shelf_camera_label': 'Камера. Активна.',
    'shelf_camera_hint': 'Двойное касание — вернуться к обычному режиму.',
    'shelf_read_label': 'Читать вслух то, что видит камера.',
    'shelf_read_hint': 'Двойное касание — начать чтение.',
    'shelf_navigate_label': 'Проложить маршрут голосом.',
    'shelf_navigate_hint': 'Двойное касание — выбрать место назначения.',
    'shelf_read_started': 'Читаю что вижу. Держите телефон ровно.',
    'shelf_navigate_started': 'Куда вести? Скажите название места.',
    'shelf_cane_confirm': 'Удерживайте секунду, чтобы переключить режим.',
    'ocr_aim_hint': 'Поднесите текст ближе и держите камеру ровно.',
    'ocr_timeout': 'Не нашёл текст за восемь секунд. Попробуйте ещё раз.',
    'ocr_lines_count': 'Нашёл {n} строк. Читаю.',
    'processing_heartbeat': 'Анализирую... подождите.',
    'pitch_black_heartbeat': '',
    'offline_banner_no_gps': 'Без сигнала GPS. Положение приблизительное.',
    'offline_banner_no_map':
        'Карта района не загружена. Скажите "загрузи карту".',
    'settings_save_failed':
        'Не удалось сохранить настройку. Попробуйте ещё раз.',
    'theme_selected_dark': 'Тёмная тема, чёрный экран и жёлтый акцент.',
    'theme_selected_light': 'Светлая тема, белый экран и тёмно-синий акцент.',
    'theme_selected_high_contrast': 'Высокий контраст, только белое на чёрном.',
    'theme_selected_warm':
        'Тёплая тема, кремовый экран и тёмно-коричневый текст.',
    'voice_layer_listening': 'Слушаю команду.',
    'voice_layer_cancel': 'Отменить прослушивание.',
    'restart_pipeline': 'Перезапустить распознавание.',
    'restart_pipeline_done': 'Распознавание перезапущено.',
    'lang_pack_required_for_kk':
        'Для лучшего распознавания казахского скачайте языковой пакет.',
    'lang_pack_downloading': 'Скачиваю казахский языковой пакет.',
    'lang_pack_install_complete': 'Казахский языковой пакет установлен.',
    'lang_pack_install_failed': 'Не удалось установить казахский пакет.',
    'lang_pack_offline_skip': 'Нет сети. Запрошу при следующем подключении.',
    'vosk_kk_loading': 'Готовлю казахское распознавание.',
    'vosk_kk_load_failed':
        'Не удалось загрузить казахское распознавание. Использую запасной вариант.',
    'lang_packs_screen_title': 'Языковые пакеты',
    'lang_packs_screen_intro': 'Управление языковыми пакетами для казахского.',
    'lang_packs_v2_toggle_label': 'Улучшенное казахское распознавание',
    'lang_packs_v2_toggle_desc':
        'Использовать Vosk для распознавания казахской речи. Требуется языковой пакет.',
    'lang_packs_v2_enabled': 'Улучшенное распознавание включено.',
    'lang_packs_v2_disabled': 'Улучшенное распознавание выключено.',
    'lang_packs_refresh': 'Обновить список',
    'lang_packs_refresh_done': 'Список пакетов обновлён.',
    'lang_packs_refresh_failed': 'Не удалось обновить список. Проверьте сеть.',
    'lang_packs_install': 'Установить',
    'lang_packs_delete': 'Удалить',
    'lang_packs_update': 'Обновить',
    'lang_packs_installed': 'Установлен',
    'lang_packs_not_installed': 'Не установлен',
    'lang_packs_size_mb': '{size} МБ',
    'lang_packs_no_packs': 'Языковые пакеты не найдены. Нажмите «Обновить».',
    'lang_packs_close': 'Закрыть',
    'lang_packs_delete_confirm': 'Удалить пакет {name}?',
    'voice_kk_v2_pack_missing':
        'Пакет не установлен. Откройте языковые пакеты для установки.',
    'voice_manage_lang_packs_announce': 'Открываю языковые пакеты.',
    'onb_kk_pack_prompt_title': 'Казахское распознавание',
    'onb_kk_pack_prompt_body':
        'Скачать пакет казахского распознавания сейчас? Около 50 МБ.',
    'onb_kk_pack_yes': 'Скачать',
    'onb_kk_pack_skip': 'Пропустить',
    'onb_kk_pack_later': 'Напомнить в сети',
    'lang_pack_online_ready':
        'Сеть восстановлена. Пакет казахского распознавания готов к установке. Скажите «языковые пакеты».',

    'tts_kk_engine_system': 'Системный казахский голос',
    'tts_kk_engine_rhvoice': 'RHVoice (Aigul)',
    'tts_kk_engine_espeak': 'espeak-ng (резервный)',
    'tts_kk_engine_fallback_ru': 'Русское чтение казахского текста',
    'tts_kk_using_rhvoice': 'Использую RHVoice для казахского.',
    'tts_kk_using_espeak':
        'Использую базовый казахский голос. Произношение может быть упрощённым.',
    'tts_kk_using_system': 'Использую системный казахский голос.',
    'tts_kk_using_russian_fallback':
        'Казахский голос недоступен. Читаю казахский текст русским голосом.',
    'tts_kk_engine_load_failed':
        'Не удалось загрузить казахский голос. Перехожу на запасной вариант.',
    'onb_rhvoice_pack_prompt_title': 'Лучший казахский голос',
    'onb_rhvoice_pack_prompt_body':
        'Скачать высококачественный казахский голос сейчас? Около 30 МБ. Голос работает без интернета.',
    'onb_rhvoice_pack_yes': 'Скачать',
    'onb_rhvoice_pack_skip': 'Пропустить',
    'onb_rhvoice_pack_later': 'Напомнить в сети',
    'lang_pack_rhvoice_online_ready':
        'Сеть восстановлена. Пакет казахского голоса готов к установке. Скажите «языковые пакеты».',

    'trail_recording_started': 'Запись маршрута начата. Идите к цели.',
    'trail_recording_stopped': 'Маршрут сохранён.',
    'trail_recording_failed': 'Не удалось начать запись маршрута.',
    'trail_recording_empty': 'Маршрут пуст, не сохранён.',
    'trail_recording_cancelled': 'Запись маршрута отменена.',
    'trail_landmark_added': 'Ориентир отмечен.',
    'trail_replay_started': 'Следую по маршруту.',
    'trail_replay_stopped': 'Повтор маршрута остановлен.',
    'trail_not_found': 'Маршрут не найден.',
    'trail_deleted': 'Маршрут удалён.',
    'trail_arrived': 'Вы на месте.',
    'trail_lost': 'Маршрут потерян. Вернитесь назад.',
    'trail_continue_straight': 'Продолжайте прямо, осталось {n} шагов.',
    'trail_turn_left': 'Поверните налево.',
    'trail_turn_right': 'Поверните направо.',
    'trail_slight_left': 'Немного влево.',
    'trail_slight_right': 'Немного вправо.',

    'bazaar_mode_on': 'Режим базара включён.',
    'bazaar_mode_off': 'Режим базара выключен.',
    'livestock_mode_on': 'Режим животных включён.',
    'livestock_mode_off': 'Режим животных выключен.',
    'livestock_cow': 'Корова',
    'livestock_horse': 'Лошадь',
    'livestock_sheep': 'Овца',
    'livestock_dog': 'Собака',
    'livestock_cat': 'Кошка',
    'livestock_bird': 'Птица',

    'voice_adapt_on':
        'Адаптация голоса включена. Данные остаются на устройстве.',
    'voice_adapt_off': 'Адаптация голоса выключена.',
    'voice_adapt_samples_cleared': 'Данные адаптации удалены.',

    'mesh_hazard_generic': 'Другой пользователь сообщил о препятствии рядом.',
    'mesh_hazard_pothole': 'Другой пользователь сообщил о яме рядом.',
    'mesh_hazard_construction': 'Другой пользователь сообщил о стройке рядом.',
    'mesh_hazard_ice': 'Другой пользователь сообщил о гололёде рядом.',
    'mesh_hazard_stairs': 'Другой пользователь сообщил о лестнице рядом.',
    'mesh_buddy_started': 'Сеть помощников включена.',
    'mesh_buddy_stopped': 'Сеть помощников выключена.',
    'mesh_buddy_no_ble':
        'Bluetooth не поддерживается. Сеть помощников недоступна.',

    'oscp_near_field': 'Трость: препятствие впереди',
    'oscp_connected': 'Трость подключена.',
    'oscp_disconnected': 'Трость отключена.',
    'oscp_battery_low': 'Низкий заряд трости.',
    'oscp_no_ble': 'Bluetooth не поддерживается. Трость недоступна.',

    'near_miss_recorded': 'Опасная ситуация записана.',
    'near_miss_cleared': 'Записи опасных ситуаций удалены.',

    'vlm_loading': 'Загружаю модель описания сцены.',
    'vlm_ready': 'Модель описания готова.',
    'vlm_not_available':
        'Описание сцены недоступно. Нужна зарядка и свободная память.',
    'vlm_thinking': 'Думаю...',
    'vlm_answer_fallback':
        'Модель не ответила. Использую стандартное описание.',

    'sonar_near_field': 'Эхолот: объект впереди',
    'sonar_started': 'Эхолот включён.',
    'sonar_stopped': 'Эхолот выключен.',
    'sonar_calibrating': 'Калибрую эхолот.',
    'sonar_no_48k': 'Микрофон не поддерживает эхолот.',
    'onb_mic_prime_tts':
        'Для голосового управления мне нужен доступ к микрофону. Сейчас появится системный диалог.',
    'onb_mic_denied_fallback_tts':
        'Доступ к микрофону отклонён. Голосовое управление отключено. Пожалуйста, используйте жесты для настройки.',
    'onb_mode_confirm_prompt':
        'Режим выбран. Скажите да для продолжения или назовите другой режим.',
    'sos_setup_prompt_tts':
        'Пожалуйста, укажите телефон близкого человека для экстренной помощи SOS.',
    'camera_perm_recovery_tts':
        'Доступ к камере заблокирован. Пожалуйста, разрешите доступ в настройках телефона. Дважды коснитесь для настроек, один раз для повтора.',
    'onb_help_prompt_lang':
        'Выберите язык. Произнесите: Русский, Казахский или Английский.',
    'onb_help_prompt_hand': 'Выберите ведущую руку. Скажите: Правая или Левая.',
    'onb_help_prompt_mode':
        'Выберите режим по умолчанию. Скажите: Улица, Трость или Сканирование.',
    'onb_help_prompt_perm': 'Разрешите доступ к камере. Скажите: Разрешить.',
    'onb_help_prompt_calib':
        'Калибровка расстояния. Скажите: Да для продолжения.',
    'onb_help_prompt_ready': 'Все готово. Скажите: Да чтобы начать.',
    'onb_emergency_skip_confirm':
        'Вы хотите пропустить всю настройку приложения? Двойной тап подтвердит. Один тап отменит.',
  },

  AppLanguage.kk: {
    'stop': 'Тоқта',
    'close': 'жақын',
    'approaching': 'жақындап келеді',
    'transport_approaching': 'Көлік жақындап келеді',
    'object_approaching': 'Нысан жақындап келеді',
    'synth_event_stop_left': 'Тоқта! Сол жақтан',
    'synth_event_stop_right': 'Тоқта! Оң жақтан',
    'synth_event_stop_center': 'Тоқта! Тура алдыңда',
    'sign': 'Белгі',
    'path_clear': 'Талдау белсенді.',
    'path_clear_cane': 'Талдау белсенді.',
    'path_clear_label': 'Талдау белсенді',
    'no_change': 'Жағдай өзгерген жоқ.',
    'nothing_seen': 'Ештеңе көрінбейді.',
    'nothing_here': 'Ештеңе жоқ',
    'left': 'солда',
    'right': 'оңда',
    'forward_loc': 'алда',
    'closest': 'Жақын нысан',
    'meters': 'метрде',
    'approx_meters': 'м',
    'now_imminent': 'қазір',
    'hazard_dead_zone': 'Аяқ маңында қауіп',
    'hazard_step_down': 'Төмен баспалдақ',
    'hazard_step_up': 'Жоғары баспалдақ',
    'hazard_pothole': 'Шұңқыр',
    'hazard_curb': 'Бордюр',
    'hazard_stairs_down': 'Төмен баспалдақ. Тоқтаңыз.',
    'hazard_overhead': 'Кеуде деңгейінде кедергі бар. Тоқтаңыз.',
    'hazard_unknown': 'Кедергі',
    'hazard_glass_door': 'Алда шыны есік болуы мүмкін. Сақ болыңыз.',
    'hazard_slippery': 'Абайлаңыз, тайғанақ болуы мүмкін.',
    'hazard_warning': 'Мүмкін кедергі —',
    'phone_tilted_sideways': 'Телефон еңкейген.',

    'deviate': 'Ауытқыңыз',
    'passage': 'Өту',
    'maneuver_ok': 'Жақсы.',
    'nav_left': 'солға',
    'nav_right': 'оңға',
    'nav_slight_left': 'сәл солға',
    'nav_slight_right': 'сәл оңға',
    'straight': 'тура',

    'corridor_blocked': 'Жол бөгелген.',
    'narrow': 'Тар.',

    'status_no_obstacle': 'Талдау белсенді',
    'status_analysis_active': 'Талдау белсенді',
    'spatial_analysis_limited':
        'Кеңістікті талдау шектеулі. Таяқты пайдаланыңыз.',
    'spatial_stop_sensing_unavailable':
        'Тоқтаңыз. Кеңістікті талдау қолжетімсіз.',
    'core_health_sound_unavailable':
        'Дыбыс қолжетімсіз. Діріл ескертулері жұмыс істейді.',
    'core_health_haptic_unavailable':
        'Діріл қолжетімсіз. Дауыстық ескертулер қалады.',
    'core_health_recovered': 'Жүйе қалпына келді.',
    'core_health_status': 'Жүйе күйі',
    'generic_obstacle_ahead': 'Алда кедергі.',
    'generic_obstacle_stop': 'Тоқтаңыз. Алда кедергі.',
    'generic_obstacle_left': 'Солда кедергі.',
    'generic_obstacle_right': 'Оңда кедергі.',
    'generic_obstacle_overhead': 'Тоқтаңыз. Бас деңгейінде кедергі.',
    'generic_vehicle_ahead': 'Алда көлік.',
    'generic_vehicle_left': 'Солда көлік.',
    'generic_vehicle_right': 'Оңда көлік.',
    'status_scanning': 'Сканерлеу...',
    'status_waiting': 'күту',
    'dist_safe': 'қауіпсіз',
    'dist_attention': 'назар',
    'dist_stop': 'тоқта',
    'lbl_object': 'Нысан',
    'lbl_status': 'Күй',
    'lbl_total_objects': 'Барлық нысандар',

    'scan_left': 'Солда',
    'scan_forward': 'Алда',
    'scan_right': 'Оңда',
    'scan_see': 'Көремін',

    'ocr_reading': 'Оқып жатырмын...',
    'ocr_not_found': 'Мәтін табылмады.',
    'ocr_camera_not_ready': 'Камера дайын емес.',

    'ocr_low_memory':
        'Мәтінді тану үшін жады жетпейді. Басқа қосымшаларды жауып, қайта көріңіз.',
    'ocr_paddle_init_failed':
        'Жетілдірілген тануды іске қосу мүмкін болмады. Стандартты нұсқаны қолданамын.',

    'camera_unavailable': 'Камера қолжетімсіз.',
    'camera_not_found': 'Камера табылмады',
    'camera_started': 'Камера қосылды',
    'system_ready': 'Жүйе дайын',
    'core_feature_unavailable': 'Бұл функция осы құрастырмада қолжетімсіз.',
    'init_failed':
        'Жүйені іске қосу сәтсіз. Тоқтаңыз. Қосымшаны қайта іске қосыңыз.',
    'camera_init_failed_critical':
        'Камера қатесі. Тану қолжетімсіз. Қосымшаны қайта іске қосыңыз.',
    'mode_changed': 'Режим',

    'calib_aim': 'Калибрлеу үшін камераны адамға бағыттаңыз.',
    'calib_saved': 'Калибрлеу сақталды.',
    'calib_recommend':
        'Дәл қашықтықты анықтау үшін баптауларда калибрлеуді ұсынамыз.',

    'onb_welcome_tts':
        'Bagdar-ға қош келдіңіз. Режимді таңдаңыз. '
        'Жоғары немесе төмен сипау — режим, қос тию — таңдау.',
    'onb_welcome_intro_tts':
        'Сәлеметсіз бе. Бағдар — бұл көру қабілеті шектелген жандарға арналған, кеңістікте бағдарлауға және кедергілерді айналып өтуге көмектесетін дауыстық көмекші. Баптауды бастайық. Тілді таңдаңыз. Солға немесе оңға свайп арқылы тілді ауыстырыңыз, ал қосарлы тартумен таңдаңыз. Немесе дауыстап айтыңыз: Қазақша, Орысша немесе Ағылшынша.',
    'onb_dominant_hand_tts':
        'Бірінші қадам. Ведущая қолды таңдаңыз. Бұл экрандағы қимылдардың орналасуына әсер етеді. Таңдау үшін жоғары немесе төмен свайп жасаңыз. Растау үшін екі рет басыңыз. Немесе дауыстап айтыңыз: Оң қол, немесе Сол қол.',
    'onb_mode_tts':
        'Екінші қадам. Әдепкі жұмыс режимін таңдаңыз. Режимді өзгерту үшін жоғары немесе төмен свайп жасаңыз. Растау үшін екі рет басыңыз. Немесе дауыстап айтыңыз: Көше, Таяқ, немесе Сканерлеу.',
    'onb_perm_tts':
        'Камераға рұқсат. Қос тию — жүйелік сұрауды ашу. Рұқсат беру түймесін табыңыз. Немесе дауыстап айтыңыз: Рұқсат ету.',
    'onb_calib_tts':
        'Қашықтықты калибрлеу. Дәлдікті арттыру үшін калибрлеу ұсынылады. Оны баптаулар мәзірінде сізден екі метр қашықтықта тұрған адамға камераны бағыттау арқылы орындай аласыз. Жалғастыру үшін екі рет басыңыз.',
    'onb_ready_tts': 'Бәрі дайын. Қос тию — бастау.',
    'onb_hand_right': 'Оң қол',
    'onb_hand_left': 'Сол қол',
    'onb_hand_changed': 'Жетекші қол {hand} болып өзгертілді',
    'onb_secondary_aid_tts':
        'Bagdar кедергілер туралы ескертеді, бірақ оларды жіберіп алуы мүмкін. '
        'Ақ таяқты немесе жолбасшы итті пайдалануды жалғастырыңыз. '
        'Bagdar — қосымша құрал.',
    'onb_secondary_aid_check': 'Bagdar — қосымша құрал, таяқтың орнына емес',
    'onb_blind_intro':
        'Bagdar — көрмейтіндерге арналған. Қимылдармен басқару. '
        'Бір тию — қайталау. Қос тию — жалғастыру. '
        'Оңға сипау — келесі қадам, солға — артқа. '
        'Ұзақ басу — тілді ауыстыру. '
        'Егер жаныңызда жақын адамыңыз болса, оған телефонды алғашқы баптау үшін беру ұсынылады.',
    'onb_gesture_help':
        'Онбординг қимылдары. Бір тию — нұсқауды қайталау. '
        'Қос тию — негізгі әрекет. Оңға немесе солға сипау — навигация. '
        'Ұзақ басу — тілді ауыстыру. Төмен сипау — онбордингті өткізу. '
        'Екі саусақпен екі секунд — шұғыл шығу.',
    'onb_mode_select_announce': 'Режим: {mode}. Қос тию — таңдау.',
    'onb_skip_confirm':
        'Барлық қолданба реттеулерін өткізіп жіберу керек пе? Қос түртіңіз растайды. Бір түрту болдырмайды.',
    'onb_skip_cancelled': 'Болдырылмады.',
    'onb_lang_switched': 'Тіл: қазақша.',
    'onb_calib_saved_tts':
        'Тамаша! Калибрлеу сақталды. Жалғастыру түймесін басыңыз.',
    'onb_calib_skip_tts':
        'Калибрлеу өткізілді. Оны кейін баптауларда орындай аласыз.',
    'onb_welcome_title': 'Bagdar\nқосымшасына қош келдіңіз',
    'onb_welcome_sub':
        'Әдепкі режимді таңдаңыз.\nОны кез келген уақытта өзгертуге болады.',
    'onb_perm_title': 'Рұқсат қажет',
    'onb_perm_sub': 'Тек камера міндетті.\nҚалғандары — қалауыңыз бойынша.',
    'onb_calib_title': 'Қашықтық дәлдігі',
    'onb_calib_sub':
        'Калибрлеусіз қателік ~40%.\nКалибрлеуден кейін — ~10%. 10 секунд кетеді.',
    'onb_calib_app_note':
        'Калибрлеуді іске қосқаннан кейін Баптауларда орындауға болады.',
    'onb_ready_title': 'Бәрі дайын!',
    'onb_ready_sub': 'Bagdar дайын. Қосымшаның мүмкіндіктері:',
    'onb_btn_continue': 'Жалғастыру',
    'onb_btn_allow_camera': 'Камераға рұқсат беру',
    'onb_btn_skip': 'Қалғанын өткізу',
    'onb_btn_calibrate': 'Мен 2 метрде тұрмын — калибрлеу',
    'onb_btn_skip_calib': 'Өткізу — кейін баптаймын',
    'onb_btn_calib_later': 'Баптауларда калибрлеймін',
    'onb_btn_start': 'Бастау',
    'onb_btn_back_calib': 'Калибрлеуге оралу',
    'onb_calib_done': 'Калибрлеу орындалды — дәлдік жақсарды!',
    'onb_calib_hint': 'Біреуден сізден 2 м қашықтықта тұруды сұраңыз',
    'onb_check_alerts': 'Нысандар туралы дауыстық ескертулер',
    'onb_check_mode': 'әдепкі ретінде таңдалды',
    'onb_check_calib': 'Камераны калибрлеу',
    'onb_check_calib_skip': 'Баптаулар → Камераны калибрлеу',
    'onb_feat_scan': '«Айналада не бар?» түймесі — көріністі сипаттау',
    'onb_feat_mode': 'Режим белгішесі — ауыстыру Көше / Таяқ / Скан',
    'onb_feat_settings': 'Баптаулар — калибрлеу, GPU, Debug HUD',
    'onb_lang_title': 'Тілді таңдаңыз',
    'onb_lang_sub': 'Тілді баптауларда өзгертуге болады',
    'onb_mic_exhausted':
        'Жауабыңызды естімей тұрмын. Қимылдарды қолданыңыз: '
        'таңдау үшін жоғары не төмен сырғытыңыз, растау үшін екі рет түртіңіз. '
        'Қайталау үшін экранды бір рет түртіңіз.',
    'onb_mode_choose_first':
        'Алдымен режимді таңдаңыз. Айтыңыз: көше, таяқ немесе шолу.',
    'onb_perm_talkback_guide':
        'Қазір рұқсат сұрайтын жүйелік диалогтар пайда болады. '
        'Олар үшеу: камера, микрофон және геолокация. '
        'TalkBack қолданыңыз — Рұқсат ету батырмасына оңға сырғытып, екі рет түртіңіз. '
        'Мен күтемін.',
    'onb_perm_tap_guide':
        'Қазір жүйелік диалогтар пайда болады. '
        'Әрбірінде экранның төменгі жағындағы Рұқсат ету батырмасын басыңыз. '
        'Маңайыңызда көмекші болса, көмек сұраңыз. Мен күтемін.',
    'onb_perm_camera_ok': 'Камераға рұқсат берілді.',
    'onb_perm_mic_ok': 'Микрофонға рұқсат берілді.',
    'onb_perm_all_granted':
        'Барлық рұқсаттар алынды. Тамаша! Келесі қадамға өтеміз.',
    'onb_perm_denied_retry':
        'Камераға рұқсат берілмеді. Камерасыз қолданба кедергілерді көрмейді. '
        'Қайталау үшін «рұқсат» деңіз, немесе «өткізіп жіберу» деңіз.',

    'tut_title': 'Қимылдарға үйрету',
    'tut_intro':
        'Қазір сіз қосымшаны басқаруды үйренесіз. '
        'Дауыстық нұсқауларға еріңіз. '
        'Қалаған сәтте өткізіп жіберуге болады.',
    'tut_tap': 'Экранға бір рет түртіңіз.',
    'tut_tap_done': 'Тамаша! Бір рет түрту — жылдам күй: режим және заряд.',
    'tut_double_tap': 'Енді жылдам екі рет түртіңіз.',
    'tut_double_tap_done': 'Жарайсыз! Екі рет түрту баптауларды ашады.',
    'tut_long_press': 'Саусақты экранда бір секунд ұстаңыз.',
    'tut_long_press_done': 'Керемет! Ұзақ басу — дауыстық команда.',
    'tut_swipe_horizontal': 'Саусақпен оңға не солға сырғытыңыз.',
    'tut_swipe_horizontal_done': 'Дұрыс! Көлденең сырғыту режимді ауыстырады.',
    'tut_swipe_up': 'Енді саусақпен жоғары сырғытыңыз.',
    'tut_swipe_up_done': 'Дұрыс! Жоғары сырғыту анықтаманы ашады.',
    'tut_swipe_down_legacy': 'Енді саусақпен төмен сырғытыңыз.',
    'tut_swipe_down_legacy_done': 'Дұрыс! Төмен сырғыту анықтаманы ашады.',
    'tut_two_finger': 'Екі саусақты қатар қойып, бір жарым секунд ұстаңыз.',
    'tut_two_finger_done':
        'Жарайсыз! Екі саусақпен бір жарым секунд ұстау SOS шақырады.',
    'tut_finished':
        'Үйрету аяқталды. Сондай-ақ SOS және анықтама үшін дауыстық командалар қолжетімді.',
    'tut_skip': 'Өткізіп жіберу',
    'tut_replay': 'Қимылдарға үйретуді қайталау',
    'tut_finish': 'Аяқтау',
    'tut_progress': '{total} қадамнан {step}',
    'tut_fail_hint':
        'Қиын ба? "Өткіз" десеңіз келесіге өтесіз. '
        'Немесе "қайтала" деңіз — нұсқау тағы айтылады.',
    'tut_detail_tap':
        'Саусақпен экранды бір рет жылдам түртіп, бірден алыңыз. '
        'Бұл қысқа тию, ұстамаңыз.',
    'tut_detail_doubleTap':
        'Экранды жылдам екі рет түртіңіз. '
        'Тиюлер арасы жарты секундтан аз болсын.',
    'tut_detail_longPress':
        'Саусақты экранға басып, бір секундтай ұстаңыз, '
        'растау дыбысын естігенше.',
    'tut_detail_swipeHorizontal':
        'Саусақты экранға қойып, оңға не солға тез сырғытыңыз. '
        'Қозғалыс үздіксіз болуы керек.',
    'tut_detail_swipeVertical':
        'Саусақты қойып, жоғары не төмен жылдам сырғытыңыз.',
    'tut_detail_twoFinger':
        'Екі саусақты қатар экранға қойып, '
        'бір жарым секунд ұстаңыз.',

    'mode_street': 'Көше',
    'mode_cane': 'Таяқ',
    'mode_scan': 'Сканерлеу',
    'mode_street_desc': 'Көліктер, адамдар, кедергілер — толық ескерту',
    'mode_cane_desc': 'Жиі діріл, сөз ең аз',
    'mode_scan_desc': 'Әр 4 секунд сайын қоршаған ортаны сипаттау',

    'perm_camera': 'Камера',
    'perm_camera_reason': 'Қосымшаның негізгі функциясы',
    'perm_camera_required': 'Міндетті',
    'perm_mic': 'Микрофон',
    'perm_mic_reason': 'Дауыстық командалар (болашақ функция)',
    'perm_location': 'Геолокация',
    'perm_location_reason': 'SOS режимі — жақындарыңызға орынды жіберу',
    'perm_optional': 'Кейін',

    'settings': 'Баптаулар',
    'settings_a11y_title': 'Арнайы мүмкіндіктер',
    'settings_classic_gestures': 'Классикалық қимылдар',
    'settings_classic_gestures_desc':
        'Жоғары сырғыту — перде, төмен сырғыту — анықтама',
    'settings_speech_rate': 'Сөйлеу жылдамдығы',
    'settings_tts_volume': 'Сөйлеу дауысы',
    'settings_earcon_volume': 'Дыбыс деңгейі',
    'settings_verbosity': 'Толықтық',
    'verbosity_minimal': 'Қысқа',
    'verbosity_normal': 'Қалыпты',
    'verbosity_detailed': 'Толық',
    'settings_alert_frequency': 'Ескерту жиілігі',
    'freq_rare': 'Сирек',
    'freq_normal': 'Қалыпты',
    'freq_frequent': 'Жиі',
    'settings_haptic_strength': 'Діріл күші',
    'haptic_weak': 'Әлсіз',
    'haptic_normal': 'Орта',
    'haptic_strong': 'Күшті',
    'settings_sos_trigger': 'SOS триггері',
    'sos_trigger_two_finger': 'Екі саусақ 2 сек',
    'sos_trigger_triple_tap': 'Үш рет түрту',
    'sos_trigger_shake': 'Сілку',
    'settings_dominant_hand': 'Негізгі қол',
    'hand_right': 'Оң',
    'hand_left': 'Сол',
    'cancel': 'Болдырмау',
    'save': 'Дайын',
    'ok': 'ОК',

    'backup_section_title': 'Баптаулардың сақтық көшірмесі',
    'backup_show_qr': 'Баптаулар QR-ын көрсету',
    'backup_show_qr_subtitle': 'Баптауларды көшіру үшін жақыныңызға көрсетіңіз',
    'backup_scan_qr': 'Баптаулар QR-ын сканерлеу',
    'backup_scan_qr_subtitle': 'Басқа құрылғыдағы QR-ды оқыңыз',
    'qr_dismiss': 'Жабу',
    'qr_export_title': 'Баптаулар QR-ы',
    'qr_export_ready':
        'QR дайын. Баптауларды көшіру үшін жақыныңызға көрсетіңіз.',
    'qr_export_hint':
        'Бұл QR-ды жақыныңызға немесе басқа құрылғыға көрсетіңіз.',
    'qr_export_footer': 'SOS контактісі берілмейді.',
    'qr_export_semantics': 'Қолжетімділік баптауларының QR-коды',
    'qr_import_title': 'QR сканерлеу',
    'qr_import_aim_camera': 'Камераны баптаулар QR-ына бағыттаңыз.',
    'qr_import_aim_hint': 'Камераны QR-кодқа бағыттаңыз.',
    'qr_import_torch': 'Жарық',
    'qr_import_found': 'QR табылды',
    'qr_import_version': 'нұсқа',
    'qr_import_lang': 'тіл',
    'qr_import_speech_rate': 'сөйлеу жылдамдығы',
    'qr_import_tts_volume': 'сөйлеу дауысы',
    'qr_import_earcon_volume': 'дыбыс деңгейі',
    'qr_import_hold_to_apply':
        'Қолдану үшін батырманы 1,5 секунд ұстап тұрыңыз.',
    'qr_import_long_press': 'Ұстап тұрыңыз — Қолдану',
    'qr_import_applying': 'Қолдануда...',
    'qr_import_applied': 'Баптаулар қолданылды.',
    'qr_import_failed': 'QR-ды қолдану мүмкін болмады. Қайталап көріңіз.',
    'qr_import_retry': 'Қайта сканерлеу',

    'voice_listening': 'Тыңдап жатырмын...',
    'voice_not_available': 'Дауыстық командалар қолжетімсіз.',
    'voice_no_permission': 'Микрофонға рұқсат жоқ.',
    'voice_unknown': 'Команда танылмады.',
    'voice_listen_error': 'Естімедім. Қайталаңыз.',
    'voice_hint': 'Дауыстық команда үшін экранды ұстап тұрыңыз.',
    'voice_commands_list':
        'Қол жетімді командалар: айналада не бар, солда, оңда, '
        'алда, оқы, режим, қара экран.',
    'voice_settings_commands':
        'Баптау командалары: жылдамырақ, баяуырақ, қаттырақ, ақырынырақ, '
        'қысқа толықтық, қалыпты толықтық, толық толықтық, '
        'сирек ескертулер, қалыпты ескертулер, жиі ескертулер, '
        'sos үш рет түрту, sos сілку, күшті діріл, әлсіз діріл.',

    'obj_remember_listening': '{name} есте сақтап жатырмын. Жақынырақ ұстаңыз.',
    'obj_remember_saved': '{name} есте сақталды.',
    'obj_remember_failed': 'Затты көрмеймін. Қайталап көріңіз.',
    'obj_remember_capacity': 'Жад толды. Алдымен бірдеңе ұмытыңыз.',
    'obj_find_started': '{name} іздеп жатырмын.',
    'obj_find_position': '{name}, {dist} метр, {dir}.',
    'obj_find_position_no_dist': '{name}, {dir}.',
    'obj_find_lost': '{name} көрінбейді.',
    'obj_find_found': '{name} алдыңызда.',
    'obj_find_stopped': 'Іздеу тоқтатылды.',
    'obj_find_searching': '{name} іздеу жалғасуда...',
    'obj_forget_done': '{name} ұмытылды',
    'obj_forget_unknown': '{name} есімде жоқ.',
    'obj_unknown_target':
        'Мұндай зат есімде жоқ. {name} есте сақта деп айтыңыз.',
    'obj_busy_remembering': 'Қазір есте сақтап жатырмын, күтіңіз.',

    'fg_notification_title': 'Bagdar белсенді',
    'fg_notification_body': 'Навигация фонда жұмыс істеуде.',

    'battery_low':
        'Заряд төмен. Үнемдеу режимінде жұмыс істеймін. Әсіресе мұқият болыңыз.',
    'battery_low_depth_off':
        'Заряд төмен. Тереңдік анықтау үнемдеу режимінде жұмыс істейді. Әсіресе мұқият болыңыз.',
    'battery_low_critical':
        'Заряд өте төмен. Ең төменгі режимде жұмыс істеймін. Әсіресе мұқият болыңыз.',
    'battery_moderate': 'Заряд орташа — энергияны үнемдеймін.',
    'battery_normal': 'Заряд қалыпты.',
    'thermal_warning_warm':
        'Құрылғы қыза бастады. Сканерлеу жиілігі төмендетілді.',
    'thermal_warning_hot':
        'Жүйе қызып кетті. Сканерлеу жиілігі төмендетілді, баяуырақ жүріңіз.',
    'thermal_warning_critical':
        'Температура өте жоғары. Сканерлеу жиілігі қатты төмендетілді.',
    'thermal_ground_hazard_reduced':
        'Жоғары температура. Шұңқырлар мен баспалдақтарды анықтау уақытша төмендетілді.',
    'thermal_warm_move_to_shade':
        'Құрылғы қызып барады. Мүмкіндік болса, көлеңкеге өтіңіз. '
        'Жоғары температурада анықтау дәлдігі төмендейді.',
    'running_detected':
        'Сіз жүгіріп жатырсыз. Қауіпсіздік үшін баяуырақ жүріңіз.',
    'battery_50_remaining': 'Заряд 50%. Жұмыс уақыты шамамен екі сағат.',
    'battery_30_warning': 'Заряд 30%. Серуенді қысқартуды ұсынамыз.',
    'battery_15_critical':
        'Заряд 15%. Шұңқырларды анықтау төмендетілді. Таяқ пайдаланыңыз немесе көмек сұраңыз.',
    'low_light_warning':
        'Жарық аз. Анықтау дәлдігі төмендетілді. Аса абайлаңыз.',
    'pitch_black_ui': 'Қара экран',
    'pitch_black_ui_desc':
        'Камера көрінісін және навигация интерфейсін жасырады.',
    'pitch_black_on': 'Қара экран қосылды.',
    'pitch_black_off': 'Қара экран өшірілді.',
    'audio_route_interrupted': 'Дыбыс үзілді. Құлаққапты тексеріңіз.',
    'audio_resumed': 'Дыбыс қалпына келді.',
    'tts_fallback_en':
        'Voice pack for your language is missing. Using English fallback.',
    'fall_detector_degraded':
        'Құлауды анықтау дәлдігі төмендетілді. Гироскоп қолжетімсіз.',
    'test_alert_warning': 'Тест: назар аударыңыз, солда',
    'test_alert_critical': 'Тест: критикалық, алда',
    'lifecycle_background':
        'Қосымша жиналды. Сканерлеу жұмыс істемейді, экранға қайтарыңыз',
    'lifecycle_resumed': 'Қосымша қалпына келтірілді.',

    'night_mode_on': 'Түнгі режим қосылды.',
    'night_mode_off': 'Түнгі режим өшірілді.',

    'guide_dog_on': 'Жолбасшы ит режимі қосылды.',
    'guide_dog_off': 'Жолбасшы ит режимі өшірілді.',
    'hazard_low_curb': 'Алда төмен баспалдақ.',
    'hazard_near_field': 'Камераның астында нысан.',
    'weather_low_vis': 'Көріну нашар. Дәлдік төмендеді.',
    'weather_restored': 'Көріну қалпына келтірілді.',
    'indoor_mode_entered': 'Бөлме режимі.',
    'indoor_mode_exited': 'Көше режимі.',
    'camera_partial_blocked': 'Камера ішінара жабық. Линзаны тексеріңіз.',
    'group_ahead': 'Алда топ: ',
    'camera_reinit': 'Камера қайта қосылуда. Күтіңіз.',
    'camera_droplet': 'Линзада тамшы болуы мүмкін. Сүртіңіз.',
    'camera_smear': 'Линза ластанған. Сүртіңіз.',

    'waypoint_saved': 'Орын сақталды',
    'waypoint_near': 'Сіз жақынсыз',
    'waypoint_name_prompt': 'Орын атауы',
    'waypoint_none': 'Сақталған орындар жоқ.',
    'waypoint_deleted': 'Орын жойылды.',

    'sos_sent': 'SOS жіберілді.',
    'sos_queued': 'SOS кезекке қойылды, растауды күтемін.',
    'sos_sent_no_location':
        'SOS жіберілді, бірақ орналасуды анықтау мүмкін болмады.',
    'sos_indoor_warning':
        'Сіз ғимарат ішіндесіз. Координаттар дәл болмауы мүмкін.',
    'sos_launch_failed': 'SMS қолданбасын ашу мүмкін болмады.',
    'sos_error': 'SOS жіберу мүмкін болмады.',
    'sos_fall_detected':
        'Құлау анықталды. SOS 15 секундтан кейін жіберіледі. Болдырмау үшін экранды басыңыз.',
    'sos_fall_classb_detected':
        'Сіз жақсысыз ба? Болдырмау үшін экранды басыңыз. SOS 30 секундтан кейін жіберіледі.',
    'sos_fall_countdown': 'SOS',
    'sos_fall_seconds': 'секундтан кейін.',
    'sos_fall_cancelled': 'SOS жіберу болдырылмады.',
    'sos_fall_sent': 'Құлаудан кейін SOS жіберілді.',
    'sos_user_fallen_again': 'Назар аударыңыз: пайдаланушы қайта құлады.',
    'sos_fall_cancel_hint':
        '"Мен жақсымын" немесе "жалған дабыл" деп айтыңыз. Болдырмау үшін экранды басыңыз.',
    'sos_fall_voice_confirm_prompt': 'Растаңыз: "мен жақсымын" деп айтыңыз.',
    'sos_fall_voice_cancel_rejected':
        'Болдырмау расталмады. Кері санақ жалғасуда.',
    'sos_fall_are_you_ok': 'Жайсыз ба? Растау үшін басыңыз.',
    'sos_cancel_confirm': 'SOS-ты болдырмау үшін тағы бір рет түртіңіз.',
    'sos_112_fallback': 'Байланыс нөмірі жоқ. SOS 112 нөміріне жіберіледі.',
    'sos_position_stale': 'Орналасу ескі, жасы',
    'sos_position_unit_min': 'минут',
    'sos_sending': 'SOS жіберіп жатырмын...',
    'sos_retry': 'SOS қайта жіберу.',
    'sos_delivered': 'SOS жеткізілді.',
    'sos_composer_opened':
        'Хабар жазу терезесі ашылды, «Жіберу» түймесі — төменгі оң жақта.',
    'sos_dialer_opened':
        'Теру тақтасы ашылды, жасыл қоңырау шалу түймесін басыңыз.',
    'sos_planned_destination': 'Бара жатқан жер:',
    'sos_near_wifi': 'Wi-Fi жанында:',
    'sos_near_cell': 'Ұялы байланыс мұнарасы жанында:',
    'sos_steps_from_last': 'қадам',
    'sos_of_last_known': 'соңғы белгілі нүктеден',
    'sos_dir_n': 'солтүстікке',
    'sos_dir_ne': 'солтүстік-шығысқа',
    'sos_dir_e': 'шығысқа',
    'sos_dir_se': 'оңтүстік-шығысқа',
    'sos_dir_s': 'оңтүстікке',
    'sos_dir_sw': 'оңтүстік-батысқа',
    'sos_dir_w': 'батысқа',
    'sos_dir_nw': 'солтүстік-батысқа',
    'camera_blocked': 'Камера бұғатталған. Объективті тексеріңіз.',
    'camera_ae_transition': 'Камера жарыққа бейімделуде. Сақ болыңыз.',
    'camera_frozen':
        'Назар аударыңыз, камера кескіні тұрып қалды. Қосымшаны қайта іске қосыңыз.',
    'camera_stalled': 'Камера тоқтады. Тоқтаңыз, қолданбаны тексеріңіз.',
    'camera_resumed': 'Камера қайта жұмыс істеп тұр.',
    'shake_warning':
        'Камера қатты дірілдейді. Бәсеңдеңіз немесе телефонды тегіс ұстаңыз.',
    'nav_maybe_off_route': 'Маршруттан ауытқып жатқан шығарсыз.',
    'pitch_too_high': 'Жерді сканерлеу үшін телефонды төмен еңкейтіңіз.',
    'pitch_too_low': 'Телефонды сәл жоғары көтеріңіз.',
    'pitch_misaligned_blind': 'Телефонды көтеріңіз — мен жолды көрмеймін.',
    'misalign_no_detections':
        'Ұзақ уақыт нысандар танылмай жатыр. Телефонды тіктеп ұстаңыз.',
    'phone_abandoned': 'Bagdar жатыр — телефонды тексеріңіз.',
    'winter_visibility_heartbeat': 'Көріну нашар — абайлаңыз.',
    'curtain_on': 'Экран пердесі қосулы. Экран жасырын.',
    'curtain_off': 'Экран пердесі өшірулі.',
    'help_summary':
        'Басқару бойынша анықтама. '
        'Бір рет түрту — жылдам күй. '
        'Екі рет түрту — баптаулар. '
        'Бір саусақпен ұзақ басу — дауыстық команда. '
        'Оңға не солға сырғыту — режимді ауыстыру. '
        'Жоғары сырғыту — осы анықтама. '
        'Төмен сырғыту — экран пердесі. '
        'Екі саусақпен екі секунд басу — SOS. '
        'Немесе SOS үшін сос деп, осы хабарлама үшін көмек деп айтыңыз.',
    'help_summary_classic':
        'Басқару бойынша анықтама. '
        'Бір рет түрту — жылдам күй. '
        'Екі рет түрту — баптаулар. '
        'Бір саусақпен ұзақ басу — дауыстық команда. '
        'Оңға не солға сырғыту — режимді ауыстыру. '
        'Жоғары сырғыту — экран пердесі. '
        'Төмен сырғыту — осы анықтама. '
        'Екі саусақпен екі секунд басу — SOS. '
        'Немесе SOS үшін сос деп, осы хабарлама үшін көмек деп айтыңыз.',
    'status_quick': 'Режим {mode}. Заряд {battery} пайыз.',
    'status_quick_mode_only': 'Режим {mode}.',
    'gesture_weak': 'Сырғыту әлсіз. Саусағыңызды жылдамырақ қозғалтыңыз.',
    'camera_screen_semantics':
        'Bagdar камера экраны. '
        'Бір тию — режим және заряд. '
        'Қос тию — баптаулар. '
        'Саусақты ұстау — дауыстық команда. '
        'Оңға немесе солға сырғыту — режимді ауыстыру. '
        'Жоғары сырғыту — анықтама. Төмен сырғыту — экран пердесі. '
        'Екі саусақпен бір жарым секунд — шұғыл SOS.',
    'camera_screen_semantics_classic':
        'Bagdar камера экраны. '
        'Бір тию — режим және заряд. '
        'Қос тию — баптаулар. '
        'Саусақты ұстау — дауыстық команда. '
        'Оңға немесе солға сырғыту — режимді ауыстыру. '
        'Жоғары сырғыту — экран пердесі. Төмен сырғыту — анықтама. '
        'Екі саусақпен бір жарым секунд — шұғыл SOS.',
    'tl_green_warning':
        'Көлік дыбыстарына құлақ салып, қауіпсіздікке көз жеткізіңіз.',
    'tl_green_wait':
        'Бағдаршам жасыл. Көліктің тоқтағанын растамайынша қозғалмаңыз.',
    'tl_green_cars_near': 'Бағдаршам жасыл, жақын маңда көлік бар. Күтіңіз.',
    'tl_vehicle': 'Көлік бағдаршамы. Оған қарамаңыз, өту дыбысын тыңдаңыз.',
    'sos_no_contact': 'SOS контактісі белгіленбеген. Баптауларда орнатыңыз.',
    'sos_no_location': 'Орналасуды анықтау мүмкін болмады.',
    'sos_no_gps': 'орналасу қолжетімсіз',
    'sos_settings': 'SOS контактісі',
    'sos_message': 'Маған көмек керек! Менің орналасуым:',
    'sos_invalid_number': 'Телефон нөмірі қате.',

    'depth_unavailable': 'Тереңдікті анықтау қолжетімсіз.',
    'depth_unavailable_street':
        'Назар аударыңыз: еден деңгейіндегі кедергілерге қауіпсіздік өшірілген.',
    'depth_session_disabled':
        'Қателерге байланысты тереңдікті анықтау өшірілді. Қайта іске қосылғанша саты мен бордюр хабарланбайды. Абай болыңыз.',
    'hazard_detection_resumed': 'Кедергілерді анықтау қайта қосылды.',
    'depth_paused_explicit': 'Саты мен бордюрді анықтау уақытша тоқтатылды.',
    'weather_depth_off_walking':
        'Көріну нашар. Саты мен бордюр анықталмауы мүмкін. Ақырын жүріңіз.',
    'depth_degraded':
        'Тереңдік сапасы төмендеді. Кедергілерге көбірек назар аударыңыз.',
    'depth_recovered': 'Тереңдік сапасы қалпына келді.',
    'depth_quality_low': 'Тереңдік сапасы төмен. MiDaS-ке ауысып жатырмын.',
    'reduced_mode_depth':
        'Шектелген режим: тереңдікті анықтау уақытша өшірілді.',
    'reduced_mode_restored': 'Тереңдікті анықтау қалпына келтірілді.',

    'camera_perm_title': 'Камераға рұқсат жоқ',
    'camera_perm_body':
        'Bagdar жұмысы үшін камера қажет.\n'
        'Баптауларды ашып, камераға рұқсат беріңіз.',
    'camera_perm_blind_intro':
        'Камера жүйеде тыйылған. '
        'Қос тию — телефон баптауларын ашу. '
        'Бір тию — болдырмау.',
    'camera_perm_denied_retry':
        'Камераға рұқсат берілмеді. Бұл рұқсатсыз Bagdar кедергіні көрмейді. '
        'Қос тию — қайталау.',
    'calib_no_person': 'Кадрда адам жоқ. Камераны бағыттап, қайта көріңіз.',
    'calib_invalid_dist': 'Дұрыс қашықтықты енгізіңіз (0–50 м)',

    'nav_destination': 'мақсат нүктесі',
    'nav_route_built': 'Маршрут құрылды',
    'nav_approx': 'Шамамен',
    'nav_minutes': 'минут',
    'nav_arrived': 'Сіз жеттіңіз',
    'nav_arrived_short': 'Жеттіңіз.',
    'hud_riding': 'Жолдамыз',
    'hud_uturn': 'Айналу',
    'nav_arriving': 'Жету.',
    'nav_not_active': 'Навигация белсенді емес.',
    'nav_remaining': 'Қалды',
    'nav_no_gps': 'GPS қолжетімсіз.',
    'nav_your_position': 'Сіздің орныңыз:',
    'nav_go_straight': 'Тура жүріңіз',
    'nav_turn_left': 'Солға бұрылыңыз',
    'nav_turn_right': 'Оңға бұрылыңыз',
    'nav_u_turn': 'Кері бұрылыңыз',
    'nav_turn_around': 'Кері бұрылыңыз',
    'nav_arrive': 'Жету',
    'nav_searching': 'Орын іздеп жатырмын...',
    'nav_not_found': 'Орын табылмады.',
    'nav_building_route': 'Маршрут құрып жатырмын...',
    'nav_route_failed': 'Маршрут құру мүмкін болмады.',
    'nav_stopped': 'Навигация тоқтатылды.',
    'nav_no_api_key': '2GIS кілті белгіленбеген. Баптауларда орнатыңыз.',
    'nav_off_route': 'Сіз маршруттан ауытқыдыңыз.',
    'nav_rerouting_try': 'Маршрутты қайта құрып жатырмын.',
    'nav_reroute_failed':
        'Маршрутты қайта құру мүмкін болмады. Қауіпсіз жерде тоқтап, мен қайдамын деп сұраңыз.',
    'nav_reroute_ok': 'Жаңа маршрут дайын.',
    'nav_bearing_return':
        'Маршрут артта, телефонды бұрыңыз да мен қайдамын деп сұраңыз.',

    'nav_transit_route_built': 'Көлікпен маршрут құрылды',
    'nav_walk': 'Жаяу',
    'nav_take_bus': 'Автобусқа отырыңыз нөмірі',
    'nav_from_stop': 'аялдамадан',
    'nav_ride_stops': 'Аялдама саны:',
    'nav_wait_bus': 'Автобус күтіңіз нөмірі',
    'nav_at_stop': 'Сіз аялдамадасыз',
    'nav_exit_now': 'Қазір түсіңіз! Аялдама',
    'nav_stops_remaining': 'Қалған аялдамалар:',
    'nav_boarding_confirmed': 'Сіз отырдыңыз. Аялдамаларды бақылаймын.',
    'nav_walking_to_stop': 'Аялдамаға бара жатырмыз.',
    'nav_waiting': 'Көлік күтіп тұрмыз.',
    'nav_waiting_for': 'Автобус күтіп тұрмыз',
    'nav_riding': 'Жүріп барамыз',
    'nav_walk_to_dest': 'Мақсат нүктесіне бара жатырмыз.',
    'nav_nearest_stop': 'Жақын аялдама',
    'nav_gps_wait': 'GPS сигналын күтемін...',
    'nav_gps_unreliable': 'GPS сенімсіз. Навигация тоқтатылды.',
    'nav_gps_restored': 'GPS қалпына келді.',
    'nav_rerouting': 'Маршрут қайта құрылуда...',
    'nav_auto_boarded': 'Қозғалыс анықталды. Аялдамаларды бақылаймын.',
    'nav_bus_interval': 'Келесі автобус шамамен',
    'nav_bus_minutes': 'минуттан кейін.',
    'nav_bus_not_running': 'Автобус қазір жұмыс істемейді.',

    'tl_red': 'Бағдаршам қызыл. Күтіңіз.',
    'tl_yellow': 'Бағдаршам сары. Күтіңіз.',
    'tl_green': 'Бағдаршам жасыл.',
    'tl_green_safe':
        'Бағдаршам жасыл болуы мүмкін. Көлік дыбыстарына құлақ салыңыз.',
    'tl_green_cars': 'Бағдаршам жасыл, бірақ көлік жақын. Күтіңіз.',
    'tl_unknown': 'Бағдаршам түсін анықтай алмадым. Сақ болыңыз.',
    'tl_uncertain':
        'Бағдаршам нашар көрінеді немесе сенімді емеспін. Сақ болыңыз.',
    'tl_ahead': 'Алда бағдаршам.',

    'nav_api_key_label': '2GIS API кілті',
    'nav_api_key_hint': 'API кілтін енгізіңіз',
    'nav_api_key_saved': 'Кілт сақталды.',

    'nav_offline_ready': 'Офлайн карта жүктелді.',
    'nav_offline_not_ready': 'Офлайн карта жүктелмеген. Онлайн қолданылады.',
    'nav_download_map': 'Картаны жүктеу',
    'nav_downloading_map': 'Картаны жүктеп жатырмын...',
    'nav_download_complete': 'Карта жүктелді.',
    'nav_download_failed': 'Картаны жүктеу мүмкін болмады.',
    'nav_download_progress': 'Жүктеу',
    'nav_delete_map': 'Картаны жою',
    'nav_map_deleted': 'Карта жойылды.',
    'nav_select_city': 'Қаланы таңдаңыз',
    'nav_city_astana': 'Астана',
    'nav_city_almaty': 'Алматы',
    'nav_no_map': 'Офлайн навигация үшін қала картасын жүктеңіз.',
    'nav_map_update': 'Карта жаңартуы қолжетімді.',
    'nav_map_stale': 'Офлайн карта ескіруі мүмкін. Жаңартуды тексеріңіз.',
    'nav_map_updated': 'Карта жаңартылды.',
    'nav_disk_space': 'Дискіде орын жеткіліксіз.',
    'nav_surface_gravel': 'Тас жол.',
    'nav_surface_unpaved': 'Жабынсыз жол.',
    'nav_tactile_yes': 'Тактильді плитка.',
    'nav_steps_ahead': 'Алда баспалдақ.',
    'nav_no_sidewalk': 'Тротуар жоқ.',

    'gtfs_route_info': 'Маршрут',
    'gtfs_schedule': 'Кесте',
    'gtfs_working_hours': 'Жұмыс уақыты',
    'gtfs_interval': 'Аралық',
    'gtfs_minutes': 'минут',
    'gtfs_stops_count': 'Аялдамалар',
    'gtfs_from': 'Бастап',
    'gtfs_to': 'Дейін',
    'gtfs_not_found': 'Маршрут табылмады.',
    'gtfs_stale': 'Кесте ескіруі мүмкін. Жаңартуды тексеріңіз.',
    'gtfs_bus_routes': 'Аялдамадағы автобус маршруттары',

    'tts_lang_title': 'Дауыстық пакет табылмады',
    'tts_lang_body':
        'Таңдалған тіл үшін дауыстық пакет орнатылмаған. '
        'Баптаулар → Арнайы мүмкіндіктер → '
        'Сөйлеу синтезі бөліміне өтіп, тілдің дауысын орнатыңыз.',
    'tts_lang_open': 'Түсінікті',

    'sem_step_of': '{count} қадамнан {step}',
    'sem_required': 'Міндетті',
    'sem_optional_perm': 'Міндетті емес',
    'sem_done': 'Орындалды',
    'sem_not_done': 'Орындалмады',
    'sem_on': 'қосулы',
    'sem_off': 'өшірулі',

    'tts_kk_guide_title': 'Қазақ дауысын орнатыңыз',
    'tts_kk_guide_body':
        'Сапалы қазақ тілінде сөйлеу үшін дауыстық пакетті орнатыңыз. '
        'Баптаулар → Арнайы мүмкіндіктер → '
        'Сөйлеу синтезі → Дауыстық деректер → Қазақ тілі.',
    'tts_kk_open_settings': 'TTS баптауларын ашу',
    'tts_kk_not_available':
        'Қазақ дауысы табылмады. Дауыстық көмекші орыс акцентімен жұмыс істейді.',

    'lang_switched': 'Тіл өзгертілді.',

    'pref_clear_path_announce': '«Жол бос» хабарламасы',
    'pref_battery_announce': 'Заряд деңгейі хабарламасы',
    'pref_mode_announce': 'Режим ауыстыру хабарламасы',

    'vc_speed_up': 'Сөйлеу жылдамдатылды.',
    'vc_speed_down': 'Сөйлеу баяулатылды.',
    'vc_volume_up': 'Дауыс көтерілді.',
    'vc_volume_down': 'Дауыс азайтылды.',
    'vc_battery_status': 'Заряд {battery} пайыз.',

    'audio_tour':
        'Сіз негізгі экрандасыз. '
        'Камера жұмыс істеуде, айналаны сканерлеп тұр. '
        'Режимді ауыстыру үшін солға не оңға сырғытыңыз. '
        'Дауыстық команда үшін саусақты ұстап тұрыңыз. '
        'Анықтама үшін жоғары сырғытыңыз.',
    'audio_tour_done': 'Сәтті пайдаланыңыз!',

    'onb_sos_title': 'Шұғыл байланыс',
    'onb_sos_sub':
        'Жақын адамыңыздың нөмірін енгізіңіз.\\nBagdar шұғыл жағдайда орныңызды SMS арқылы жібереді.',
    'onb_sos_tts':
        'Шұғыл жағдай үшін нөмір енгізіңіз. '
        'Bagdar сіздің орныңызды SMS-пен жібереді. '
        'Өткізіп жіберіп, кейін баптауға болады.',
    'onb_sos_placeholder': '+7 (___) ___-__-__',
    'onb_sos_save': 'Контактіні сақтау',
    'onb_sos_skip': 'Кейін баптаймын',

    'settings_calibration': 'Камераны калибрлеу',
    'settings_calibration_desc': 'Адамнан дәл 2 м қашықтықта тұрып басыңыз',
    'settings_read_text': 'Мәтінді оқу',
    'settings_read_text_desc': 'OCR — кадрдағы мәтінді тану',
    'settings_cpu_threads': 'CPU ағындары',
    'settings_lang_label': 'Тіл / Язык',
    'settings_earcon_title': 'Дыбыстық сигналдар',
    'settings_earcon_desc': 'Оқиғалар үшін тез дыбыстар',
    'settings_depth_active': 'Тереңдік талдауы: белсенді',
    'settings_depth_not_ready': 'Тереңдік талдауы: дайын емес',
    'settings_scan_left': 'Солда не бар?',
    'settings_scan_forward': 'Алда не бар?',
    'settings_scan_right': 'Оңда не бар?',
    'settings_haptic_test': 'Діріл тесті (Таяқ режимі)',
    'settings_earcon_test': 'Дыбыстық сигналдар тесті',
    'settings_sos_not_set': 'Белгіленбеген',

    'path_clear_minimal': 'Талдау белсенді.',
    'hazard_stairs_down_minimal': 'Баспалдақ. Тоқта.',
    'hazard_overhead_minimal': 'Кедергі. Тоқта.',
    'camera_blocked_minimal': 'Камера жабық.',

    'scene_see_count': '{count} нысан көрінеді.',
    'scene_see_one': 'Бір нысан көрінеді.',
    'scene_see_none': 'Ештеңе танылмады.',
    'scene_object_entry': '{label} {direction}',
    'scene_object_dist': ', шамамен {dist}',
    'scene_object_approaching': ', жақындап келеді',
    'scene_hazard_intro': 'Жерде:',
    'scene_traffic_light': 'Бағдаршам {color}.',
    'scene_color_red': 'қызыл',
    'scene_color_yellow': 'сары',
    'scene_color_green': 'жасыл',
    'scene_ocr_read': 'Жазу: {text}.',
    'scene_left_only': 'Солда:',
    'scene_right_only': 'Оңда:',
    'scene_ahead_only': 'Алда:',
    'scene_narrating': 'Сипаттап жатырмын...',
    'scene_cooldown': 'Қайта сипаттау алдында күтіңіз.',

    'sms_payment_received': 'Түсті',
    'sms_payment_sent': 'Шығыс',
    'sms_payment_from': 'жіберуші',
    'sms_balance': 'Қалдық',
    'sms_currency_kzt': 'теңге',
    'sms_currency_rub': 'рубль',
    'sms_currency_usd': 'доллар',
    'sms_currency_eur': 'еуро',
    'sms_notifications_enabled': 'Төлем хабарламалары қосылды.',
    'sms_notifications_disabled': 'Төлем хабарламалары өшірілді.',
    'sms_permission_denied':
        'Кіріс СМС оқу рұқсаты жоқ. Баптауларды ашып рұқсат беріңіз.',
    'acoustic_vehicle_left': 'Сол жақтан көлік.',
    'acoustic_vehicle_right': 'Оң жақтан көлік.',
    'acoustic_vehicle_behind': 'Көлік дыбысы.',
    'acoustic_horn': 'Сигнал!',
    'acoustic_siren': 'Жақында сирена.',
    'acoustic_dog': 'Жақында ит.',
    'acoustic_dog_left': 'Сол жақта ит.',
    'acoustic_dog_right': 'Оң жақта ит.',
    'acoustic_crowd_dense': 'Адам көп жер.',
    'acoustic_construction': 'Жақында құрылыс.',
    'awm_enabled': 'Акустика қосылды.',
    'awm_disabled': 'Акустика өшірілді.',

    'shelf_camera_short': 'Камера',
    'shelf_read_short': 'Оқу',
    'shelf_navigate_short': 'Қайда',
    'shelf_camera_label': 'Камера. Белсенді.',
    'shelf_camera_hint': 'Қос түрту — қалыпты режимге қайту.',
    'shelf_read_label': 'Камера көріп тұрғанды дауыстап оқу.',
    'shelf_read_hint': 'Қос түрту — оқуды бастау.',
    'shelf_navigate_label': 'Дауыспен бағыт салу.',
    'shelf_navigate_hint': 'Қос түрту — бару орнын таңдау.',
    'shelf_read_started': 'Көрген нәрсемді оқимын. Телефонды тігінен ұстаңыз.',
    'shelf_navigate_started': 'Қайда барамыз? Орынның атын айтыңыз.',
    'shelf_cane_confirm': 'Режимді ауыстыру үшін секунд ұстаңыз.',
    'ocr_aim_hint': 'Мәтінді жақынырақ ұстап, камераны тігінен ұстаңыз.',
    'ocr_timeout': 'Сегіз секундта мәтін табылмады. Қайталап көріңіз.',
    'ocr_lines_count': '{n} жол табылды. Оқимын.',
    'processing_heartbeat': 'Талдап жатырмын... күтіңіз.',
    'pitch_black_heartbeat': '',
    'offline_banner_no_gps': 'GPS сигналы жоқ. Орналасу шамамен.',
    'offline_banner_no_map':
        'Аймақ картасы жүктелмеген. "Картаны жүкте" деп айтыңыз.',
    'settings_save_failed': 'Параметр сақталмады. Қайталап көріңіз.',
    'theme_selected_dark': 'Қара тақырып, қара экран мен сары акцент.',
    'theme_selected_light': 'Ашық тақырып, ақ экран мен қара-көк акцент.',
    'theme_selected_high_contrast': 'Жоғары контраст, тек қара үстіндегі ақ.',
    'theme_selected_warm':
        'Жылы тақырып, кілегейлі экран мен қара-қоңыр мәтін.',
    'voice_layer_listening': 'Команданы тыңдап тұрмын.',
    'voice_layer_cancel': 'Тыңдауды тоқтату.',
    'restart_pipeline': 'Тануды қайта қосу.',
    'restart_pipeline_done': 'Тану қайта қосылды.',
    'lang_pack_required_for_kk':
        'Қазақ тілін жақсырақ тану үшін тіл пакетін жүктеп алыңыз.',
    'lang_pack_downloading': 'Қазақ тіл пакетін жүктеп жатырмын.',
    'lang_pack_install_complete': 'Қазақ тіл пакеті орнатылды.',
    'lang_pack_install_failed': 'Қазақ пакетін орнату мүмкін болмады.',
    'lang_pack_offline_skip': 'Желі жоқ. Келесі жалғану кезінде сұраймын.',
    'vosk_kk_loading': 'Қазақша тануды дайындап жатырмын.',
    'vosk_kk_load_failed':
        'Қазақша тануды жүктеу мүмкін болмады. Қосымша нұсқаны қолданамын.',
    'lang_packs_screen_title': 'Тіл пакеттері',
    'lang_packs_screen_intro': 'Қазақ тіліне арналған тіл пакеттерін басқару.',
    'lang_packs_v2_toggle_label': 'Жетілдірілген қазақша тану',
    'lang_packs_v2_toggle_desc':
        'Қазақша сөйлеуді тану үшін Vosk қолдану. Тіл пакеті қажет.',
    'lang_packs_v2_enabled': 'Жетілдірілген тану қосылды.',
    'lang_packs_v2_disabled': 'Жетілдірілген тану өшірілді.',
    'lang_packs_refresh': 'Тізімді жаңарту',
    'lang_packs_refresh_done': 'Пакеттер тізімі жаңартылды.',
    'lang_packs_refresh_failed':
        'Тізімді жаңарту мүмкін болмады. Желіні тексеріңіз.',
    'lang_packs_install': 'Орнату',
    'lang_packs_delete': 'Жою',
    'lang_packs_update': 'Жаңарту',
    'lang_packs_installed': 'Орнатылған',
    'lang_packs_not_installed': 'Орнатылмаған',
    'lang_packs_size_mb': '{size} МБ',
    'lang_packs_no_packs':
        'Тіл пакеттері табылмады. «Жаңарту» түймесін басыңыз.',
    'lang_packs_close': 'Жабу',
    'lang_packs_delete_confirm': '{name} пакетін жою керек пе?',
    'voice_kk_v2_pack_missing':
        'Пакет орнатылмаған. Орнату үшін тіл пакеттерін ашыңыз.',
    'voice_manage_lang_packs_announce': 'Тіл пакеттерін ашамын.',
    'onb_kk_pack_prompt_title': 'Қазақша тану',
    'onb_kk_pack_prompt_body':
        'Қазақша тану пакетін қазір жүктеп алу керек пе? Шамамен 50 МБ.',
    'onb_kk_pack_yes': 'Жүктеп алу',
    'onb_kk_pack_skip': 'Өткізіп жіберу',
    'onb_kk_pack_later': 'Желі болғанда еске салу',
    'lang_pack_online_ready':
        'Желі қалпына келді. Қазақша тану пакетін орнатуға дайын. «Тіл пакеттері» деп айтыңыз.',

    'tts_kk_engine_system': 'Жүйелік қазақша дауыс',
    'tts_kk_engine_rhvoice': 'RHVoice (Айгүл)',
    'tts_kk_engine_espeak': 'espeak-ng (қосалқы)',
    'tts_kk_engine_fallback_ru': 'Қазақ мәтінін орысша оқу',
    'tts_kk_using_rhvoice': 'Қазақша үшін RHVoice қолданамын.',
    'tts_kk_using_espeak':
        'Базалық қазақша дауысты қолданамын. Дыбыстау қарапайым болуы мүмкін.',
    'tts_kk_using_system': 'Жүйелік қазақша дауысты қолданамын.',
    'tts_kk_using_russian_fallback':
        'Қазақша дауыс жоқ. Қазақ мәтінін орысша оқимын.',
    'tts_kk_engine_load_failed':
        'Қазақша дауысты жүктеу мүмкін болмады. Қосалқы нұсқаға көшемін.',
    'onb_rhvoice_pack_prompt_title': 'Жақсы қазақша дауыс',
    'onb_rhvoice_pack_prompt_body':
        'Жоғары сапалы қазақша дауысты қазір жүктеп алу керек пе? Шамамен 30 МБ. Дауыс интернетсіз жұмыс істейді.',
    'onb_rhvoice_pack_yes': 'Жүктеп алу',
    'onb_rhvoice_pack_skip': 'Өткізіп жіберу',
    'onb_rhvoice_pack_later': 'Желі болғанда еске салу',
    'lang_pack_rhvoice_online_ready':
        'Желі қалпына келді. Қазақша дауыс пакетін орнатуға дайын. «Тіл пакеттері» деп айтыңыз.',

    'trail_recording_started':
        'Маршрут жазуы басталды. Мақсатқа қарай жүріңіз.',
    'trail_recording_stopped': 'Маршрут сақталды.',
    'trail_recording_failed': 'Маршрут жазуын бастау мүмкін болмады.',
    'trail_recording_empty': 'Маршрут бос, сақталмады.',
    'trail_recording_cancelled': 'Маршрут жазуы тоқтатылды.',
    'trail_landmark_added': 'Белгі қойылды.',
    'trail_replay_started': 'Маршрутпен жүремін.',
    'trail_replay_stopped': 'Маршрут қайталау тоқтатылды.',
    'trail_not_found': 'Маршрут табылмады.',
    'trail_deleted': 'Маршрут жойылды.',
    'trail_arrived': 'Жеттіңіз.',
    'trail_lost': 'Маршрут жоғалды. Кері қайтыңыз.',
    'trail_continue_straight': 'Тура жүріңіз, {n} қадам қалды.',
    'trail_turn_left': 'Солға бұрылыңыз.',
    'trail_turn_right': 'Оңға бұрылыңыз.',
    'trail_slight_left': 'Сәл солға.',
    'trail_slight_right': 'Сәл оңға.',

    'bazaar_mode_on': 'Базар режимі қосылды.',
    'bazaar_mode_off': 'Базар режимі өшірілді.',
    'livestock_mode_on': 'Мал режимі қосылды.',
    'livestock_mode_off': 'Мал режимі өшірілді.',
    'livestock_cow': 'Сиыр',
    'livestock_horse': 'Жылқы',
    'livestock_sheep': 'Қой',
    'livestock_dog': 'Ит',
    'livestock_cat': 'Мысық',
    'livestock_bird': 'Құс',

    'voice_adapt_on': 'Дауыс бейімдеу қосылды. Деректер құрылғыда қалады.',
    'voice_adapt_off': 'Дауыс бейімдеу өшірілді.',
    'voice_adapt_samples_cleared': 'Бейімдеу деректері жойылды.',

    'mesh_hazard_generic':
        'Басқа пайдаланушы жақын маңда кедергі туралы хабарлады.',
    'mesh_hazard_pothole':
        'Басқа пайдаланушы жақын маңда шұңқыр туралы хабарлады.',
    'mesh_hazard_construction':
        'Басқа пайдаланушы жақын маңда құрылыс туралы хабарлады.',
    'mesh_hazard_ice': 'Басқа пайдаланушы жақын маңда мұз туралы хабарлады.',
    'mesh_hazard_stairs':
        'Басқа пайдаланушы жақын маңда баспалдақ туралы хабарлады.',
    'mesh_buddy_started': 'Көмекшілер желісі қосылды.',
    'mesh_buddy_stopped': 'Көмекшілер желісі өшірілді.',
    'mesh_buddy_no_ble':
        'Bluetooth қолдау көрсетілмейді. Көмекшілер желісі қол жетімсіз.',

    'oscp_near_field': 'Таяқ: алда кедергі',
    'oscp_connected': 'Таяқ қосылды.',
    'oscp_disconnected': 'Таяқ ажыратылды.',
    'oscp_battery_low': 'Таяқтың заряды төмен.',
    'oscp_no_ble': 'Bluetooth қолдау көрсетілмейді. Таяқ қол жетімсіз.',

    'near_miss_recorded': 'Қауіпті жағдай жазылды.',
    'near_miss_cleared': 'Қауіпті жағдай жазбалары жойылды.',

    'vlm_loading': 'Сахна сипаттау моделін жүктеп жатырмын.',
    'vlm_ready': 'Сахна сипаттау моделі дайын.',
    'vlm_not_available':
        'Сахна сипаттау қол жетімсіз. Зарядтау және бос жад қажет.',
    'vlm_thinking': 'Ойланып жатырмын...',
    'vlm_answer_fallback':
        'Модель жауап бермеді. Стандартты сипаттама қолданылуда.',

    'sonar_near_field': 'Эхолот: алда нысан',
    'sonar_started': 'Эхолот қосылды.',
    'sonar_stopped': 'Эхолот өшірілді.',
    'sonar_calibrating': 'Эхолотты калибрлеу.',
    'sonar_no_48k': 'Микрофон эхолотты қолдамайды.',
    'onb_mic_prime_tts':
        'Дауыспен басқару үшін маған микрофонға рұқсат қажет. Қазір жүйелік сұрау терезесі пайда болады.',
    'onb_mic_denied_fallback_tts':
        'Микрофонға рұқсат берілмеді. Дауыспен басқару өшірілген. Параметрлерді реттеу үшін қимылдарды пайдаланыңыз.',
    'onb_mode_confirm_prompt':
        'Режим таңдалды. Жалғастыру үшін иә деп айтыңыз немесе басқа режимді атаңыз.',
    'sos_setup_prompt_tts':
        'Шұғыл SOS көмегі үшін жақын адамыңыздың телефон нөмірін көрсетіңіз.',
    'camera_perm_recovery_tts':
        'Камераға рұқсат блокталған. Телефон баптауларында рұқсат беріңіз. Баптаулар үшін қос түртіңіз, қайталау үшін бір рет түртіңіз.',
    'onb_help_prompt_lang':
        'Тілді таңдаңыз. Орыс, Қазақ немесе Ағылшын деп айтыңыз.',
    'onb_help_prompt_hand':
        'Ведущий қолды таңдаңыз. Оң немесе Сол деп айтыңыз.',
    'onb_help_prompt_mode':
        'Әдепкі режимді таңдаңыз. Көше, Таяқ немесе Сканерлеу деп айтыңыз.',
    'onb_help_prompt_perm': 'Камераға рұқсат беріңіз. Рұқсат деп айтыңыз.',
    'onb_help_prompt_calib':
        'Қашықтықты калибрлеу. Жалғастыру үшін Иә деп айтыңыз.',
    'onb_help_prompt_ready': 'Бәрі дайын. Бастау үшін Иә деп айтыңыз.',
    'onb_emergency_skip_confirm':
        'Барлық қолданба реттеулерін өткізіп жіберу керек пе? Қос түртіңіз растайды. Бір түрту болдырмайды.',
    'yolo_unavailable': 'Нысан тануы қолжетімсіз. Қауіп анықтау өшірілді.',
    'yolo_detector_not_responding': 'Нысан детекторы жауап бермейді.',
  },
  AppLanguage.en: {
    'stop': 'Stop',
    'close': 'close',
    'approaching': 'approaching',
    'transport_approaching': 'Transport approaching',
    'object_approaching': 'Object approaching',
    'synth_event_stop_left': 'Stop! From the left',
    'synth_event_stop_right': 'Stop! From the right',
    'synth_event_stop_center': 'Stop! Straight ahead',
    'sign': 'Sign',
    'path_clear': 'Analysis active.',
    'path_clear_cane': 'Analysis active.',
    'path_clear_label': 'Analysis active',
    'no_change': 'No changes.',
    'nothing_seen': 'I see nothing.',
    'nothing_here': 'Nothing here',
    'left': 'left',
    'right': 'right',
    'forward_loc': 'forward',
    'closest': 'Closest object at',
    'meters': 'meters',
    'approx_meters': 'm',
    'now_imminent': 'now',
    'hazard_dead_zone': 'Hazard near your feet',
    'hazard_step_down': 'Step down',
    'hazard_step_up': 'Step up',
    'hazard_pothole': 'Pothole',
    'hazard_curb': 'Curb',
    'hazard_stairs_down': 'Stairs down. Stop.',
    'hazard_overhead': 'Obstacle at chest height. Stop.',
    'hazard_unknown': 'Obstacle',
    'hazard_glass_door': 'Possible glass door ahead. Be careful.',
    'hazard_slippery': 'Careful, might be slippery.',
    'hazard_warning': 'Possible obstacle —',
    'phone_tilted_sideways': 'Phone tilted.',

    'deviate': 'Deviate',
    'passage': 'Passage',
    'maneuver_ok': 'Good.',
    'nav_left': 'left',
    'nav_right': 'right',
    'nav_slight_left': 'slight left',
    'nav_slight_right': 'slight right',
    'straight': 'straight',

    'corridor_blocked': 'Passage blocked.',
    'narrow': 'Narrow.',

    'status_no_obstacle': 'Analysis active',
    'status_analysis_active': 'Analysis active',
    'spatial_analysis_limited': 'Spatial analysis is limited. Use your cane.',
    'spatial_stop_sensing_unavailable':
        'Stop. Spatial sensing is unavailable.',
    'core_health_sound_unavailable':
        'Sound unavailable. Vibration warnings remain active.',
    'core_health_haptic_unavailable':
        'Vibration unavailable. Spoken warnings remain active.',
    'core_health_recovered': 'System recovered.',
    'core_health_status': 'System status',
    'generic_obstacle_ahead': 'Obstacle ahead.',
    'generic_obstacle_stop': 'Stop. Obstacle ahead.',
    'generic_obstacle_left': 'Obstacle on the left.',
    'generic_obstacle_right': 'Obstacle on the right.',
    'generic_obstacle_overhead': 'Stop. Obstacle at head height.',
    'generic_vehicle_ahead': 'Car ahead.',
    'generic_vehicle_left': 'Car on the left.',
    'generic_vehicle_right': 'Car on the right.',
    'status_scanning': 'Scanning...',
    'status_waiting': 'waiting',
    'dist_safe': 'safe',
    'dist_attention': 'attention',
    'dist_stop': 'stop',
    'lbl_object': 'Object',
    'lbl_status': 'Status',
    'lbl_total_objects': 'Total objects',

    'scan_left': 'Left',
    'scan_forward': 'Forward',
    'scan_right': 'Right',
    'scan_see': 'I see',

    'ocr_reading': 'Reading...',
    'ocr_not_found': 'No text found.',
    'ocr_camera_not_ready': 'Camera not ready.',

    'ocr_low_memory':
        'Not enough memory to recognize text. Close other apps and try again.',
    'ocr_paddle_init_failed':
        'Could not start the enhanced recognizer. Falling back to the default.',

    'camera_unavailable': 'Camera unavailable.',
    'camera_not_found': 'Camera not found',
    'camera_started': 'Camera started',
    'system_ready': 'System ready',
    'core_feature_unavailable': 'This feature is not available in this build.',
    'init_failed':
        'System start failed. Stop where you are. Please restart the app.',
    'camera_init_failed_critical':
        'Camera error. Recognition unavailable. Please restart the app.',
    'mode_changed': 'Mode',

    'calib_aim': 'Point the camera at a person for calibration.',
    'calib_saved': 'Calibration saved.',
    'calib_recommend':
        'For accurate distance detection, we recommend calibration in Settings.',

    'onb_welcome_tts':
        'Welcome to Bagdar. Choose your mode. '
        'Swipe up or down to change mode, double tap to select.',
    'onb_welcome_intro_tts':
        'Hello. Bagdar is a voice assistant for the blind, helping to orient in space and avoid obstacles. Let\'s begin the setup. Choose language. Swipe up or down to change. Double tap to select. Or say out loud: Russian, Kazakh, or English.',
    'onb_dominant_hand_tts':
        'Step one. Select dominant hand. This affects gesture placement on the screen. Swipe up or down to change. Double tap to select. Or say out loud: Right, or Left.',
    'onb_mode_tts':
        'Step two. Select default operation mode. Swipe up or down to change. Double tap to select. Or say: Street, Cane, or Scan.',
    'onb_perm_tts':
        'Camera permission. Double tap to open the system request. Find the Allow button. Or say out loud: Allow.',
    'onb_calib_tts':
        'Distance calibration. Calibration is recommended for better accuracy. You can perform it later in settings by aiming the camera at a person 2 meters away. Double tap to continue.',
    'onb_ready_tts': 'All set. Double tap to start.',
    'onb_hand_right': 'Right hand',
    'onb_hand_left': 'Left hand',
    'onb_hand_changed': 'Dominant hand changed to {hand}',
    'onb_secondary_aid_tts':
        'Bagdar warns about hazards but can miss them. '
        'Continue using your white cane or guide dog. '
        'Bagdar is a secondary aid.',
    'onb_secondary_aid_check':
        'Bagdar is a secondary aid, not a cane replacement',
    'onb_blind_intro':
        'Bagdar for blind users. Gesture-based control. '
        'Single tap to repeat. Double tap to continue. '
        'Swipe right for next step, left to go back. '
        'Long press to change language. '
        'If a loved one is nearby, it is recommended to hand them the phone for initial setup.',
    'onb_gesture_help':
        'Onboarding gestures. Single tap repeats the prompt. '
        'Double tap is the main action. Swipe right or left to navigate. '
        'Long press changes language. Swipe down to skip onboarding. '
        'Two fingers for two seconds for emergency exit.',
    'onb_mode_select_announce': 'Mode: {mode}. Double tap to select.',
    'onb_skip_confirm':
        'Skip all setup? Double tap confirms. Single tap cancels.',
    'onb_skip_cancelled': 'Cancelled.',
    'onb_lang_switched': 'Language: English.',
    'onb_calib_saved_tts': 'Great! Calibration saved. Tap Continue.',
    'onb_calib_skip_tts':
        'Calibration skipped. You can do it later in settings.',
    'onb_welcome_title': 'Welcome\nto Bagdar',
    'onb_welcome_sub': 'Choose your default mode.\nYou can change it anytime.',
    'onb_perm_title': 'Access needed',
    'onb_perm_sub': 'Only camera is required.\nThe rest is optional.',
    'onb_calib_title': 'Distance accuracy',
    'onb_calib_sub':
        'Without calibration, error ~40%.\nAfter — ~10%. Takes 10 seconds.',
    'onb_calib_app_note':
        'Calibration can be done in Settings after starting the app.',
    'onb_ready_title': 'All set!',
    'onb_ready_sub': 'Bagdar is ready. Here is what the app can do:',
    'onb_btn_continue': 'Continue',
    'onb_btn_allow_camera': 'Allow camera',
    'onb_btn_skip': 'Skip the rest',
    'onb_btn_calibrate': 'I stand 2 meters away — calibrate',
    'onb_btn_skip_calib': 'Skip — set up later',
    'onb_btn_calib_later': 'Calibrate in settings',
    'onb_btn_start': 'Start',
    'onb_btn_back_calib': 'Back to calibration',
    'onb_calib_done': 'Calibration done — accuracy improved!',
    'onb_calib_hint': 'Ask someone to stand 2m away from you',
    'onb_check_alerts': 'Voice alerts for objects',
    'onb_check_mode': 'selected by default',
    'onb_check_calib': 'Camera calibration',
    'onb_check_calib_skip': 'Available in Settings → Camera calibration',
    'onb_feat_scan': '«What is around?» button — scene description',
    'onb_feat_mode': 'Mode icon — toggle Street / Cane / Scan',
    'onb_feat_settings': 'Settings — calibration, GPU, Debug HUD',
    'onb_lang_title': 'Choose a language',
    'onb_lang_sub': 'Language can be changed in settings',
    'onb_mic_exhausted':
        'I cannot hear your response. Use gestures: '
        'swipe up or down to select, double-tap to confirm. '
        'Tap once to have me repeat.',
    'onb_mode_choose_first':
        'Please choose a mode first. Say: street, cane, or scan.',
    'onb_perm_talkback_guide':
        'System permission dialogs will now appear. '
        'There will be three: camera, microphone, and location. '
        'Use TalkBack — swipe right to the Allow button and double-tap. '
        'I will wait.',
    'onb_perm_tap_guide':
        'System dialogs will now appear. '
        'In each one, tap the Allow button at the bottom of the screen. '
        'If a sighted helper is nearby, ask them for assistance. I will wait.',
    'onb_perm_camera_ok': 'Camera access granted.',
    'onb_perm_mic_ok': 'Microphone access granted.',
    'onb_perm_all_granted': 'All permissions granted. Excellent! Moving on.',
    'onb_perm_denied_retry':
        'Camera was not allowed. Without the camera, the app cannot detect obstacles. '
        'Say allow to try again, or skip to continue.',

    'tut_title': 'Gesture Tutorial',
    'tut_intro':
        'You will now learn how to control the app. '
        'Follow the voice prompts. '
        'You can skip at any time.',
    'tut_tap': 'Tap the screen once.',
    'tut_tap_done':
        'Great. A single tap gives a quick status: mode and battery.',
    'tut_double_tap': 'Now tap twice quickly.',
    'tut_double_tap_done': 'Great. Double tap opens settings.',
    'tut_long_press': 'Hold one finger on the screen for one second.',
    'tut_long_press_done': 'Great. A long press starts voice command.',
    'tut_swipe_horizontal': 'Swipe left or right across the screen.',
    'tut_swipe_horizontal_done': 'Great. A horizontal swipe switches mode.',
    'tut_swipe_up': 'Now swipe up.',
    'tut_swipe_up_done': 'Great. Swipe up opens help.',
    'tut_swipe_down_legacy': 'Now swipe down.',
    'tut_swipe_down_legacy_done': 'Great. Swipe down opens help.',
    'tut_two_finger':
        'Place two fingers on the screen together and hold for one and a half seconds.',
    'tut_two_finger_done':
        'Great. Two fingers for one and a half seconds triggers SOS.',
    'tut_finished':
        'Tutorial complete. Voice commands for SOS and help are also available.',
    'tut_skip': 'Skip',
    'tut_replay': 'Replay gesture tutorial',
    'tut_finish': 'Finish',
    'tut_progress': 'Step {step} of {total}',
    'tut_fail_hint':
        'Trouble? Say "skip" to move on. '
        'Or say "repeat" to hear the prompt again.',
    'tut_detail_tap':
        'Quickly touch the screen with one finger and lift it. '
        'A short tap, no hold.',
    'tut_detail_doubleTap':
        'Tap the screen twice quickly. '
        'Less than half a second between taps.',
    'tut_detail_longPress':
        'Press your finger on the screen and hold for about one second '
        'until you hear confirmation.',
    'tut_detail_swipeHorizontal':
        'Place your finger on the screen and slide left or right. '
        'A continuous, fast motion.',
    'tut_detail_swipeVertical':
        'Place your finger and swipe up or down with a quick motion.',
    'tut_detail_twoFinger':
        'Place two fingers on the screen at the same time '
        'and hold for one and a half seconds.',

    'mode_street': 'Street',
    'mode_cane': 'Cane',
    'mode_scan': 'Scan',
    'mode_street_desc': 'Cars, people, obstacles — full alert stack',
    'mode_cane_desc': 'Maximum haptics, minimum speech',
    'mode_scan_desc': 'Verbal scene description every 4 seconds',

    'perm_camera': 'Camera',
    'perm_camera_reason': 'Core app function',
    'perm_camera_required': 'Required',
    'perm_mic': 'Microphone',
    'perm_mic_reason': 'Voice commands (future feature)',
    'perm_location': 'Location',
    'perm_location_reason': 'SOS mode — send your location to loved ones',
    'perm_optional': 'Later',

    'settings': 'Settings',
    'settings_a11y_title': 'Accessibility',
    'settings_classic_gestures': 'Classic gestures',
    'settings_classic_gestures_desc':
        'Swipe up for curtain, swipe down for help',
    'settings_speech_rate': 'Speech rate',
    'settings_tts_volume': 'Speech volume',
    'settings_earcon_volume': 'Earcon volume',
    'settings_verbosity': 'Verbosity',
    'verbosity_minimal': 'Minimal',
    'verbosity_normal': 'Normal',
    'verbosity_detailed': 'Detailed',
    'settings_alert_frequency': 'Alert frequency',
    'freq_rare': 'Rare',
    'freq_normal': 'Normal',
    'freq_frequent': 'Frequent',
    'settings_haptic_strength': 'Haptic strength',
    'haptic_weak': 'Weak',
    'haptic_normal': 'Normal',
    'haptic_strong': 'Strong',
    'settings_sos_trigger': 'SOS trigger',
    'sos_trigger_two_finger': 'Two fingers 2 sec',
    'sos_trigger_triple_tap': 'Triple tap',
    'sos_trigger_shake': 'Shake device',
    'settings_dominant_hand': 'Dominant hand',
    'hand_right': 'Right',
    'hand_left': 'Left',
    'cancel': 'Cancel',
    'save': 'Done',
    'ok': 'OK',

    'backup_section_title': 'Settings backup',
    'backup_show_qr': 'Show settings QR',
    'backup_show_qr_subtitle': 'Show this to a helper to copy settings',
    'backup_scan_qr': 'Scan settings QR',
    'backup_scan_qr_subtitle': 'Read a QR from another device',
    'qr_dismiss': 'Close',
    'qr_export_title': 'Settings QR',
    'qr_export_ready': 'QR ready. Show it to a helper to copy your settings.',
    'qr_export_hint': 'Show this QR to a helper or another device.',
    'qr_export_footer': 'SOS contact is not exported.',
    'qr_export_semantics': 'QR code with accessibility settings',
    'qr_import_title': 'Scan QR',
    'qr_import_aim_camera': 'Aim the camera at a settings QR.',
    'qr_import_aim_hint': 'Aim the camera at the QR code.',
    'qr_import_torch': 'Torch',
    'qr_import_found': 'QR detected',
    'qr_import_version': 'version',
    'qr_import_lang': 'language',
    'qr_import_speech_rate': 'speech rate',
    'qr_import_tts_volume': 'speech volume',
    'qr_import_earcon_volume': 'sound volume',
    'qr_import_hold_to_apply': 'Hold the button for 1.5 seconds to apply.',
    'qr_import_long_press': 'Hold to apply',
    'qr_import_applying': 'Applying...',
    'qr_import_applied': 'Settings applied.',
    'qr_import_failed': 'Could not apply QR. Please try again.',
    'qr_import_retry': 'Scan again',

    'voice_listening': 'Listening...',
    'voice_not_available': 'Voice commands not available.',
    'voice_no_permission': 'No microphone access.',
    'voice_unknown': 'Command not recognized.',
    'voice_listen_error': "Didn't hear you. Please repeat.",
    'voice_hint': 'Hold screen for voice command.',
    'voice_commands_list':
        'Available commands: what is around, what is left, what is right, '
        'what is ahead, read, mode, pitch black.',
    'voice_settings_commands':
        'Settings commands: faster, slower, volume up, volume down, '
        'minimal verbosity, normal verbosity, detailed verbosity, '
        'rare alerts, normal alerts, frequent alerts, '
        'set sos to triple tap, set sos to shake, strong vibration, weak vibration.',

    'obj_remember_listening': 'Remembering {name}. Hold closer.',
    'obj_remember_saved': '{name} remembered.',
    'obj_remember_failed': "I can't see the object. Try again.",
    'obj_remember_capacity': 'Memory is full. Forget something first.',
    'obj_find_started': 'Searching for {name}.',
    'obj_find_position': '{name}, {dist} meters, {dir}.',
    'obj_find_position_no_dist': '{name}, {dir}.',
    'obj_find_lost': "I don't see {name}.",
    'obj_find_found': '{name} in front of you.',
    'obj_find_stopped': 'Search stopped.',
    'obj_find_searching': 'Still searching for {name}...',
    'obj_forget_done': '{name} forgotten.',
    'obj_forget_unknown': "I don't remember {name}.",
    'obj_unknown_target': "I don't remember such object. Say remember {name}.",
    'obj_busy_remembering': 'Currently remembering, please wait.',

    'fg_notification_title': 'Bagdar is active',
    'fg_notification_body': 'Navigation is running in background.',

    'battery_low': 'Battery low. Running in eco mode. Stay extra alert.',
    'battery_low_depth_off':
        'Battery low. Depth detection in eco mode. Stay extra alert.',
    'battery_low_critical':
        'Critical battery. Running in lowest mode. Stay extra alert.',
    'battery_moderate': 'Battery moderate — saving energy.',
    'battery_normal': 'Battery normal.',
    'thermal_warning_warm': 'Device warming up. Scan rate reduced.',
    'thermal_warning_hot':
        'System getting hot. Scan rate reduced, walk slower.',
    'thermal_warning_critical':
        'Critical temperature. Scan rate heavily reduced.',
    'thermal_ground_hazard_reduced':
        'High temperature. Pothole and step detection is temporarily reduced.',
    'thermal_warm_move_to_shade':
        'Device warming up. Move to shade if possible. '
        'Detection accuracy reduces at higher temperatures.',
    'running_detected': 'You are running. Please slow down for safety.',
    'battery_50_remaining':
        'Battery at 50%. Approximately two hours of active detection remaining.',
    'battery_30_warning': 'Battery at 30%. Consider shortening your walk.',
    'battery_15_critical':
        'Battery at 15%. Ground hazard detection is reduced. Please use a cane or seek assistance.',
    'low_light_warning':
        'Low light detected. Detection accuracy is reduced. Please use additional caution.',
    'pitch_black_ui': 'Pitch Black',
    'pitch_black_ui_desc': 'Hides camera preview and whole navigation ui.',
    'pitch_black_on': 'Pitch black mode enabled.',
    'pitch_black_off': 'Pitch black mode disabled.',
    'audio_route_interrupted': 'Audio interrupted. Check your headphones.',
    'audio_resumed': 'Audio resumed.',
    'tts_fallback_en':
        'Voice pack for your language is missing. Using English fallback.',
    'fall_detector_unavailable':
        'Fall detector unavailable. Automatic SOS disabled.',
    'fall_detector_degraded':
        'Fall detection accuracy reduced. Gyroscope unavailable.',
    'yolo_unavailable':
        'Object recognition unavailable. Hazard detection disabled.',
    'yolo_detector_not_responding': 'Object detector not responding.',
    'test_alert_warning': 'Test: warning left',
    'test_alert_critical': 'Test: critical center',
    'lifecycle_background':
        'App hidden. Bring it to foreground, otherwise scanning stops',
    'lifecycle_resumed': 'App resumed.',

    'night_mode_on': 'Night mode on.',
    'night_mode_off': 'Night mode off.',

    'guide_dog_on': 'Guide dog mode on.',
    'guide_dog_off': 'Guide dog mode off.',
    'hazard_low_curb': 'Low curb ahead.',
    'hazard_near_field': 'Object below camera.',
    'weather_low_vis': 'Low visibility. Accuracy reduced.',
    'weather_restored': 'Visibility restored.',
    'indoor_mode_entered': 'Indoor mode.',
    'indoor_mode_exited': 'Outdoor mode.',
    'camera_partial_blocked': 'Camera partially blocked. Check the lens.',
    'group_ahead': 'Group ahead: ',
    'camera_reinit': 'Camera restarting. Please wait.',
    'camera_droplet': 'Possible droplet on lens. Wipe clean.',
    'camera_smear': 'Lens smeared. Wipe clean.',

    'waypoint_saved': 'Location saved',
    'waypoint_near': 'You are near',
    'waypoint_name_prompt': 'Location title',
    'waypoint_none': 'No saved locations.',
    'waypoint_deleted': 'Location deleted.',

    'sos_sent': 'SOS sent.',
    'sos_queued': 'SOS queued, awaiting confirmation.',
    'sos_sent_no_location': 'SOS sent, but location could not be determined.',
    'sos_indoor_warning': 'You are indoors. Coordinates may be inaccurate.',
    'sos_no_contact': 'No SOS contact specified. Set it up in settings.',
    'sos_no_location': 'Could not determine location.',
    'sos_no_gps': 'location unavailable',
    'sos_settings': 'SOS contact',
    'sos_message': 'I need help! My location:',
    'sos_invalid_number': 'Invalid phone number.',
    'sos_launch_failed': 'Could not launch SMS app.',
    'sos_error': 'Failed to send SOS.',
    'sos_fall_detected':
        'Fall detected. SOS will be sent in 15 seconds. Tap screen to cancel.',
    'sos_fall_classb_detected':
        'Are you OK? Tap screen to cancel. SOS will be sent in 30 seconds.',
    'sos_fall_countdown': 'SOS in',
    'sos_fall_seconds': 'seconds.',
    'sos_fall_cancelled': 'SOS cancelled.',
    'sos_fall_sent': 'SOS sent after fall.',
    'sos_user_fallen_again': 'Alert: user has fallen again.',
    'sos_fall_cancel_hint':
        'Say "I am fine" or "false alarm". Tap screen to cancel.',
    'sos_fall_voice_confirm_prompt': 'Confirm: say "I am fine".',
    'sos_fall_voice_cancel_rejected':
        'Cancel not confirmed. Countdown continues.',
    'sos_fall_are_you_ok': 'Are you ok? Tap to confirm.',
    'sos_cancel_confirm': 'Tap again to cancel SOS.',
    'sos_112_fallback':
        'No contact specified. SOS will be sent to emergency 112.',
    'sos_position_stale': 'Location is stale by',
    'sos_position_unit_min': 'minutes',
    'sos_sending': 'Sending SOS...',
    'sos_retry': 'Retrying SOS.',
    'sos_delivered': 'SOS delivered.',
    'sos_composer_opened':
        'Message composer opened. Tap the Send button at the bottom right.',
    'sos_dialer_opened': 'Phone dialer opened. Press the green call button.',
    'sos_planned_destination': 'Heading to:',
    'sos_near_wifi': 'Near Wi-Fi:',
    'sos_near_cell': 'Near cell:',
    'sos_steps_from_last': 'steps',
    'sos_of_last_known': 'from last known location',
    'sos_dir_n': 'north',
    'sos_dir_ne': 'northeast',
    'sos_dir_e': 'east',
    'sos_dir_se': 'southeast',
    'sos_dir_s': 'south',
    'sos_dir_sw': 'southwest',
    'sos_dir_w': 'west',
    'sos_dir_nw': 'northwest',
    'camera_blocked': 'Camera blocked. Check the lens.',
    'camera_ae_transition': 'Camera adjusting to light. Be careful.',
    'camera_frozen': 'Warning, camera image is frozen. Restart app.',
    'camera_stalled': 'Camera stalled. Stop and check the app.',
    'camera_resumed': 'Camera functioning again.',
    'shake_warning': 'Camera shaking heavily. Slow down or keep phone steady.',
    'nav_maybe_off_route': 'You might be off route.',
    'pitch_too_high': 'Tilt phone downwards to scan the floor.',
    'pitch_too_low': 'Tilt phone slightly up.',
    'pitch_misaligned_blind': "Raise the phone — I can't see the road.",
    'phone_abandoned': 'Bagdar is lying down — please check your phone.',
    'winter_visibility_heartbeat': 'Low visibility — walk carefully.',
    'curtain_on': 'Screen curtain on. Screen hidden.',
    'curtain_off': 'Screen curtain off.',
    'help_summary':
        'Controls help. '
        'Single tap for quick status. '
        'Double tap for settings. '
        'Hold one finger for voice command. '
        'Swipe left or right to switch mode. '
        'Swipe up for this help. '
        'Swipe down for screen curtain. '
        'Hold two fingers for two seconds for SOS. '
        'Or say sos for emergency, gestures for this help.',
    'help_summary_classic':
        'Controls help. '
        'Single tap for quick status. '
        'Double tap for settings. '
        'Hold one finger for voice command. '
        'Swipe left or right to switch mode. '
        'Swipe up for screen curtain. '
        'Swipe down for this help. '
        'Hold two fingers for two seconds for SOS. '
        'Or say sos for emergency, gestures for this help.',
    'status_quick': 'Mode {mode}. Battery {battery} percent.',
    'status_quick_mode_only': 'Mode {mode}.',
    'gesture_weak': 'Swipe too weak. Move finger faster.',
    'camera_screen_semantics':
        'Bagdar camera screen. '
        'Single tap — mode and battery. '
        'Double tap — settings. '
        'Long press — voice command. '
        'Swipe left or right — switch mode. '
        'Swipe up — help. Swipe down — screen curtain. '
        'Two fingers for one and a half seconds — emergency SOS.',
    'camera_screen_semantics_classic':
        'Bagdar camera screen. '
        'Single tap — mode and battery. '
        'Double tap — settings. '
        'Long press — voice command. '
        'Swipe left or right — switch mode. '
        'Swipe up — screen curtain. Swipe down — help. '
        'Two fingers for one and a half seconds — emergency SOS.',
    'tl_green_warning': 'Please rely on traffic sounds to ensure safety.',
    'tl_green_wait':
        'Light is green. Do not cross until traffic stops completely.',
    'tl_green_cars_near': 'Light is green, but cars are near. Wait.',
    'tl_vehicle':
        'Vehicle traffic light. Do not rely on it, listen to crossing sounds.',

    'depth_unavailable': 'Depth detection unavailable.',
    'depth_unavailable_street':
        'Warning: floor-level obstacle safety is off on this device. Curb, stair and pothole detection are not active. Please use your cane',
    'depth_session_disabled':
        'Depth detection disabled due to repeated errors. Stairs and curbs will not be announced until you restart the app. Walk with care',
    'hazard_detection_resumed': 'Hazard detection resumed.',
    'depth_paused_explicit': 'Stair and curb detection are paused.',
    'weather_depth_off_walking':
        'Visibility is poor. Stairs and curbs may not be detected. Walk slowly.',
    'depth_degraded': 'Depth quality degraded. Pay extra attention.',
    'depth_recovered': 'Depth quality recovered.',
    'depth_quality_low': 'Depth quality low. Switching to MiDaS.',
    'reduced_mode_depth': 'Operating in reduced mode — depth disabled.',
    'reduced_mode_restored': 'Depth restored.',

    'camera_perm_title': 'No camera access',
    'camera_perm_body':
        'Camera is required for Bagdar to work.\n'
        'Please go to Settings and allow camera.',
    'camera_perm_blind_intro':
        'Camera is blocked by the system. '
        'Double tap to open phone settings. '
        'Single tap to cancel.',
    'camera_perm_denied_retry':
        'Camera access was denied. Without it Bagdar cannot see obstacles. '
        'Double tap to try again.',
    'calib_no_person': 'No person in frame. Aim the camera and try again.',
    'calib_invalid_dist': 'Enter a valid distance (0–50 m)',

    'nav_destination': 'destination',
    'nav_route_built': 'Route built to',
    'nav_approx': 'About',
    'nav_minutes': 'minutes',
    'nav_arrived': 'You have arrived at',
    'nav_arrived_short': 'Arrived.',
    'hud_riding': 'En route',
    'hud_uturn': 'U-turn',
    'nav_arriving': 'Arriving.',
    'nav_not_active': 'Navigation inactive.',
    'nav_remaining': 'Remaining',
    'nav_no_gps': 'GPS unavailable.',
    'nav_your_position': 'Your position:',
    'nav_go_straight': 'Go straight',
    'nav_turn_left': 'Turn left',
    'nav_turn_right': 'Turn right',
    'nav_u_turn': 'Perform a U-turn',
    'nav_turn_around': 'Turn around',
    'nav_arrive': 'Arrive',
    'nav_searching': 'Searching...',
    'nav_not_found': 'Location not found.',
    'nav_building_route': 'Building route...',
    'nav_route_failed': 'Could not build route.',
    'nav_stopped': 'Navigation stopped.',
    'nav_no_api_key': '2GIS key missing. Provide in settings.',
    'nav_off_route': 'You are off route.',
    'nav_rerouting_try': 'Rerouting.',
    'nav_reroute_failed': 'Could not reroute. Stop safely and say where am i.',
    'nav_reroute_ok': 'New route ready.',
    'nav_bearing_return':
        'Route is behind you, turn around and ask where am i.',

    'nav_transit_route_built': 'Transit route to',
    'nav_walk': 'Walk',
    'nav_take_bus': 'Take bus number',
    'nav_from_stop': 'from stop',
    'nav_ride_stops': 'Stops to ride:',
    'nav_wait_bus': 'Wait for bus number',
    'nav_at_stop': 'You are at the stop',
    'nav_exit_now': 'Exit now! Stop',
    'nav_stops_remaining': 'Stops left:',
    'nav_boarding_confirmed': 'You boarded. Tracking stops.',
    'nav_walking_to_stop': 'Walking to stop.',
    'nav_waiting': 'Waiting for transport.',
    'nav_waiting_for': 'Waiting for bus',
    'nav_riding': 'Riding to',
    'nav_walk_to_dest': 'Walking to destination.',
    'nav_nearest_stop': 'Nearest stop',
    'nav_gps_wait': 'Waiting for GPS signal...',
    'nav_gps_unreliable': 'GPS unreliable. Pausing turn-by-turn.',
    'nav_gps_restored': 'GPS restored.',
    'nav_rerouting': 'Rerouting...',
    'nav_auto_boarded': 'Movement detected. Tracking stops.',
    'nav_bus_interval': 'Next bus in about',
    'nav_bus_minutes': 'minutes.',
    'nav_bus_not_running': 'Bus is currently not running.',

    'tl_red': 'Traffic light is red. Wait.',
    'tl_yellow': 'Traffic light is yellow. Wait.',
    'tl_green': 'Traffic light is green.',
    'tl_green_safe': 'Traffic light might be green. Rely on traffic sound.',
    'tl_green_cars': 'Traffic light is green, but cars are around. Wait.',
    'tl_unknown': 'Cannot detect traffic light color. Be careful.',
    'tl_uncertain': 'Traffic light unclear. Be careful.',
    'tl_ahead': 'Traffic light ahead.',

    'nav_api_key_label': '2GIS API Key',
    'nav_api_key_hint': 'Enter API key',
    'nav_api_key_saved': 'Key saved.',

    'nav_offline_ready': 'Offline map loaded.',
    'nav_offline_not_ready': 'Offline map not loaded. Using online.',
    'nav_download_map': 'Download map',
    'nav_downloading_map': 'Downloading map...',
    'nav_download_complete': 'Map downloaded.',
    'nav_download_failed': 'Failed to download map.',
    'nav_download_progress': 'Downloading',
    'nav_delete_map': 'Delete map',
    'nav_map_deleted': 'Map deleted.',
    'nav_select_city': 'Select city',
    'nav_city_astana': 'Astana',
    'nav_city_almaty': 'Almaty',
    'nav_no_map': 'Download city map for offline navigation.',
    'nav_map_update': 'Map update available.',
    'nav_map_stale': 'Offline map might be stale. Check for updates.',
    'nav_map_updated': 'Map updated.',
    'nav_disk_space': 'Not enough disk space.',
    'nav_surface_gravel': 'Gravel road.',
    'nav_surface_unpaved': 'Unpaved road.',
    'nav_tactile_yes': 'Tactile paving.',
    'nav_steps_ahead': 'Steps ahead.',
    'nav_no_sidewalk': 'No sidewalk.',

    'gtfs_route_info': 'Route',
    'gtfs_schedule': 'Schedule',
    'gtfs_working_hours': 'Working hours',
    'gtfs_interval': 'Interval',
    'gtfs_minutes': 'minutes',
    'gtfs_stops_count': 'Stops count',
    'gtfs_from': 'From',
    'gtfs_to': 'To',
    'gtfs_not_found': 'Route not found.',
    'gtfs_stale': 'Schedule might be stale. Check for updates.',
    'gtfs_bus_routes': 'Bus routes at stop',

    'tts_lang_title': 'Voice not found',
    'tts_lang_body':
        'Voice pack for the selected language is not installed. '
        'Go to Settings → Accessibility → '
        'Text-to-speech output and install voice data.',
    'tts_lang_open': 'OK',

    'sem_step_of': 'Step {step} of {total}',
    'sem_required': 'Required',
    'sem_optional_perm': 'Optional',
    'sem_done': 'Done',
    'sem_not_done': 'Not done',
    'sem_on': 'on',
    'sem_off': 'off',

    'tts_kk_guide_title': 'Install Kazakh voice',
    'tts_kk_guide_body':
        'For proper Kazakh pronunciation, install a voice pack. '
        'Go to Settings → Accessibility → '
        'Text-to-speech → Install voice data → Kazakh.',
    'tts_kk_open_settings': 'Open TTS settings',
    'tts_kk_not_available':
        'Kazakh voice not found. Voice assistant uses Russian accent.',

    'lang_switched': 'Language changed.',

    'pref_clear_path_announce': 'Announce "Path clear"',
    'pref_battery_announce': 'Battery level announcements',
    'pref_mode_announce': 'Mode change announcements',

    'vc_speed_up': 'Speech faster.',
    'vc_speed_down': 'Speech slower.',
    'vc_volume_up': 'Volume up.',
    'vc_volume_down': 'Volume down.',
    'vc_battery_status': 'Battery {battery} percent.',

    'audio_tour':
        'You are on the main screen. '
        'Camera is active and scanning your surroundings. '
        'Swipe left or right to switch modes. '
        'Hold your finger for voice command. '
        'Swipe up for help.',
    'audio_tour_done': 'Enjoy using the app!',

    'onb_sos_title': 'Emergency contact',
    'onb_sos_sub':
        'Enter the number of a trusted person.\\nBagdar will send an SMS with your location in an emergency.',
    'onb_sos_tts':
        'Enter a number for emergencies. '
        'Bagdar will send an SMS with your location. '
        'You can skip this and set it up later.',
    'onb_sos_placeholder': '+1 (___) ___-____',
    'onb_sos_save': 'Save contact',
    'onb_sos_skip': 'Set up later',

    'settings_calibration': 'Camera calibration',
    'settings_calibration_desc': 'Stand exactly 2m from a person and tap',
    'settings_read_text': 'Read text',
    'settings_read_text_desc': 'OCR — recognize text in frame',
    'settings_cpu_threads': 'CPU threads',
    'settings_lang_label': 'Language',
    'settings_earcon_title': 'Earcon sounds',
    'settings_earcon_desc': 'Instant tones for events',
    'settings_depth_active': 'Depth analysis: active',
    'settings_depth_not_ready': 'Depth analysis: not ready',
    'settings_scan_left': 'What is left?',
    'settings_scan_forward': 'What is ahead?',
    'settings_scan_right': 'What is right?',
    'settings_haptic_test': 'Vibration test (Cane mode)',
    'settings_earcon_test': 'Earcon sound test',
    'settings_sos_not_set': 'Not set',

    'path_clear_minimal': 'Analysis active.',
    'hazard_stairs_down_minimal': 'Stairs. Stop.',
    'hazard_overhead_minimal': 'Obstacle. Stop.',
    'camera_blocked_minimal': 'Camera blocked.',

    'scene_see_count': 'I see {count} objects.',
    'scene_see_one': 'I see one object.',
    'scene_see_none': 'Nothing recognized.',
    'scene_object_entry': '{label} {direction}',
    'scene_object_dist': ', approximately {dist}',
    'scene_object_approaching': ', approaching',
    'scene_hazard_intro': 'On the ground:',
    'scene_traffic_light': 'Traffic light {color}.',
    'scene_color_red': 'red',
    'scene_color_yellow': 'yellow',
    'scene_color_green': 'green',
    'scene_ocr_read': 'Sign reads: {text}.',
    'scene_left_only': 'On the left:',
    'scene_right_only': 'On the right:',
    'scene_ahead_only': 'Ahead:',
    'scene_narrating': 'Describing...',
    'scene_cooldown': 'Wait before describing again.',

    'sms_payment_received': 'Received',
    'sms_payment_sent': 'Sent',
    'sms_payment_from': 'from',
    'sms_balance': 'Balance',
    'sms_currency_kzt': 'tenge',
    'sms_currency_rub': 'rubles',
    'sms_currency_usd': 'dollars',
    'sms_currency_eur': 'euros',
    'sms_notifications_enabled': 'Payment notifications enabled.',
    'sms_notifications_disabled': 'Payment notifications disabled.',
    'sms_permission_denied':
        'No permission to read incoming SMS. Open settings and grant access.',
    'acoustic_vehicle_left': 'Vehicle on the left.',
    'acoustic_vehicle_right': 'Vehicle on the right.',
    'acoustic_vehicle_behind': 'Vehicle sound.',
    'acoustic_horn': 'Horn!',
    'acoustic_siren': 'Siren nearby.',
    'acoustic_dog': 'Dog nearby.',
    'acoustic_dog_left': 'Dog on the left.',
    'acoustic_dog_right': 'Dog on the right.',
    'acoustic_crowd_dense': 'Crowded area.',
    'acoustic_construction': 'Construction nearby.',
    'awm_enabled': 'Acoustic sensing enabled.',
    'awm_disabled': 'Acoustic sensing disabled.',

    'shelf_camera_short': 'Camera',
    'shelf_read_short': 'Read',
    'shelf_navigate_short': 'Where to',
    'shelf_camera_label': 'Camera. Active.',
    'shelf_camera_hint': 'Double-tap to return to normal mode.',
    'shelf_read_label': 'Read aloud what the camera sees.',
    'shelf_read_hint': 'Double-tap to start reading.',
    'shelf_navigate_label': 'Set a route by voice.',
    'shelf_navigate_hint': 'Double-tap to choose destination.',
    'shelf_read_started': 'Reading what I see. Hold the phone steady.',
    'shelf_navigate_started': 'Where shall I take you? Say the place name.',
    'shelf_cane_confirm': 'Hold for one second to switch mode.',
    'ocr_aim_hint': 'Hold the text closer and keep the camera steady.',
    'ocr_timeout': 'Could not find text in eight seconds. Try again.',
    'ocr_lines_count': 'Found {n} lines. Reading now.',
    'processing_heartbeat': 'Analyzing... please hold.',
    'pitch_black_heartbeat': '',
    'offline_banner_no_gps': 'No GPS. Position approximate.',
    'offline_banner_no_map': 'Area map not loaded. Say "download map".',
    'settings_save_failed': 'Could not save setting. Try again.',
    'theme_selected_dark': 'Dark theme, black screen with yellow accent.',
    'theme_selected_light': 'Light theme, white screen with deep navy accent.',
    'theme_selected_high_contrast': 'High contrast, white on black only.',
    'theme_selected_warm': 'Warm theme, cream screen with dark brown text.',
    'voice_layer_listening': 'Listening for a command.',
    'voice_layer_cancel': 'Cancel listening.',
    'restart_pipeline': 'Restart recognition.',
    'restart_pipeline_done': 'Recognition restarted.',
    'lang_pack_required_for_kk':
        'For better Kazakh recognition, please download the language pack.',
    'lang_pack_downloading': 'Downloading Kazakh language pack.',
    'lang_pack_install_complete': 'Kazakh language pack installed.',
    'lang_pack_install_failed': 'Failed to install Kazakh pack.',
    'lang_pack_offline_skip': 'Offline. Will ask next time online.',
    'vosk_kk_loading': 'Preparing Kazakh recognition.',
    'vosk_kk_load_failed': 'Could not load Kazakh recognition. Using fallback.',
    'lang_packs_screen_title': 'Language packs',
    'lang_packs_screen_intro': 'Manage language packs for Kazakh.',
    'lang_packs_v2_toggle_label': 'Enhanced Kazakh recognition',
    'lang_packs_v2_toggle_desc':
        'Use Vosk for Kazakh speech recognition. Requires the language pack.',
    'lang_packs_v2_enabled': 'Enhanced recognition enabled.',
    'lang_packs_v2_disabled': 'Enhanced recognition disabled.',
    'lang_packs_refresh': 'Refresh list',
    'lang_packs_refresh_done': 'Pack list refreshed.',
    'lang_packs_refresh_failed': 'Failed to refresh list. Check the network.',
    'lang_packs_install': 'Install',
    'lang_packs_delete': 'Delete',
    'lang_packs_update': 'Update',
    'lang_packs_installed': 'Installed',
    'lang_packs_not_installed': 'Not installed',
    'lang_packs_size_mb': '{size} MB',
    'lang_packs_no_packs': 'No language packs available. Tap Refresh.',
    'lang_packs_close': 'Close',
    'lang_packs_delete_confirm': 'Delete pack {name}?',
    'voice_kk_v2_pack_missing':
        'Pack not installed. Open language packs to install.',
    'voice_manage_lang_packs_announce': 'Opening language packs.',
    'onb_kk_pack_prompt_title': 'Kazakh recognition',
    'onb_kk_pack_prompt_body':
        'Download the Kazakh recognition pack now? About 50 MB.',
    'onb_kk_pack_yes': 'Download',
    'onb_kk_pack_skip': 'Skip',
    'onb_kk_pack_later': 'Remind me online',
    'lang_pack_online_ready':
        'You are online. The Kazakh recognition pack is ready to install. '
        'Say "language packs".',

    'tts_kk_engine_system': 'System Kazakh voice',
    'tts_kk_engine_rhvoice': 'RHVoice (Aigul)',
    'tts_kk_engine_espeak': 'espeak-ng (fallback)',
    'tts_kk_engine_fallback_ru': 'Russian voice reading Kazakh text',
    'tts_kk_using_rhvoice': 'Using RHVoice for Kazakh.',
    'tts_kk_using_espeak':
        'Using the basic Kazakh voice. Pronunciation may be simplified.',
    'tts_kk_using_system': 'Using the system Kazakh voice.',
    'tts_kk_using_russian_fallback':
        'Kazakh voice is unavailable. Reading Kazakh text with the Russian voice.',
    'tts_kk_engine_load_failed':
        'Failed to load the Kazakh voice. Falling back.',
    'onb_rhvoice_pack_prompt_title': 'Better Kazakh voice',
    'onb_rhvoice_pack_prompt_body':
        'Download a high-quality Kazakh voice now? About 30 MB. The voice works offline.',
    'onb_rhvoice_pack_yes': 'Download',
    'onb_rhvoice_pack_skip': 'Skip',
    'onb_rhvoice_pack_later': 'Remind me online',
    'lang_pack_rhvoice_online_ready':
        'You are online. The Kazakh voice pack is ready to install. '
        'Say "language packs".',

    'trail_recording_started':
        'Trail recording started. Walk to your destination.',
    'trail_recording_stopped': 'Trail saved.',
    'trail_recording_failed': 'Could not start trail recording.',
    'trail_recording_empty': 'Trail is empty, not saved.',
    'trail_recording_cancelled': 'Trail recording cancelled.',
    'trail_landmark_added': 'Landmark marked.',
    'trail_replay_started': 'Following trail.',
    'trail_replay_stopped': 'Trail replay stopped.',
    'trail_not_found': 'Trail not found.',
    'trail_deleted': 'Trail deleted.',
    'trail_arrived': 'You have arrived.',
    'trail_lost': 'Trail lost. Go back.',
    'trail_continue_straight': 'Continue straight, {n} steps left.',
    'trail_turn_left': 'Turn left.',
    'trail_turn_right': 'Turn right.',
    'trail_slight_left': 'Slightly left.',
    'trail_slight_right': 'Slightly right.',

    'bazaar_mode_on': 'Bazaar mode on.',
    'bazaar_mode_off': 'Bazaar mode off.',
    'livestock_mode_on': 'Livestock mode on.',
    'livestock_mode_off': 'Livestock mode off.',
    'livestock_cow': 'Cow',
    'livestock_horse': 'Horse',
    'livestock_sheep': 'Sheep',
    'livestock_dog': 'Dog',
    'livestock_cat': 'Cat',
    'livestock_bird': 'Bird',

    'voice_adapt_on': 'Voice adaptation enabled. Data stays on device.',
    'voice_adapt_off': 'Voice adaptation disabled.',
    'voice_adapt_samples_cleared': 'Adaptation data cleared.',

    'mesh_hazard_generic': 'Another user reported an obstacle nearby.',
    'mesh_hazard_pothole': 'Another user reported a pothole nearby.',
    'mesh_hazard_construction': 'Another user reported construction nearby.',
    'mesh_hazard_ice': 'Another user reported ice nearby.',
    'mesh_hazard_stairs': 'Another user reported stairs nearby.',
    'mesh_buddy_started': 'Buddy network enabled.',
    'mesh_buddy_stopped': 'Buddy network disabled.',
    'mesh_buddy_no_ble': 'Bluetooth not supported. Buddy network unavailable.',

    'oscp_near_field': 'Cane: obstacle ahead',
    'oscp_connected': 'Smart cane connected.',
    'oscp_disconnected': 'Smart cane disconnected.',
    'oscp_battery_low': 'Smart cane battery low.',
    'oscp_no_ble': 'Bluetooth not supported. Smart cane unavailable.',

    'near_miss_recorded': 'Near-miss recorded.',
    'near_miss_cleared': 'Near-miss records cleared.',

    'vlm_loading': 'Loading scene description model.',
    'vlm_ready': 'Scene description model ready.',
    'vlm_not_available':
        'Scene description not available. Charging and free memory required.',
    'vlm_thinking': 'Thinking...',
    'vlm_answer_fallback': 'Model did not respond. Using standard description.',

    'sonar_near_field': 'Sonar: object ahead',
    'sonar_started': 'Sonar enabled.',
    'sonar_stopped': 'Sonar disabled.',
    'sonar_calibrating': 'Calibrating sonar.',
    'sonar_no_48k': 'Microphone does not support sonar.',
    'onb_mic_prime_tts':
        'For voice control, I need access to your microphone. A system dialog will appear now.',
    'onb_mic_denied_fallback_tts':
        'Microphone access denied. Voice control is disabled. Please use gestures to configure.',
    'onb_mode_confirm_prompt':
        'Mode selected. Say yes to continue, or choose another mode.',
    'sos_setup_prompt_tts':
        'Please set a contact number for emergency SOS help.',
    'camera_perm_recovery_tts':
        'Camera permission is blocked. Please allow access in phone settings. Double tap for settings, single tap to retry.',
    'onb_help_prompt_lang':
        'Choose language. Say: Russian, Kazakh, or English.',
    'onb_help_prompt_hand': 'Choose dominant hand. Say: Right or Left.',
    'onb_help_prompt_mode': 'Choose default mode. Say: Street, Cane, or Scan.',
    'onb_help_prompt_perm': 'Grant camera permission. Say: Allow.',
    'onb_help_prompt_calib': 'Distance calibration. Say: Yes to continue.',
    'onb_help_prompt_ready': 'Ready to start. Say: Yes to start.',
    'onb_emergency_skip_confirm':
        'Skip all setup? Double tap to confirm. Single tap to cancel.',
  },
};

const Map<AppLanguage, Map<String, String>> _labels = {
  AppLanguage.ru: {
    'person': 'человек',
    'bicycle': 'велосипед',
    'motorcycle': 'мотоцикл',
    'car': 'машина',
    'bus': 'автобус',
    'truck': 'грузовик',
    'stop sign': 'знак стоп',
    'traffic light': 'светофор',
    'dog': 'собака',
    'cat': 'кошка',
    'bench': 'скамейка',
    'fire hydrant': 'гидрант',
    'parking meter': 'паркомат',
    'backpack': 'рюкзак',
    'handbag': 'сумка',
    'suitcase': 'чемодан',
    'umbrella': 'зонт',
  },
  AppLanguage.kk: {
    'person': 'адам',
    'bicycle': 'велосипед',
    'motorcycle': 'мотоцикл',
    'car': 'көлік',
    'bus': 'автобус',
    'truck': 'жүк көлігі',
    'stop sign': 'стоп белгісі',
    'traffic light': 'бағдаршам',
    'dog': 'ит',
    'cat': 'мысық',
    'bench': 'орындық',
    'fire hydrant': 'өрт гидранты',
    'parking meter': 'паркомат',
    'backpack': 'рюкзак',
    'handbag': 'сөмке',
    'suitcase': 'чемодан',
    'umbrella': 'қолшатыр',
  },
  AppLanguage.en: {
    'person': 'person',
    'bicycle': 'bicycle',
    'motorcycle': 'motorcycle',
    'car': 'car',
    'bus': 'bus',
    'truck': 'truck',
    'stop sign': 'stop sign',
    'traffic light': 'traffic light',
    'dog': 'dog',
    'cat': 'cat',
    'bench': 'bench',
    'fire hydrant': 'fire hydrant',
    'parking meter': 'parking meter',
    'backpack': 'backpack',
    'handbag': 'handbag',
    'suitcase': 'suitcase',
    'umbrella': 'umbrella',
  },
};

const Map<AppLanguage, Map<String, String>> _dirs = {
  AppLanguage.ru: {
    'forward': 'впереди',
    '9': 'на 9 часов',
    '10': 'на 10 часов',
    '11': 'на 11 часов',
    '1': 'на 1 час',
    '2': 'на 2 часа',
    '3': 'на 3 часа',
  },
  AppLanguage.kk: {
    'forward': 'алда',
    '9': '9 сағатта',
    '10': '10 сағатта',
    '11': '11 сағатта',
    '1': '1 сағатта',
    '2': '2 сағатта',
    '3': '3 сағатта',
  },
  AppLanguage.en: {
    'forward': 'ahead',
    '9': 'at 9 o\'clock',
    '10': 'at 10 o\'clock',
    '11': 'at 11 o\'clock',
    '1': 'at 1 o\'clock',
    '2': 'at 2 o\'clock',
    '3': 'at 3 o\'clock',
  },
};
