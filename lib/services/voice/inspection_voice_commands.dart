import '../../models/strings.dart';

enum InspectionVoiceCommand {
  status,
  help,
  repeat,
  slower,
  faster,
  settings,
  finish,
  micOff,
}

/// Exact, language-specific commands. No substring, navigation or SOS path.
InspectionVoiceCommand? parseInspectionVoice(
  String text,
  AppLanguage language,
) {
  final normalized = text
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[.!?,;:]+$'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  return (switch (language) {
    AppLanguage.ru => const {
      'статус': InspectionVoiceCommand.status,
      'справка': InspectionVoiceCommand.help,
      'что можно сказать': InspectionVoiceCommand.help,
      'повтори': InspectionVoiceCommand.repeat,
      'медленнее': InspectionVoiceCommand.slower,
      'говори медленнее': InspectionVoiceCommand.slower,
      'быстрее': InspectionVoiceCommand.faster,
      'говори быстрее': InspectionVoiceCommand.faster,
      'настройки': InspectionVoiceCommand.settings,
      'закончить осмотр': InspectionVoiceCommand.finish,
      'выключить микрофон': InspectionVoiceCommand.micOff,
    },
    AppLanguage.kk => const {
      'күйі': InspectionVoiceCommand.status,
      'анықтама': InspectionVoiceCommand.help,
      'не айтуға болады': InspectionVoiceCommand.help,
      'қайтала': InspectionVoiceCommand.repeat,
      'баяуырақ': InspectionVoiceCommand.slower,
      'жылдамырақ': InspectionVoiceCommand.faster,
      'баптаулар': InspectionVoiceCommand.settings,
      'тексеруді аяқтау': InspectionVoiceCommand.finish,
      'микрофонды өшір': InspectionVoiceCommand.micOff,
    },
    AppLanguage.en => const {
      'status': InspectionVoiceCommand.status,
      'help': InspectionVoiceCommand.help,
      'what can i say': InspectionVoiceCommand.help,
      'repeat': InspectionVoiceCommand.repeat,
      'slower': InspectionVoiceCommand.slower,
      'speak slower': InspectionVoiceCommand.slower,
      'faster': InspectionVoiceCommand.faster,
      'speak faster': InspectionVoiceCommand.faster,
      'settings': InspectionVoiceCommand.settings,
      'finish inspection': InspectionVoiceCommand.finish,
      'turn off microphone': InspectionVoiceCommand.micOff,
    },
  })[normalized];
}

enum InspectionVoiceCopy {
  button,
  cancel,
  privacy,
  prompt,
  listening,
  help,
  off,
  unavailable,
  speechUnavailable,
  actionUnavailable,
  denied,
  noSpeech,
  unknown,
  interrupted,
  shutdownFailed,
  settings,
  finish,
  slower,
  faster,
}

