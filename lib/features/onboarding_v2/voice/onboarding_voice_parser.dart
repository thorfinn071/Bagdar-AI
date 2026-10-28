import '../../../models/strings.dart';

enum OnboardingVoiceIntent {
  russian,
  kazakh,
  english,
  voice,
  largeText,
  helper,
  handoff,
  next,
  back,
  repeat,
  help,
  slower,
  faster,
  acceptLimits,
  declineLimits,
  heard,
  notHeard,
  felt,
  notFelt,
  skipHaptic,
  stop,
  move,
  check,
  pause,
  resume,
  disable,
  unknown,
  requestCamera,
  cameraSettings,
  defer,
  runDevice,
  runAlignment,
  aligned,
  notAligned,
  standing,
  notStanding,
  runStationary,
  runSession,
  continueSetup,
  practiceAgain,
  inspect,
}

enum OnboardingVoiceQuestion {
  language,
  access,
  handoff,
  information,
  limits,
  ordinaryVoice,
  stopVoice,
  haptic,
  feedbackDone,
  practice,
  practiceDone,
  paused,
  camera,
  cameraGranted,
  device,
  deviceDone,
  standing,
  alignment,
  alignmentConfirm,
  alignmentDone,
  stationaryCheck,
  stationaryDone,
  sessionCheck,
  summaryBlocked,
  summaryReady,
}

