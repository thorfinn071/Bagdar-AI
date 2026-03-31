enum AppLanguage { ru, kk }

typedef S = AppStrings;

class AppStrings {
  AppStrings._();

  static AppLanguage current = AppLanguage.ru;

  static String get ttsLang =>
      current == AppLanguage.kk ? 'kk-KZ' : 'ru-RU';

  static String get(String key) =>
      _ui[current]?[key] ?? _ui[AppLanguage.ru]?[key] ?? key;

  static String label(String yoloClass) =>
      _labels[current]?[yoloClass] ??
      _labels[AppLanguage.ru]?[yoloClass] ??
      yoloClass;

  static String dir(String key) =>
      _dirs[current]?[key] ?? _dirs[AppLanguage.ru]?[key] ?? key;

  static void setLanguage(AppLanguage lang) => current = lang;
}

const Map<AppLanguage, Map<String, String>> _ui = {
  AppLanguage.ru: {
    'stop':                   'Стоп',
    'close':                  'близко',
    'approaching':            'приближается',
    'transport_approaching':  'Транспорт приближается',
    'sign':                   'Знак',
    'path_clear':             'Путь свободен.',
    'path_clear_cane':        'Свободно.',
    'path_clear_label':       'Путь свободен',
    'no_change':              'Обстановка не изменилась.',
    'nothing_seen':           'Ничего не вижу.',
    'nothing_here':           'Ничего нет',
    'left':                   'слева',
    'right':                  'справа',
    'forward_loc':            'впереди',
    'closest':                'Ближайший объект в',
    'meters':                 'метрах',
    'approx_meters':          'м',
    'hazard_step_down':     'Ступенька вниз',
    'hazard_pothole':       'Яма',
    'hazard_curb':          'Бордюр',
    'hazard_unknown':       'Препятствие',
    'hazard_warning':       'Возможное препятствие —',

    'deviate':                'Отклонитесь',
    'passage':                'Проход',
    'maneuver_ok':            'Хорошо.',
    'nav_left':               'влево',
    'nav_right':              'вправо',
    'nav_slight_left':        'немного влево',
    'nav_slight_right':       'немного вправо',
    'straight':               'прямо',

    'corridor_blocked':       'Проход заблокирован.',
    'narrow':                 'Узко.',

    'status_no_obstacle':     'Препятствий нет',
    'status_scanning':        'Сканирование...',
    'status_waiting':         'ожидание',
    'dist_safe':              'безопасно',
    'dist_attention':         'внимание',
    'dist_stop':              'стоп',
    'lbl_object':             'Объект',
    'lbl_status':             'Статус',
    'lbl_total_objects':      'Всего объектов',

    'scan_left':              'Слева',
    'scan_forward':           'Впереди',
    'scan_right':             'Справа',
    'scan_see':               'Вижу',

    'ocr_reading':            'Читаю...',
    'ocr_not_found':          'Текст не найден.',
    'ocr_camera_not_ready':   'Камера не готова.',

    'camera_unavailable':     'Камера недоступна.',
    'camera_not_found':       'Камера не найдена',
    'camera_started':         'Камера запущена',
    'system_ready':           'Система готова',
    'mode_changed':           'Режим',

    'calib_aim':              'Наведите камеру на человека для калибровки.',
    'calib_saved':            'Калибровка сохранена.',
    'calib_recommend':
        'Для точного определения расстояния рекомендуем калибровку в настройках.',

    'onb_welcome_tts':
        'Добро пожаловать в VisionGuide. Выберите режим работы по умолчанию. '
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
    'onb_ready_tts':          'Всё готово! Нажмите Начать.',
    'onb_calib_saved_tts':    'Отлично! Калибровка сохранена. Нажмите Продолжить.',
    'onb_calib_skip_tts':
        'Калибровка пропущена. Вы сможете выполнить её позже в настройках.',
    'onb_welcome_title':      'Добро пожаловать\nв VisionGuide',
    'onb_welcome_sub':
        'Выберите режим по умолчанию.\nЕго можно изменить в любой момент.',
    'onb_perm_title':         'Нужен доступ',
    'onb_perm_sub':           'Только камера обязательна.\nОстальное — по желанию.',
    'onb_calib_title':        'Точность расстояния',
    'onb_calib_sub':
        'Без калибровки погрешность ~40%.\nПосле — ~10%. Займёт 10 секунд.',
    'onb_calib_app_note':
        'Калибровку можно выполнить в Настройках после запуска приложения.',
    'onb_ready_title':        'Всё готово!',
    'onb_ready_sub':          'VisionGuide настроен. Вот что умеет приложение:',
    'onb_btn_continue':       'Продолжить',
    'onb_btn_allow_camera':   'Разрешить камеру',
    'onb_btn_skip':           'Пропустить остальное',
    'onb_btn_calibrate':      'Я стою в 2 метрах — откалибровать',
    'onb_btn_skip_calib':     'Пропустить — настрою позже',
    'onb_btn_calib_later':    'Откалибрую в настройках',
    'onb_btn_start':          'Начать',
    'onb_btn_back_calib':     'Вернуться к калибровке',
    'onb_calib_done':         'Калибровка выполнена — точность улучшена!',
    'onb_calib_hint':         'Попросите кого-нибудь встать в 2 м от вас',
    'onb_check_alerts':       'Голосовые предупреждения об объектах',
    'onb_check_mode':         'выбран по умолчанию',
    'onb_check_calib':        'Калибровка камеры',
    'onb_check_calib_skip':   'Доступна в Настройках → Калибровка камеры',
    'onb_feat_scan':          'Кнопка «Что вокруг?» — описание сцены',
    'onb_feat_mode':          'Иконка режима — переключение Улица / Трость / Скан',
    'onb_feat_settings':      'Настройки — калибровка, GPU, Debug HUD',
    'onb_lang_title':         'Выберите язык',
    'onb_lang_sub':           'Язык можно изменить в настройках',

    'mode_street':            'Улица',
    'mode_cane':              'Трость',
    'mode_scan':              'Сканирование',
    'mode_street_desc':       'Машины, люди, препятствия — полный стек алертов',
    'mode_cane_desc':         'Максимально частая вибрация, минимум речи',
    'mode_scan_desc':         'Словесное описание окружения каждые 4 секунды',

    'perm_camera':            'Камера',
    'perm_camera_reason':     'Основная функция приложения',
    'perm_camera_required':   'Обязательно',
    'perm_mic':               'Микрофон',
    'perm_mic_reason':        'Голосовые команды (будущая функция)',
    'perm_location':          'Геолокация',
    'perm_location_reason':   'SOS-режим — отправить локацию близким',
    'perm_optional':          'Позже',

    'settings':               'Настройки',
    'cancel':                 'Отмена',
    'save':                   'Готово',
    'ok':                     'ОК',

    'voice_listening':        'Слушаю...',
    'voice_not_available':    'Голосовые команды недоступны.',
    'voice_no_permission':    'Нет доступа к микрофону.',
    'voice_unknown':          'Команда не распознана.',
    'voice_hint':             'Удерживайте экран для голосовой команды.',
    'voice_commands_list':
        'Доступные команды: что вокруг, что слева, что справа, '
        'что впереди, читай, режим.',

    'fg_notification_title': 'VisionGuide активен',
    'fg_notification_body':  'Навигация работает в фоне.',

    'battery_low':           'Низкий заряд — замедляю работу.',
    'battery_moderate':      'Заряд средний — экономлю энергию.',
    'battery_normal':        'Заряд в норме.',

    'night_mode_on':         'Ночной режим включён.',
    'night_mode_off':        'Ночной режим выключен.',

    'waypoint_saved':        'Место сохранено.',
    'waypoint_near':         'Вы рядом с',
    'waypoint_name_prompt':  'Название места',
    'waypoint_none':         'Нет сохранённых мест.',
    'waypoint_deleted':      'Место удалено.',

    'sos_sent':              'SOS отправлен.',
    'sos_no_contact':        'Контакт для SOS не задан. Настройте в настройках.',
    'sos_no_location':       'Не удалось определить местоположение.',
    'sos_no_gps':            'местоположение недоступно',
    'sos_settings':          'SOS контакт',
    'sos_message':           'Мне нужна помощь! Моё местоположение:',
    'sos_invalid_number':    'Некорректный номер телефона.',
    'sos_launch_failed':     'Не удалось открыть приложение для SMS.',

    'depth_unavailable':     'Обнаружение глубины недоступно.',
  },

  AppLanguage.kk: {
    'stop':                   'Стоп',
    'close':                  'жақын',
    'approaching':            'жақындап келеді',
    'transport_approaching':  'Көлік жақындап келеді',
    'sign':                   'Белгі',
    'path_clear':             'Жол бос.',
    'path_clear_cane':        'Бос.',
    'path_clear_label':       'Жол бос',
    'no_change':              'Жағдай өзгерген жоқ.',
    'nothing_seen':           'Ештеңе көрінбейді.',
    'nothing_here':           'Ештеңе жоқ',
    'left':                   'солда',
    'right':                  'оңда',
    'forward_loc':            'алда',
    'closest':                'Жақын нысан',
    'meters':                 'метрде',
    'approx_meters':          'м',
    'hazard_step_down':     'Төмен баспалдақ',
    'hazard_pothole':       'Шұңқыр',
    'hazard_curb':          'Бордюр',
    'hazard_unknown':       'Кедергі',
    'hazard_warning':       'Мүмкін кедергі —',

    'deviate':                'Ауытқыңыз',
    'passage':                'Өту',
    'maneuver_ok':            'Жақсы.',
    'nav_left':               'солға',
    'nav_right':              'оңға',
    'nav_slight_left':        'сәл солға',
    'nav_slight_right':       'сәл оңға',
    'straight':               'тура',

    'corridor_blocked':       'Жол бөгелген.',
    'narrow':                 'Тар.',

    'status_no_obstacle':     'Кедергі жоқ',
    'status_scanning':        'Сканерлеу...',
    'status_waiting':         'күту',
    'dist_safe':              'қауіпсіз',
    'dist_attention':         'назар',
    'dist_stop':              'тоқта',
    'lbl_object':             'Нысан',
    'lbl_status':             'Күй',
    'lbl_total_objects':      'Барлық нысандар',

    'scan_left':              'Солда',
    'scan_forward':           'Алда',
    'scan_right':             'Оңда',
    'scan_see':               'Көремін',

    'ocr_reading':            'Оқып жатырмын...',
    'ocr_not_found':          'Мәтін табылмады.',
    'ocr_camera_not_ready':   'Камера дайын емес.',

    'camera_unavailable':     'Камера қолжетімсіз.',
    'camera_not_found':       'Камера табылмады',
    'camera_started':         'Камера қосылды',
    'system_ready':           'Жүйе дайын',
    'mode_changed':           'Режим',

    'calib_aim':              'Калибрлеу үшін камераны адамға бағыттаңыз.',
    'calib_saved':            'Калибрлеу сақталды.',
    'calib_recommend':
        'Дәл қашықтықты анықтау үшін баптауларда калибрлеуді ұсынамыз.',

    'onb_welcome_tts':
        'VisionGuide-қа қош келдіңіз. Әдепкі режимді таңдаңыз. '
        'Көше — нысандар туралы ескертулер. '
        'Таяқ — жиі дірілдік сигналдар. '
        'Сканерлеу — қоршаған ортаның сөздік сипаттамасы.',
    'onb_perm_tts':
        'Қосымшаға камераға рұқсат қажет. '
        'Рұқсат беру үшін түймені басыңыз.',
    'onb_calib_tts':
        'Калибрлеу қадамы. '
        'Нақты калибрлеуді кейін баптауларда орындауға болады. '
        'Бұл қашықтық дәлдігін қырық пайыздан он пайызға дейін жақсартады.',
    'onb_ready_tts':          'Бәрі дайын! Бастау түймесін басыңыз.',
    'onb_calib_saved_tts':    'Тамаша! Калибрлеу сақталды. Жалғастыру түймесін басыңыз.',
    'onb_calib_skip_tts':
        'Калибрлеу өткізілді. Оны кейін баптауларда орындай аласыз.',
    'onb_welcome_title':      'VisionGuide-қа\nқош келдіңіз',
    'onb_welcome_sub':
        'Әдепкі режимді таңдаңыз.\nОны кез келген уақытта өзгертуге болады.',
    'onb_perm_title':         'Рұқсат қажет',
    'onb_perm_sub':           'Тек камера міндетті.\nҚалғандары — қалауыңыз бойынша.',
    'onb_calib_title':        'Қашықтық дәлдігі',
    'onb_calib_sub':
        'Калибрлеусіз қате ~40%.\nКейін — ~10%. 10 секунд кетеді.',
    'onb_calib_app_note':
        'Калибрлеуді іске қосқаннан кейін Баптауларда орындауға болады.',
    'onb_ready_title':        'Бәрі дайын!',
    'onb_ready_sub':          'VisionGuide баптанды. Қосымша мүмкіндіктері:',
    'onb_btn_continue':       'Жалғастыру',
    'onb_btn_allow_camera':   'Камераға рұқсат беру',
    'onb_btn_skip':           'Қалғанын өткізу',
    'onb_btn_calibrate':      'Мен 2 метрде тұрмын — калибрлеу',
    'onb_btn_skip_calib':     'Өткізу — кейін баптаймын',
    'onb_btn_calib_later':    'Баптауларда калибрлеймін',
    'onb_btn_start':          'Бастау',
    'onb_btn_back_calib':     'Калибрлеуге оралу',
    'onb_calib_done':         'Калибрлеу орындалды — дәлдік жақсарды!',
    'onb_calib_hint':         'Біреуден сізден 2 м қашықтықта тұруды сұраңыз',
    'onb_check_alerts':       'Нысандар туралы дауыстық ескертулер',
    'onb_check_mode':         'әдепкі ретінде таңдалды',
    'onb_check_calib':        'Камераны калибрлеу',
    'onb_check_calib_skip':   'Баптаулар → Камераны калибрлеу',
    'onb_feat_scan':          '«Айналада не бар?» түймесі — сахнаның сипаттамасы',
    'onb_feat_mode':          'Режим белгішесі — ауыстыру Көше / Таяқ / Скан',
    'onb_feat_settings':      'Баптаулар — калибрлеу, GPU, Debug HUD',
    'onb_lang_title':         'Тілді таңдаңыз',
    'onb_lang_sub':           'Тілді баптауларда өзгертуге болады',

    'mode_street':            'Көше',
    'mode_cane':              'Таяқ',
    'mode_scan':              'Сканерлеу',
    'mode_street_desc':       'Көліктер, адамдар, кедергілер — толық ескерту стегі',
    'mode_cane_desc':         'Максималды жиі діріл, ең аз сөз',
    'mode_scan_desc':         'Әр 4 секунд сайын қоршаған ортаның сипаттамасы',

    'perm_camera':            'Камера',
    'perm_camera_reason':     'Қосымшаның негізгі функциясы',
    'perm_camera_required':   'Міндетті',
    'perm_mic':               'Микрофон',
    'perm_mic_reason':        'Дауыстық командалар (болашақ функция)',
    'perm_location':          'Геолокация',
    'perm_location_reason':   'SOS режимі — жақындарыңызға орынды жіберу',
    'perm_optional':          'Кейін',

    'settings':               'Баптаулар',
    'cancel':                 'Болдырмау',
    'save':                   'Дайын',
    'ok':                     'ОК',

    'voice_listening':        'Тыңдап жатырмын...',
    'voice_not_available':    'Дауыстық командалар қолжетімсіз.',
    'voice_no_permission':    'Микрофонға рұқсат жоқ.',
    'voice_unknown':          'Команда танылмады.',
    'voice_hint':             'Дауыстық команда үшін экранды ұстап тұрыңыз.',
    'voice_commands_list':
        'Қол жетімді командалар: айналада не бар, солда, оңда, '
        'алда, оқы, режим.',

    'fg_notification_title': 'VisionGuide белсенді',
    'fg_notification_body':  'Навигация фонда жұмыс істеуде.',

    'battery_low':           'Заряд аз — жұмыс жылдамдығын бәсеңдетемін.',
    'battery_moderate':      'Заряд орташа — энергияны үнемдеймін.',
    'battery_normal':        'Заряд қалыпты.',

    'night_mode_on':         'Түнгі режим қосылды.',
    'night_mode_off':        'Түнгі режим өшірілді.',

    'waypoint_saved':        'Орын сақталды.',
    'waypoint_near':         'Сіз жақынсыз',
    'waypoint_name_prompt':  'Орын атауы',
    'waypoint_none':         'Сақталған орындар жоқ.',
    'waypoint_deleted':      'Орын жойылды.',

    'sos_sent':              'SOS жіберілді.',
    'sos_launch_failed':     'SMS қолданбасын ашу мүмкін болмады.',
    'sos_no_contact':        'SOS контактісі белгіленбеген. Баптауларда орнатыңыз.',
    'sos_no_location':       'Орналасуды анықтау мүмкін болмады.',
    'sos_no_gps':            'орналасу қолжетімсіз',
    'sos_settings':          'SOS контактісі',
    'sos_message':           'Маған көмек керек! Менің орналасуым:',
    'sos_invalid_number':    'Телефон нөмірі қате.',

    'depth_unavailable':     'Тереңдікті анықтау қолжетімсіз.',
  },
};