String inspectionVoiceText(InspectionVoiceCopy copy, AppLanguage language) {
  const texts = {
    InspectionVoiceCopy.actionUnavailable: [
      'Команда недоступна в текущем состоянии. Микрофон выключен.',
      'Бұл күйде пәрмен қолжетімсіз. Микрофон өшірілді.',
      'This command is unavailable in the current state. Microphone off.',
    ],
    InspectionVoiceCopy.speechUnavailable: [
      'Озвучка не подтверждена. Голосовой ввод не начат. Используйте доступные элементы экрана.',
      'Дыбыстау расталмады. Дауыстық енгізу басталмады. Экран элементтерін қолданыңыз.',
      'Speech playback not confirmed. Voice input has not started. Use the accessible screen controls.',
    ],
    InspectionVoiceCopy.button: [
      'Голосовая команда',
      'Дауыстық пәрмен',
      'Voice command',
    ],
    InspectionVoiceCopy.cancel: [
      'Выключить микрофон',
      'Микрофонды өшір',
      'Turn off microphone',
    ],
    InspectionVoiceCopy.privacy: [
      'Один короткий ответ. Только локальное распознавание Android. Записи и расшифровки не сохраняются. Ожидания слова «Багдар» пока нет.',
      'Бір қысқа жауап. Тек Android құрылғысында тану. Жазбалар мен мәтін сақталмайды. «Бағдар» сөзін күту әзірше жоқ.',
      'One short answer. Android on-device recognition only. Audio and transcripts are not saved. Wake word is not available yet.',
    ],
    InspectionVoiceCopy.prompt: [
      'После сигнала скажите: статус, справка или настройки.',
      'Белгіден кейін айтыңыз: күйі, анықтама немесе баптаулар.',
      'After the tone, say: status, help or settings.',
    ],
    InspectionVoiceCopy.listening: [
      'Слушаю одну команду',
      'Бір пәрменді тыңдап тұрмын',
      'Listening for one command',
    ],
    InspectionVoiceCopy.help: [
      'Команды: статус, справка, повтори, медленнее, быстрее, настройки, закончить осмотр, выключить микрофон. Для следующей команды снова включите голосовой ввод.',
      'Пәрмендер: күйі, анықтама, қайтала, баяуырақ, жылдамырақ, баптаулар, тексеруді аяқтау, микрофонды өшір. Келесі пәрмен үшін дауыстық енгізуді қайта қосыңыз.',
      'Commands: status, help, repeat, slower, faster, settings, finish inspection, turn off microphone. Activate voice input again for another command.',
    ],
    InspectionVoiceCopy.off: [
      'Микрофон выключен. Для следующей команды используйте элемент «Голосовая команда» или средство управления ОС.',
      'Микрофон өшірілді. Келесі пәрмен үшін «Дауыстық пәрмен» элементін немесе жүйелік басқаруды қолданыңыз.',
      'Microphone off. For another command, use Voice command or a system control.',
    ],
    InspectionVoiceCopy.unavailable: [
      'Локальное распознавание выбранного языка недоступно. Используйте доступные элементы экрана.',
      'Таңдалған тілде жергілікті тану қолжетімсіз. Экран элементтерін қолданыңыз.',
      'On-device recognition for this language is unavailable. Use the accessible screen controls.',
    ],
    InspectionVoiceCopy.denied: [
      'Нет разрешения на микрофон. Повторный запрос возможен только через элемент голосового ввода.',
      'Микрофонға рұқсат жоқ. Қайта сұрау үшін дауыстық енгізу элементін қолданыңыз.',
      'Microphone permission denied. Use Voice command to request it again.',
    ],
    InspectionVoiceCopy.noSpeech: [
      'Ответ не получен. Микрофон выключен.',
      'Жауап алынбады. Микрофон өшірілді.',
      'No answer received. Microphone off.',
    ],
    InspectionVoiceCopy.unknown: [
      'Команда не подтверждена. Действие не выполнено. Микрофон выключен.',
      'Пәрмен расталмады. Әрекет орындалмады. Микрофон өшірілді.',
      'Command not confirmed. No action taken. Microphone off.',
    ],
    InspectionVoiceCopy.interrupted: [
      'Голосовой сеанс прерван. Включите его заново после предупреждения или возврата в осмотр.',
      'Дауыстық сеанс үзілді. Ескертуден кейін немесе тексеруге оралғанда қайта қосыңыз.',
      'Voice session interrupted. Activate again after the alert or return to inspection.',
    ],
    InspectionVoiceCopy.shutdownFailed: [
      'Остановка микрофона не подтверждена. Закройте Bagdar средствами ОС.',
      'Микрофонның тоқтауы расталмады. Bagdar қолданбасын жүйе арқылы жабыңыз.',
      'Microphone shutdown not confirmed. Close Bagdar using system controls.',
    ],
    InspectionVoiceCopy.settings: [
      'Открываю голосовые настройки. Далее выберите группу.',
      'Дауыстық баптаулар ашылады. Содан кейін топты таңдаңыз.',
      'Opening voice settings. Choose a group next.',
    ],
    InspectionVoiceCopy.finish: [
      'Заканчиваю неподвижный осмотр.',
      'Қозғалмай тексеру аяқталады.',
      'Finishing stationary inspection.',
    ],
    InspectionVoiceCopy.slower: [
      'Речь медленнее. Голосовой сеанс завершён.',
      'Сөйлеу баяуырақ. Дауыстық сеанс аяқталды.',
      'Speech slower. Voice session ended.',
    ],
    InspectionVoiceCopy.faster: [
      'Речь быстрее. Голосовой сеанс завершён.',
      'Сөйлеу жылдамырақ. Дауыстық сеанс аяқталды.',
      'Speech faster. Voice session ended.',
    ],
  };
  return texts[copy]![language.index];
}