class OnboardingVoiceParser {
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[.,!?;:«»"“”]'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static const _phrases = <OnboardingVoiceIntent, List<List<String>>>{
    OnboardingVoiceIntent.requestCamera: [
      ['запросить доступ', 'запросить доступ к камере'],
      ['камераға рұқсат сұрау'],
      ['request camera access'],
    ],
    OnboardingVoiceIntent.cameraSettings: [
      ['настройки приложения', 'открыть настройки приложения'],
      ['қолданба баптаулары'],
      ['app settings', 'open app settings'],
    ],
    OnboardingVoiceIntent.defer: [
      ['отложить'],
      ['кейінге қалдыру'],
      ['later'],
    ],
    OnboardingVoiceIntent.runDevice: [
      ['проверить устройство', 'повторить проверку'],
      ['құрылғыны тексеру'],
      ['check device'],
    ],
    OnboardingVoiceIntent.runAlignment: [
      ['проверить положение'],
      ['қалыпты тексеру'],
      ['check position'],
    ],
    OnboardingVoiceIntent.aligned: [
      ['положение подтверждаю'],
      ['қалыпты растаймын'],
      ['confirm position'],
    ],
    OnboardingVoiceIntent.notAligned: [
      ['положение не подтверждаю'],
      ['қалыпты растамаймын'],
      ['do not confirm position'],
    ],
    OnboardingVoiceIntent.standing: [
      ['стою на месте'],
      ['орнымда тұрмын'],
      ['i am standing still'],
    ],
    OnboardingVoiceIntent.notStanding: [
      ['не стою на месте', 'я иду'],
      ['орнымда тұрған жоқпын'],
      ['i am not standing still'],
    ],
    OnboardingVoiceIntent.runStationary: [
      ['проверить на месте'],
      ['орнымда тексеру'],
      ['check while stationary'],
    ],
    OnboardingVoiceIntent.runSession: [
      ['повторить проверку', 'проверить готовность'],
      ['дайындықты тексеру'],
      ['check readiness'],
    ],
    OnboardingVoiceIntent.continueSetup: [
      ['продолжить настройку'],
      ['баптауды жалғастыру'],
      ['continue setup'],
    ],
    OnboardingVoiceIntent.practiceAgain: [
      ['учебные примеры'],
      ['оқу мысалдары'],
      ['training examples'],
    ],
    OnboardingVoiceIntent.inspect: [
      ['начать осмотр'],
      ['шолуды бастау'],
      ['start inspection'],
    ],
    OnboardingVoiceIntent.russian: [
      ['русский', 'русский язык'],
      ['орысша', 'орыс тілі'],
      ['russian'],
    ],
    OnboardingVoiceIntent.kazakh: [
      ['казахский', 'казахский язык', 'қазақша'],
      ['қазақша', 'қазақ тілі'],
      ['kazakh'],
    ],
    OnboardingVoiceIntent.english: [
      ['английский', 'английский язык', 'english'],
      ['ағылшынша', 'ағылшын тілі'],
      ['english'],
    ],
    OnboardingVoiceIntent.voice: [
      ['сам', 'самостоятельно', 'голосом'],
      ['өзім', 'дауыспен'],
      ['myself', 'voice'],
    ],
    OnboardingVoiceIntent.largeText: [
      ['крупный текст'],
      ['ірі мәтін'],
      ['large text'],
    ],
    OnboardingVoiceIntent.helper: [
      ['с помощником'],
      ['көмекшімен'],
      ['with a helper'],
    ],
    OnboardingVoiceIntent.handoff: [
      ['управление у меня'],
      ['басқару менде'],
      ['i have control'],
    ],
    OnboardingVoiceIntent.next: [
      ['дальше', 'далее'],
      ['келесі', 'әрі қарай'],
      ['next'],
    ],
    OnboardingVoiceIntent.back: [
      ['назад'],
      ['артқа'],
      ['back'],
    ],
    OnboardingVoiceIntent.repeat: [
      ['повтори', 'еще раз'],
      ['қайтала', 'тағы бір рет'],
      ['repeat', 'again'],
    ],
    OnboardingVoiceIntent.help: [
      ['что можно сказать', 'где я в настройке', 'подсказка'],
      ['не айтуға болады', 'көмек'],
      ['what can i say', 'help'],
    ],
    OnboardingVoiceIntent.slower: [
      ['медленнее', 'говори медленнее'],
      ['баяуырақ'],
      ['slower', 'speak slower'],
    ],
    OnboardingVoiceIntent.faster: [
      ['быстрее', 'говори быстрее'],
      ['жылдамырақ'],
      ['faster', 'speak faster'],
    ],
    OnboardingVoiceIntent.acceptLimits: [
      ['понимаю ограничения'],
      ['шектеулерді түсінемін'],
      ['i understand the limits'],
    ],
    OnboardingVoiceIntent.declineLimits: [
      ['не понимаю', 'не согласен'],
      ['түсінбедім', 'келіспеймін'],
      ['i do not understand', 'i disagree'],
    ],
    OnboardingVoiceIntent.heard: [
      ['услышал', 'услышала'],
      ['естідім'],
      ['i heard it'],
    ],
    OnboardingVoiceIntent.notHeard: [
      ['не услышал', 'не услышала'],
      ['естімедім'],
      ['i did not hear it'],
    ],
    OnboardingVoiceIntent.felt: [
      ['почувствовал', 'почувствовала'],
      ['сездім'],
      ['i felt it'],
    ],
    OnboardingVoiceIntent.notFelt: [
      ['не почувствовал', 'не почувствовала'],
      ['сезбедім'],
      ['i did not feel it'],
    ],
    OnboardingVoiceIntent.skipHaptic: [
      ['без вибрации'],
      ['дірілсіз'],
      ['without vibration'],
    ],
    OnboardingVoiceIntent.stop: [
      ['остановлюсь', 'остановиться', 'стоп'],
      ['тоқтаймын', 'тоқтау', 'тоқта'],
      ['i will stop', 'stop'],
    ],
    OnboardingVoiceIntent.move: [
      ['пойду', 'продолжу идти'],
      ['жүремін'],
      ['i will walk', 'walk'],
    ],
    OnboardingVoiceIntent.check: [
      ['проверю', 'проверить'],
      ['тексеремін'],
      ['i will check', 'check'],
    ],
    OnboardingVoiceIntent.pause: [
      ['пауза'],
      ['үзіліс'],
      ['pause'],
    ],
    OnboardingVoiceIntent.resume: [
      ['продолжить', 'продолжим'],
      ['жалғастыру'],
      ['continue', 'resume'],
    ],
    OnboardingVoiceIntent.disable: [
      ['выключить микрофон', 'выключи микрофон'],
      ['микрофонды өшір'],
      ['turn off the microphone'],
    ],
  };

  static const _common = {
    OnboardingVoiceIntent.back,
    OnboardingVoiceIntent.repeat,
    OnboardingVoiceIntent.help,
    OnboardingVoiceIntent.slower,
    OnboardingVoiceIntent.faster,
    OnboardingVoiceIntent.pause,
    OnboardingVoiceIntent.disable,
  };