const Map<AppLanguage, Map<String, String>> _labels = {
  AppLanguage.ru: {
    'person':        'человек',
    'bicycle':       'велосипед',
    'motorcycle':    'мотоцикл',
    'car':           'машина',
    'bus':           'автобус',
    'truck':         'грузовик',
    'stop sign':     'знак стоп',
    'traffic light': 'светофор',
    'dog':           'собака',
    'cat':           'кошка',
    'bench':         'скамейка',
    'fire hydrant':  'гидрант',
    'parking meter': 'паркомат',
    'backpack':      'рюкзак',
    'handbag':       'сумка',
    'suitcase':      'чемодан',
    'umbrella':      'зонт',
  },
  AppLanguage.kk: {
    'person':        'адам',
    'bicycle':       'велосипед',
    'motorcycle':    'мотоцикл',
    'car':           'көлік',
    'bus':           'автобус',
    'truck':         'жүк көлігі',
    'stop sign':     'стоп белгісі',
    'traffic light': 'жарық шам',
    'dog':           'ит',
    'cat':           'мысық',
    'bench':         'орындық',
    'fire hydrant':  'өрт гидранты',
    'parking meter': 'паркомат',
    'backpack':      'рюкзак',
    'handbag':       'сөмке',
    'suitcase':      'чемодан',
    'umbrella':      'қолшатыр',
  },
};

const Map<AppLanguage, Map<String, String>> _dirs = {
  AppLanguage.ru: {
    'forward': 'впереди',
    '9':       'на 9 часов',
    '10':      'на 10 часов',
    '11':      'на 11 часов',
    '1':       'на 1 час',
    '2':       'на 2 часа',
    '3':       'на 3 часа',
  },
  AppLanguage.kk: {
    'forward': 'алда',
    '9':       '9 сағатта',
    '10':      '10 сағатта',
    '11':      '11 сағатта',
    '1':       '1 сағатта',
    '2':       '2 сағатта',
    '3':       '3 сағатта',
  },
};
