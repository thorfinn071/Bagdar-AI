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

  static String get(String key) =>
      _ui[current]?[key] ?? _ui[AppLanguage.ru]?[key] ?? key;

  
  
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
    'sign': 'Знак',
    'path_clear': 'Путь свободен.',
    'path_clear_cane': 'Свободно.',
    'path_clear_label': 'Путь свободен',
    'no_change': 'Обстановка не изменилась.',
    'nothing_seen': 'Ничего не вижу.',
    'nothing_here': 'Ничего нет',
    'left': 'слева',
    'right': 'справа',
    'forward_loc': 'впереди',
    'closest': 'Ближайший объект в',
    'meters': 'метрах',
    'approx_meters': 'м',
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
    'phone_tilted_sideways': 'Телефон наклонён вбок. Результаты менее точны.',

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

    'status_no_obstacle': 'Препятствий нет',
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

    'camera_unavailable': 'Камера недоступна.',
    'camera_not_found': 'Камера не найдена',
    'camera_started': 'Камера запущена',
    'system_ready': 'Система готова',
    'mode_changed': 'Режим',

    'calib_aim': 'Наведите камеру на человека для калибровки.',
    'calib_saved': 'Калибровка сохранена.',
    'calib_recommend':
        'Для точного определения расстояния рекомендуем калибровку в настройках.',

    'onb_welcome_tts':
        'Добро пожаловать в Bagdar. Выберите режим работы по умолчанию. '
        'Улица — предупреждения об объектах. '
        'Трость — частые тактильные сигналы. '
        'Сканирование — словесное описание окружения.',
    'onb_perm_tts':
        'Приложению нужен доступ к камере. '
        'Нажмите кнопку чтобы разрешить.',
    'onb_calib_tts':
        'Шаг калибровки камеры. '
        'Реальную калибровку можно выполнить позже в настройках приложения. '
        'Это улучшит точность определения расстояния примерно с сорока до десяти процентов.',
    'onb_ready_tts': 'Всё готово! Нажмите Начать.',
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

    'voice_listening': 'Слушаю...',
    'voice_not_available': 'Голосовые команды недоступны.',
    'voice_no_permission': 'Нет доступа к микрофону.',
    'voice_unknown': 'Команда не распознана.',
    'voice_hint': 'Удерживайте экран для голосовой команды.',
    'voice_commands_list':
        'Доступные команды: что вокруг, что слева, что справа, '
        'что впереди, читай, режим, черный экран.',

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
    'pitch_black_ui': 'Чёрный экран',
    'pitch_black_ui_desc':
        'Скрывает изображение камеры и весь интерфейс навигации.',
    'pitch_black_on': 'Чёрный экран включён.',
    'pitch_black_off': 'Чёрный экран выключен.',
    'audio_route_interrupted': 'Звук прерван. Проверьте наушники.',
    'audio_resumed': 'Звук восстановлен.',
    'tts_fallback_en':
        'Voice pack for your language is missing. Using English fallback.',
    'lifecycle_background':
        'Приложение свёрнуто. Верните его на экран, иначе сканирование не работает.',
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
    'camera_partial_blocked':
        'Камера частично перекрыта. Проверьте объектив.',
    'group_ahead': 'Впереди группа: ',

    'waypoint_saved': 'Место сохранено.',
    'waypoint_near': 'Вы рядом с',
    'waypoint_name_prompt': 'Название места',
    'waypoint_none': 'Нет сохранённых мест.',
    'waypoint_deleted': 'Место удалено.',

    'sos_sent': 'SOS отправлен.',
    'sos_sent_no_location':
        'SOS отправлен, но местоположение не удалось определить.',
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
    'sos_fall_countdown': 'SOS через',
    'sos_fall_seconds': 'секунд.',
    'sos_fall_cancelled': 'Отправка SOS отменена.',
    'sos_fall_sent': 'SOS отправлен после падения.',
    'sos_fall_cancel_hint':
        'Скажите стоп, отмена или я в порядке чтобы отменить.',
    'sos_112_fallback':
        'Контакт не задан. SOS будет отправлен на экстренный номер 112.',
    'sos_position_stale': 'Местоположение устарело на',
    'sos_position_unit_min': 'минут',
    'sos_sending': 'Отправляю SOS...',
    'sos_retry': 'Повторная отправка SOS.',
    'sos_delivered': 'SOS доставлен.',
    'camera_blocked': 'Камера заблокирована. Проверьте объектив.',
    'camera_frozen':
        'Внимание, изображение с камеры не меняется. Перезапустите приложение.',
    'camera_stalled': 'Камера замолчала. Остановитесь, проверьте приложение.',
    'camera_resumed': 'Камера снова работает.',
    'shake_warning':
        'Сильно трясет камеру. Замедлитесь или держите телефон ровнее.',
    'nav_maybe_off_route': 'Возможно, вы отклоняетесь от маршрута.',
    'pitch_too_high': 'Наклоните телефон ниже для сканирования земли.',
    'pitch_too_low': 'Поднимите телефон чуть выше.',
    'curtain_on': 'Экранная шторка включена. Экран скрыт.',
    'curtain_off': 'Экранная шторка выключена.',
    'help_summary':
        'Справка по управлению. '
        'Проведите вправо или влево для смены режима. '
        'Проведите вверх для включения или выключения экранной шторки. '
        'Удерживайте двумя пальцами одновременно для экстренной помощи SOS. '
        'Или скажите сос для SOS. '
        'Двойное касание для настроек. '
        'Удерживайте одним пальцем для голосовой команды.',
    'camera_screen_semantics':
        'Экран камеры. Проведите вправо или влево для смены режима. '
        'Проведите вверх для экранной шторки. Проведите вниз для справки.',
    'tl_green_warning': 'Пожалуйста, убедитесь в безопасности по звуку машин.',
    'tl_green_wait':
        'Светофор зелёный. Не начинайте движение без подтверждения, что транспорт остановился.',
    'tl_green_cars_near': 'Светофор зелёный, рядом транспорт. Подождите.',
    'tl_vehicle':
        'Автомобильный светофор. Не ориентируйтесь по нему, слушайте звуки перехода.',

    'depth_unavailable': 'Обнаружение глубины недоступно.',
    'depth_unavailable_street':
        'Внимание: безопасность по препятствиям на уровне пола отключена на этом устройстве.',
    'depth_degraded':
        'Качество глубины снизилось. Внимательнее к препятствиям.',
    'depth_recovered': 'Качество глубины восстановлено.',
    'depth_quality_low': 'Качество глубины низкое. Перехожу на MiDaS.',

    'camera_perm_title': 'Нет доступа к камере',
    'camera_perm_body':
        'Камера необходима для работы Bagdar.\n'
        'Откройте Настройки и разрешите доступ к камере.',
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
  },

  AppLanguage.kk: {
    'stop': 'Стоп',
    'close': 'жақын',
    'approaching': 'жақындап келеді',
    'transport_approaching': 'Көлік жақындап келеді',
    'object_approaching': 'Нысан жақындап келеді',
    'sign': 'Белгі',
    'path_clear': 'Жол бос.',
    'path_clear_cane': 'Бос.',
    'path_clear_label': 'Жол бос',
    'no_change': 'Жағдай өзгерген жоқ.',
    'nothing_seen': 'Ештеңе көрінбейді.',
    'nothing_here': 'Ештеңе жоқ',
    'left': 'солда',
    'right': 'оңда',
    'forward_loc': 'алда',
    'closest': 'Жақын нысан',
    'meters': 'метрде',
    'approx_meters': 'м',
    'hazard_dead_zone': 'Аяқ маңында қауіп',
    'hazard_step_down': 'Төмен баспалдақ',
    'hazard_step_up': 'Жоғары баспалдақ',
    'hazard_pothole': 'Шұңқыр',
    'hazard_curb': 'Бордюр',
    'hazard_stairs_down': 'Төмен баспалдақ. Тоқтаңыз.',
    'hazard_overhead': 'Кеуде деңгейінде кедергі. Тоқтаңыз.',
    'hazard_unknown': 'Кедергі',
    'hazard_glass_door': 'Алда шыны есік болуы мүмкін. Сақ болыңыз.',
    'hazard_slippery': 'Абайлаңыз, тайғанақ болуы мүмкін.',
    'hazard_warning': 'Мүмкін кедергі —',
    'phone_tilted_sideways': 'Телефон бүйірге еңкейген. Нәтижелер дәлсіз.',

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

    'status_no_obstacle': 'Кедергі жоқ',
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

    'camera_unavailable': 'Камера қолжетімсіз.',
    'camera_not_found': 'Камера табылмады',
    'camera_started': 'Камера қосылды',
    'system_ready': 'Жүйе дайын',
    'mode_changed': 'Режим',

    'calib_aim': 'Калибрлеу үшін камераны адамға бағыттаңыз.',
    'calib_saved': 'Калибрлеу сақталды.',
    'calib_recommend':
        'Дәл қашықтықты анықтау үшін баптауларда калибрлеуді ұсынамыз.',

    'onb_welcome_tts':
        'Bagdar-қа қош келдіңіз. Әдепкі режимді таңдаңыз. '
        'Көше — нысандар туралы ескертулер. '
        'Таяқ — жиі дірілдік сигналдар. '
        'Сканерлеу — қоршаған ортаның сипаттамасы.',
    'onb_perm_tts':
        'Қосымшаға камераға рұқсат қажет. '
        'Рұқсат беру үшін түймені басыңыз.',
    'onb_calib_tts':
        'Калибрлеу қадамы. '
        'Нақты калибрлеуді кейін баптауларда орындауға болады. '
        'Бұл қашықтық дәлдігін қырық пайыздан он пайызға дейін жақсартады.',
    'onb_ready_tts': 'Бәрі дайын! Бастау түймесін басыңыз.',
    'onb_calib_saved_tts':
        'Тамаша! Калибрлеу сақталды. Жалғастыру түймесін басыңыз.',
    'onb_calib_skip_tts':
        'Калибрлеу өткізілді. Оны кейін баптауларда орындай аласыз.',
    'onb_welcome_title': 'Bagdar-қа\nқош келдіңіз',
    'onb_welcome_sub':
        'Әдепкі режимді таңдаңыз.\nОны кез келген уақытта өзгертуге болады.',
    'onb_perm_title': 'Рұқсат қажет',
    'onb_perm_sub': 'Тек камера міндетті.\nҚалғандары — қалауыңыз бойынша.',
    'onb_calib_title': 'Қашықтық дәлдігі',
    'onb_calib_sub': 'Калибрлеусіз қате ~40%.\nКейін — ~10%. 10 секунд кетеді.',
    'onb_calib_app_note':
        'Калибрлеуді іске қосқаннан кейін Баптауларда орындауға болады.',
    'onb_ready_title': 'Бәрі дайын!',
    'onb_ready_sub': 'Bagdar баптанды. Қосымша мүмкіндіктері:',
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
    'onb_feat_scan': '«Айналада не бар?» түймесі — сахнаның сипаттамасы',
    'onb_feat_mode': 'Режим белгішесі — ауыстыру Көше / Таяқ / Скан',
    'onb_feat_settings': 'Баптаулар — калибрлеу, GPU, Debug HUD',
    'onb_lang_title': 'Тілді таңдаңыз',
    'onb_lang_sub': 'Тілді баптауларда өзгертуге болады',

    'mode_street': 'Көше',
    'mode_cane': 'Таяқ',
    'mode_scan': 'Сканерлеу',
    'mode_street_desc': 'Көліктер, адамдар, кедергілер — толық ескерту стегі',
    'mode_cane_desc': 'Максималды жиі діріл, ең аз сөз',
    'mode_scan_desc': 'Әр 4 секунд сайын қоршаған ортаның сипаттамасы',

    'perm_camera': 'Камера',
    'perm_camera_reason': 'Қосымшаның негізгі функциясы',
    'perm_camera_required': 'Міндетті',
    'perm_mic': 'Микрофон',
    'perm_mic_reason': 'Дауыстық командалар (болашақ функция)',
    'perm_location': 'Геолокация',
    'perm_location_reason': 'SOS режимі — жақындарыңызға орынды жіберу',
    'perm_optional': 'Кейін',

    'settings': 'Баптаулар',
    'cancel': 'Болдырмау',
    'save': 'Дайын',
    'ok': 'ОК',

    'voice_listening': 'Тыңдап жатырмын...',
    'voice_not_available': 'Дауыстық командалар қолжетімсіз.',
    'voice_no_permission': 'Микрофонға рұқсат жоқ.',
    'voice_unknown': 'Команда танылмады.',
    'voice_hint': 'Дауыстық команда үшін экранды ұстап тұрыңыз.',
    'voice_commands_list':
        'Қол жетімді командалар: айналада не бар, солда, оңда, '
        'алда, оқы, режим, қара экран.',

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
    'pitch_black_ui': 'Қара экран',
    'pitch_black_ui_desc':
        'Камера көрінісін және навигация интерфейсін жасырады.',
    'pitch_black_on': 'Қара экран қосылды.',
    'pitch_black_off': 'Қара экран өшірілді.',
    'audio_route_interrupted': 'Дыбыс үзілді. Құлаққапты тексеріңіз.',
    'audio_resumed': 'Дыбыс қалпына келді.',
    'tts_fallback_en':
        'Voice pack for your language is missing. Using English fallback.',
    'lifecycle_background':
        'Қосымша жиналды. Сканерлеу жұмыс істемейді, экранға қайтарыңыз.',
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
    'camera_partial_blocked':
        'Камера ішінара жабық. Линзаны тексеріңіз.',
    'group_ahead': 'Алда топ: ',

    'waypoint_saved': 'Орын сақталды.',
    'waypoint_near': 'Сіз жақынсыз',
    'waypoint_name_prompt': 'Орын атауы',
    'waypoint_none': 'Сақталған орындар жоқ.',
    'waypoint_deleted': 'Орын жойылды.',

    'sos_sent': 'SOS жіберілді.',
    'sos_sent_no_location':
        'SOS жіберілді, бірақ орналасуды анықтау мүмкін болмады.',
    'sos_launch_failed': 'SMS қолданбасын ашу мүмкін болмады.',
    'sos_error': 'SOS жіберу мүмкін болмады.',
    'sos_fall_detected':
        'Құлау анықталды. SOS 15 секундтан кейін жіберіледі. Болдырмау үшін экранды басыңыз.',
    'sos_fall_countdown': 'SOS',
    'sos_fall_seconds': 'секундтан кейін.',
    'sos_fall_cancelled': 'SOS жіберу болдырылмады.',
    'sos_fall_sent': 'Құлаудан кейін SOS жіберілді.',
    'sos_fall_cancel_hint':
        'Болдырмау үшін тоқта, болдырма немесе мен жақсы деп айтыңыз.',
    'sos_112_fallback': 'Байланыс нөмірі жоқ. SOS 112 нөміріне жіберіледі.',
    'sos_position_stale': 'Орналасу ескі, жасы',
    'sos_position_unit_min': 'минут',
    'sos_sending': 'SOS жіберіп жатырмын...',
    'sos_retry': 'SOS қайта жіберу.',
    'sos_delivered': 'SOS жеткізілді.',
    'camera_blocked': 'Камера бұғатталған. Объективті тексеріңіз.',
    'camera_frozen':
        'Назар аударыңыз, камера кескіні өзгермейді. Қолданбаны қайта іске қосыңыз.',
    'camera_stalled': 'Камера тоқтады. Тоқтаңыз, қолданбаны тексеріңіз.',
    'camera_resumed': 'Камера қайта жұмыс істеп тұр.',
    'shake_warning':
        'Камера қатты дірілдейді. Бәсеңдеңіз немесе телефонды тегіс ұстаңыз.',
    'nav_maybe_off_route': 'Маршруттан ауытқып жатқан шығарсыз.',
    'pitch_too_high': 'Жерді сканерлеу үшін телефонды төмен еңкейтіңіз.',
    'pitch_too_low': 'Телефонды сәл жоғары көтеріңіз.',
    'curtain_on': 'Экран пердесі қосулы. Экран жасырын.',
    'curtain_off': 'Экран пердесі өшірулі.',
    'help_summary':
        'Басқару бойынша анықтама. '
        'Режимді ауыстыру үшін оңға немесе солға сырғытыңыз. '
        'Экран пердесін қосу немесе өшіру үшін жоғары сырғытыңыз. '
        'SOS шұғыл көмегі үшін екі саусақпен қатар басып тұрыңыз. '
        'Немесе сос деп айтыңыз. '
        'Баптаулар үшін екі рет түртіңіз. '
        'Дауыстық команда үшін экранды бір саусақпен басып тұрыңыз.',
    'camera_screen_semantics':
        'Камера экраны. Режимді ауыстыру үшін оңға немесе солға сырғытыңыз. '
        'Экран пердесі үшін жоғары сырғытыңыз. Анықтама үшін төмен сырғытыңыз.',
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
    'depth_degraded':
        'Тереңдік сапасы төмендеді. Кедергілерге көбірек назар аударыңыз.',
    'depth_recovered': 'Тереңдік сапасы қалпына келді.',
    'depth_quality_low': 'Тереңдік сапасы төмен. MiDaS-ке ауысып жатырмын.',

    'camera_perm_title': 'Камераға рұқсат жоқ',
    'camera_perm_body':
        'Bagdar жұмысы үшін камера қажет.\n'
        'Баптауларды ашып, камераға рұқсат беріңіз.',
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

    'tts_lang_title': 'Дауыс табылмады',
    'tts_lang_body':
        'Таңдалған тіл үшін дауыстық пакет орнатылмаған. '
        'Баптаулар → Арнайы мүмкіндіктер → '
        'Сөйлеу синтезі бөліміне өтіп, тілдің дауысын орнатыңыз.',
    'tts_lang_open': 'Түсінікті',
  },
  AppLanguage.en: {
    'stop': 'Stop',
    'close': 'close',
    'approaching': 'approaching',
    'transport_approaching': 'Transport approaching',
    'object_approaching': 'Object approaching',
    'sign': 'Sign',
    'path_clear': 'Path clear.',
    'path_clear_cane': 'Clear.',
    'path_clear_label': 'Path clear',
    'no_change': 'No changes.',
    'nothing_seen': 'I see nothing.',
    'nothing_here': 'Nothing here',
    'left': 'left',
    'right': 'right',
    'forward_loc': 'forward',
    'closest': 'Closest object at',
    'meters': 'meters',
    'approx_meters': 'm',
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
    'phone_tilted_sideways':
        'Phone tilted sideways. Results are less accurate.',

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

    'status_no_obstacle': 'No obstacles',
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

    'camera_unavailable': 'Camera unavailable.',
    'camera_not_found': 'Camera not found',
    'camera_started': 'Camera started',
    'system_ready': 'System ready',
    'mode_changed': 'Mode',

    'calib_aim': 'Point the camera at a person for calibration.',
    'calib_saved': 'Calibration saved.',
    'calib_recommend':
        'For accurate distance detection, we recommend calibration in Settings.',

    'onb_welcome_tts':
        'Welcome to Bagdar. Choose your default mode. '
        'Street — object warnings. '
        'Cane — frequent haptic feedback. '
        'Scan — verbal description of surroundings.',
    'onb_perm_tts':
        'The app needs camera access. '
        'Tap the button to allow.',
    'onb_calib_tts':
        'Camera calibration step. '
        'You can perform the actual calibration later in settings. '
        'This improves distance accuracy from forty to ten percent.',
    'onb_ready_tts': 'All set! Tap Start.',
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
    'cancel': 'Cancel',
    'save': 'Done',
    'ok': 'OK',

    'voice_listening': 'Listening...',
    'voice_not_available': 'Voice commands not available.',
    'voice_no_permission': 'No microphone access.',
    'voice_unknown': 'Command not recognized.',
    'voice_hint': 'Hold screen for voice command.',
    'voice_commands_list':
        'Available commands: what is around, what is left, what is right, '
        'what is ahead, read, mode, pitch black.',

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
    'pitch_black_ui': 'Pitch Black',
    'pitch_black_ui_desc': 'Hides camera preview and whole navigation ui.',
    'pitch_black_on': 'Pitch black mode enabled.',
    'pitch_black_off': 'Pitch black mode disabled.',
    'audio_route_interrupted': 'Audio interrupted. Check your headphones.',
    'audio_resumed': 'Audio resumed.',
    'tts_fallback_en':
        'Voice pack for your language is missing. Using English fallback.',
    'lifecycle_background':
        'App hidden. Bring it to foreground, otherwise scanning stops.',
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

    'waypoint_saved': 'Location saved.',
    'waypoint_near': 'You are near',
    'waypoint_name_prompt': 'Location title',
    'waypoint_none': 'No saved locations.',
    'waypoint_deleted': 'Location deleted.',

    'sos_sent': 'SOS sent.',
    'sos_sent_no_location': 'SOS sent, but location could not be determined.',
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
    'sos_fall_countdown': 'SOS in',
    'sos_fall_seconds': 'seconds.',
    'sos_fall_cancelled': 'SOS cancelled.',
    'sos_fall_sent': 'SOS sent after fall.',
    'sos_fall_cancel_hint': 'Say stop, cancel, or I am okay to cancel.',
    'sos_112_fallback':
        'No contact specified. SOS will be sent to emergency 112.',
    'sos_position_stale': 'Location is stale by',
    'sos_position_unit_min': 'minutes',
    'sos_sending': 'Sending SOS...',
    'sos_retry': 'Retrying SOS.',
    'sos_delivered': 'SOS delivered.',
    'camera_blocked': 'Camera blocked. Check the lens.',
    'camera_frozen': 'Warning, camera image is frozen. Restart app.',
    'camera_stalled': 'Camera stalled. Stop and check the app.',
    'camera_resumed': 'Camera functioning again.',
    'shake_warning': 'Camera shaking heavily. Slow down or keep phone steady.',
    'nav_maybe_off_route': 'You might be off route.',
    'pitch_too_high': 'Tilt phone downwards to scan the floor.',
    'pitch_too_low': 'Tilt phone slightly up.',
    'curtain_on': 'Screen curtain on. Screen hidden.',
    'curtain_off': 'Screen curtain off.',
    'help_summary':
        'Controls help. '
        'Swipe left or right to switch modes. '
        'Swipe up to toggle screen curtain. '
        'Hold with two fingers for SOS. '
        'Or say sos. '
        'Double tap for settings. '
        'Hold with one finger for voice commands.',
    'camera_screen_semantics':
        'Camera screen. Swipe left or right to switch modes. '
        'Swipe up for screen curtain. Swipe down for help.',
    'tl_green_warning': 'Please rely on traffic sounds to ensure safety.',
    'tl_green_wait':
        'Light is green. Do not cross until traffic stops completely.',
    'tl_green_cars_near': 'Light is green, but cars are near. Wait.',
    'tl_vehicle':
        'Vehicle traffic light. Do not rely on it, listen to crossing sounds.',

    'depth_unavailable': 'Depth detection unavailable.',
    'depth_unavailable_street':
        'Warning: floor-level obstacle safety is disabled.',
    'depth_degraded': 'Depth quality degraded. Pay extra attention.',
    'depth_recovered': 'Depth quality recovered.',
    'depth_quality_low': 'Depth quality low. Switching to MiDaS.',

    'camera_perm_title': 'No camera access',
    'camera_perm_body':
        'Camera is required for Bagdar to work.\n'
        'Please go to Settings and allow camera.',
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
    'traffic light': 'жарық шам',
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