  static Set<OnboardingVoiceIntent> allowed(
    OnboardingVoiceQuestion question,
  ) => {
    ..._common,
    ...switch (question) {
      OnboardingVoiceQuestion.language => {
        OnboardingVoiceIntent.russian,
        OnboardingVoiceIntent.kazakh,
        OnboardingVoiceIntent.english,
        OnboardingVoiceIntent.next,
      },
      OnboardingVoiceQuestion.access => {
        OnboardingVoiceIntent.voice,
        OnboardingVoiceIntent.largeText,
        OnboardingVoiceIntent.helper,
      },
      OnboardingVoiceQuestion.handoff => {OnboardingVoiceIntent.handoff},
      OnboardingVoiceQuestion.information ||
      OnboardingVoiceQuestion.feedbackDone ||
      OnboardingVoiceQuestion.practiceDone => {OnboardingVoiceIntent.next},
      OnboardingVoiceQuestion.limits => {
        OnboardingVoiceIntent.acceptLimits,
        OnboardingVoiceIntent.declineLimits,
      },
      OnboardingVoiceQuestion.ordinaryVoice ||
      OnboardingVoiceQuestion.stopVoice => {
        OnboardingVoiceIntent.heard,
        OnboardingVoiceIntent.notHeard,
      },
      OnboardingVoiceQuestion.haptic => {
        OnboardingVoiceIntent.felt,
        OnboardingVoiceIntent.notFelt,
        OnboardingVoiceIntent.skipHaptic,
      },
      OnboardingVoiceQuestion.practice => {
        OnboardingVoiceIntent.stop,
        OnboardingVoiceIntent.move,
        OnboardingVoiceIntent.check,
        OnboardingVoiceIntent.resume,
        OnboardingVoiceIntent.next,
      },
      OnboardingVoiceQuestion.paused => {OnboardingVoiceIntent.resume},
      OnboardingVoiceQuestion.camera => {
        OnboardingVoiceIntent.requestCamera,
        OnboardingVoiceIntent.cameraSettings,
        OnboardingVoiceIntent.defer,
      },
      OnboardingVoiceQuestion.cameraGranted => {OnboardingVoiceIntent.next},
      OnboardingVoiceQuestion.standing => {
        OnboardingVoiceIntent.standing,
        OnboardingVoiceIntent.notStanding,
        OnboardingVoiceIntent.defer,
      },
      OnboardingVoiceQuestion.device || OnboardingVoiceQuestion.deviceDone => {
        OnboardingVoiceIntent.runDevice,
        OnboardingVoiceIntent.defer,
        if (question == OnboardingVoiceQuestion.deviceDone)
          OnboardingVoiceIntent.next,
      },
      OnboardingVoiceQuestion.alignment ||
      OnboardingVoiceQuestion.alignmentConfirm ||
      OnboardingVoiceQuestion.alignmentDone => {
        OnboardingVoiceIntent.runAlignment,
        OnboardingVoiceIntent.defer,
        if (question == OnboardingVoiceQuestion.alignmentConfirm) ...{
          OnboardingVoiceIntent.aligned,
          OnboardingVoiceIntent.notAligned,
        },
        if (question == OnboardingVoiceQuestion.alignmentDone)
          OnboardingVoiceIntent.next,
      },
      OnboardingVoiceQuestion.stationaryCheck ||
      OnboardingVoiceQuestion.stationaryDone => {
        OnboardingVoiceIntent.runStationary,
        OnboardingVoiceIntent.defer,
        if (question == OnboardingVoiceQuestion.stationaryDone)
          OnboardingVoiceIntent.next,
      },
      OnboardingVoiceQuestion.sessionCheck => {
        OnboardingVoiceIntent.runSession,
        OnboardingVoiceIntent.runAlignment,
        OnboardingVoiceIntent.defer,
      },
      OnboardingVoiceQuestion.summaryBlocked ||
      OnboardingVoiceQuestion.summaryReady => {
        OnboardingVoiceIntent.continueSetup,
        OnboardingVoiceIntent.practiceAgain,
        if (question == OnboardingVoiceQuestion.summaryReady)
          OnboardingVoiceIntent.inspect,
      },
    },
  };

  static OnboardingVoiceIntent parse(
    String text,
    AppLanguage language,
    OnboardingVoiceQuestion question,
  ) {
    final normalized = normalize(text);
    for (final intent in allowed(question)) {
      for (final phrase in _phrases[intent]?[language.index] ?? <String>[]) {
        if (normalized == normalize(phrase)) return intent;
      }
    }
    return OnboardingVoiceIntent.unknown;
  }
}
