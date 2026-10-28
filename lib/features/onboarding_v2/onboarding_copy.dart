import '../../models/strings.dart';
import 'onboarding_state.dart';

enum OnboardingText {
  back,
  next,
  later,
  laterHint,
  repeat,
  listen,
  unavailable,
  notChecked,
  confirmed,
  retry,
  settings,
  saveError,
  restoreError,
  restoreFuture,
  restart,
  languageTitle,
  languageBody,
  languageFooter,
  ruContinue,
  kkContinue,
  enContinue,
  accessTitle,
  accessBody,
  voice,
  voiceBody,
  largeText,
  largeTextBody,
  helper,
  helperBody,
  limitsTitle,
  limitsBody,
  limit1,
  limit2,
  limit3,
  limit4,
  understand,
  feedbackTitle,
  feedbackBody,
  ordinaryHeard,
  ordinaryTask,
  stopTask,
  hapticTask,
  useHaptic,
  useVoice,
  hapticRecovery,
  trainingWithoutSignals,
  bootLoading,
  bootError,
  bootTimeout,
  bootRecovery,
  sessionOnlyNotice,
  ordinaryVoice,
  stopVoice,
  stopHaptic,
  heard,
  felt,
  feedbackMissing,
  voiceMissing,
  signalPlayed,
  feedbackFooter,
  speechSpeed,
  privacyTitle,
  privacyBody,
  privacyLocal,
  privacyRecord,
  privacyOptional,
  vocabularyTitle,
  vocabularyBody,
  stopMeaning,
  sideMeaning,
  lostMeaning,
  pauseMeaning,
  practiceTitle,
  practiceBody,
  trainingLabel,
  scene,
  stopAction,
  moveAction,
  checkAction,
  pauseAction,
  resumeAction,
  wrongAction,
  correctAction,
  practiceFinished,
  practicePaused,
  pauseCue,
  resumeCue,
  finishPractice,
  cameraTitle,
  cameraBody,
  cameraRequest,
  cameraLater,
  cameraGranted,
  cameraDenied,
  cameraSettingsUnavailable,
  cameraPermanent,
  cameraRestricted,
  cameraNotRequested,
  deviceTitle,
  deviceBody,
  checkDevice,
  cameraFrames,
  temperature,
  checking,
  cameraUnavailable,
  cameraDark,
  cameraFrozen,
  thermalUnavailable,
  thermalHot,
  alignmentTitle,
  alignmentBody,
  alignmentHold,
  checkAlignment,
  alignmentStable,
  alignmentUnavailable,
  alignmentUnstable,
  alignmentConfirm,
  stationaryTitle,
  stationaryBody,
  stationaryConfirm,
  checkStationary,
  summaryTitle,
  summaryBody,
  setup,
  signals,
  training,
  alignment,
  inspection,
  inspectionBody,
  genericLimited,
  genericLimitedBody,
  trainingRequired,
  recheckRequired,
  trainingAgain,
  continueSetup,
  freshCheck,
  expired,
  close,
  stopped,
  example,
  storageSessionOnly,
  stepProgress,
  nextRequiredStep,
  confirmationRequired,
  repeatInstruction,
  stopSpeech,
  reading,
  stoppingSpeech,
  speechStopped,
  sceneProgress,
  alignmentMoreUpright,
  alignmentMoreFlat,
  alignmentLevel,
  alignmentHoldStill,
  sessionTitle,
  sessionBody,
  sessionProgress,
  sessionSignals,
  sessionPermission,
  sessionDevice,
  sessionCheck,
  sessionCheckHint,
  sessionReady,
  sessionNotReady,
  sessionSetup,
  practiceRestart,
  wrongStop,
  wrongSide,
  wrongLost,
  wrongPause,
  speechEngineUnavailable,
  speechInterrupted,
  speechTimedOut,
  speechFailed,
  speechSettings,
  speechSettingsUnavailable,
  checkSound,
  helperControl,
  userControl,
  helperHandoffBody,
  handToUser,
  handToHelper,
  coachStart,
  coachStop,
  coachBody,
  coachUpright,
  coachFlat,
  coachLevel,
  coachHold,
  coachReady,
  coachRetry,
  coachStopped,
  limitAidTitle,
  limitErrorsTitle,
  limitSilenceTitle,
  limitStationaryTitle,
  privacyLocalTitle,
  privacyRecordTitle,
  privacyPermissionsTitle,
  limitAidDetails,
  limitErrorsDetails,
  limitSilenceDetails,
  limitStationaryDetails,
  privacyLocalDetails,
  privacyRecordDetails,
  privacyPermissionsDetails,
  readBlock,
  moreDetails,
  hideDetails,
  setupPhase,
  trainingPhase,
  cameraPhase,
  setupOverview,
  practiceQuestion,
  nextExample,
  finishExamples,
  practicePauseHint,
}

class OnboardingInfoBlock {
  final OnboardingText title;
  final OnboardingText body;
  final OnboardingText details;
  const OnboardingInfoBlock(this.title, this.body, this.details);
}

/// A single, versioned catalog: every app-owned onboarding label has all three
/// languages. Device errors are mapped to these keys, never displayed raw.
class OnboardingCopy {
  final AppLanguage language;
  const OnboardingCopy(this.language);
  String t(OnboardingText key) => catalog[key]![language.index];
  List<OnboardingInfoBlock> infoBlocks(OnboardingStep step) => switch (step) {
    OnboardingStep.limits => const [
      OnboardingInfoBlock(
        OnboardingText.limitAidTitle,
        OnboardingText.limit1,
        OnboardingText.limitAidDetails,
      ),
      OnboardingInfoBlock(
        OnboardingText.limitErrorsTitle,
        OnboardingText.limit2,
        OnboardingText.limitErrorsDetails,
      ),
      OnboardingInfoBlock(
        OnboardingText.limitSilenceTitle,
        OnboardingText.limit3,
        OnboardingText.limitSilenceDetails,
      ),
      OnboardingInfoBlock(
        OnboardingText.limitStationaryTitle,
        OnboardingText.limit4,
        OnboardingText.limitStationaryDetails,
      ),
    ],
    OnboardingStep.privacy => const [
      OnboardingInfoBlock(
        OnboardingText.privacyLocalTitle,
        OnboardingText.privacyLocal,
        OnboardingText.privacyLocalDetails,
      ),
      OnboardingInfoBlock(
        OnboardingText.privacyRecordTitle,
        OnboardingText.privacyRecord,
        OnboardingText.privacyRecordDetails,
      ),
      OnboardingInfoBlock(
        OnboardingText.privacyPermissionsTitle,
        OnboardingText.privacyOptional,
        OnboardingText.privacyPermissionsDetails,
      ),
    ],
    _ => const [],
  };
  String blockLabel(OnboardingText action, OnboardingInfoBlock block) =>
      t(action).replaceAll('{title}', t(block.title));
  String blockInstruction(OnboardingInfoBlock block, {bool details = false}) =>
      '${t(block.title)}. ${t(block.body)}${details ? '\n${t(block.details)}' : ''}';
  String cameraAccessDescription(CameraAccess access) => t(switch (access) {
    CameraAccess.granted => OnboardingText.cameraGranted,
    CameraAccess.denied => OnboardingText.cameraDenied,
    CameraAccess.permanentlyDenied => OnboardingText.cameraPermanent,
    CameraAccess.restricted => OnboardingText.cameraRestricted,
    CameraAccess.notRequested => OnboardingText.cameraNotRequested,
  });
  String sceneProgress(int index) =>
      t(OnboardingText.sceneProgress).replaceAll('{current}', '${index + 1}');
  String sessionProgress(int index) =>
      t(OnboardingText.sessionProgress).replaceAll('{current}', '$index');
  String probeDescription(ProbeResult result, DateTime now) => t(
    result.status == ProbeStatus.notChecked
        ? OnboardingText.notChecked
        : result.status == ProbeStatus.available
        ? result.freshAt(now)
              ? OnboardingText.freshCheck
              : OnboardingText.expired
        : OnboardingText.values.firstWhere(
            (key) => key.name == result.reason,
            orElse: () => OnboardingText.unavailable,
          ),
  );
  String phase(OnboardingStep step) => t(switch (step) {
    OnboardingStep.language ||
    OnboardingStep.access ||
    OnboardingStep.limits ||
    OnboardingStep.feedback ||
    OnboardingStep.privacy => OnboardingText.setupPhase,
    OnboardingStep.vocabulary ||
    OnboardingStep.practice => OnboardingText.trainingPhase,
    _ => OnboardingText.cameraPhase,
  });
  String stepProgress(OnboardingStep step) => step == OnboardingStep.summary
      ? t(OnboardingText.setupOverview)
      : t(OnboardingText.stepProgress)
            .replaceAll('{current}', '${step.index + 1}')
            .replaceAll('{total}', '${OnboardingStep.values.length}');
  String nextRequiredStep(OnboardingStep step) => t(
    OnboardingText.nextRequiredStep,
  ).replaceAll('{step}', title(step).replaceAll('\n', ' '));

  String get continueLanguage => t(switch (language) {
    AppLanguage.ru => OnboardingText.ruContinue,
    AppLanguage.kk => OnboardingText.kkContinue,
    AppLanguage.en => OnboardingText.enContinue,
  });

  String title(OnboardingStep step) => t(switch (step) {
    OnboardingStep.language => OnboardingText.languageTitle,
    OnboardingStep.access => OnboardingText.accessTitle,
    OnboardingStep.limits => OnboardingText.limitsTitle,
    OnboardingStep.feedback => OnboardingText.feedbackTitle,
    OnboardingStep.privacy => OnboardingText.privacyTitle,
    OnboardingStep.vocabulary => OnboardingText.vocabularyTitle,
    OnboardingStep.practice => OnboardingText.practiceTitle,
    OnboardingStep.camera => OnboardingText.cameraTitle,
    OnboardingStep.device => OnboardingText.deviceTitle,
    OnboardingStep.alignment => OnboardingText.alignmentTitle,
    OnboardingStep.stationary => OnboardingText.stationaryTitle,
    OnboardingStep.summary => OnboardingText.summaryTitle,
  });

  String body(OnboardingStep step) => t(switch (step) {
    OnboardingStep.language => OnboardingText.languageBody,
    OnboardingStep.access => OnboardingText.accessBody,
    OnboardingStep.limits => OnboardingText.limitsBody,
    OnboardingStep.feedback => OnboardingText.feedbackBody,
    OnboardingStep.privacy => OnboardingText.privacyBody,
    OnboardingStep.vocabulary => OnboardingText.vocabularyBody,
    OnboardingStep.practice => OnboardingText.practiceBody,
    OnboardingStep.camera => OnboardingText.cameraBody,
    OnboardingStep.device => OnboardingText.deviceBody,
    OnboardingStep.alignment => OnboardingText.alignmentBody,
    OnboardingStep.stationary => OnboardingText.stationaryBody,
    OnboardingStep.summary => OnboardingText.summaryBody,
  });

  static const catalog = <OnboardingText, List<String>>{
    OnboardingText.setupPhase: ['Знакомство', 'Танысу', 'Getting started'],
    OnboardingText.trainingPhase: ['Обучение', 'Оқу', 'Training'],
    OnboardingText.cameraPhase: [
      'Проверка камеры',
      'Камераны тексеру',
      'Camera check',
    ],
    OnboardingText.setupOverview: [
      'Обзор настройки',
      'Баптауға шолу',
      'Setup overview',
    ],
    OnboardingText.practiceQuestion: [
      'Какое действие подходит?',
      'Қай әрекет сәйкес келеді?',
      'Which action fits?',
    ],
    OnboardingText.nextExample: [
      'Следующий пример',
      'Келесі мысал',
      'Next example',
    ],
    OnboardingText.finishExamples: [
      'Завершить упражнения',
      'Жаттығуларды аяқтау',
      'Finish exercises',
    ],
    OnboardingText.practicePauseHint: [
      'Нажмите «Возобновить», чтобы вернуться к этому примеру.',
      'Осы мысалға оралу үшін «Жалғастыру» түймесін басыңыз.',
      'Select Resume to return to this example.',
    ],
    OnboardingText.helperControl: [
      'Сейчас настраивает помощник',
      'Қазір көмекші баптап жатыр',
      'The helper is setting up',
    ],
    OnboardingText.userControl: [
      'Управление у пользователя',
      'Басқару сізде',
      'The user has control',
    ],
    OnboardingText.helperHandoffBody: [
      'Помощник может настроить приложение и положение телефона. Передайте управление пользователю до подтверждения ограничений, сигналов и ответов на упражнения. После передачи сигналы нужно воспроизвести заново.',
      'Көмекші қолданбаны және телефон қалпын баптай алады. Шектеулерді, сигналдарды растаудан және жаттығуға жауап беруден бұрын басқаруды пайдаланушыға беріңіз. Берген соң сигналдарды қайта ойнату керек.',
      'A helper can configure the app and phone position. Hand control to the user before confirming limitations, signals or exercise answers. Replay the signals after handing over.',
    ],
    OnboardingText.handToUser: [
      'Передать управление пользователю',
      'Басқаруды пайдаланушыға беру',
      'Hand control to the user',
    ],
    OnboardingText.handToHelper: [
      'Вернуть управление помощнику',
      'Басқаруды көмекшіге қайтару',
      'Hand control back to the helper',
    ],
    OnboardingText.coachStart: [
      'Помочь с положением голосом',
      'Қалыпты дауыспен баптауға көмектесу',
      'Guide phone position by voice',
    ],
    OnboardingText.coachStop: [
      'Остановить помощь с положением',
      'Қалыпты баптау көмегін тоқтату',
      'Stop position guidance',
    ],
    OnboardingText.coachBody: [
      'Оставайтесь на месте. По нажатию: измерение, одна голосовая подсказка, затем новое измерение. До четырёх попыток; помощь можно остановить в любой момент. Камера не включается.',
      'Орныңызда қалыңыз. Басқан соң: өлшеу, бір дауыстық нұсқау, содан кейін жаңа өлшеу. Төрт әрекетке дейін; көмекті кез келген уақытта тоқтатуға болады. Камера қосылмайды.',
      'Stay stationary. On request: one measurement, one voice hint, then another measurement. Up to four attempts; stop guidance at any time. The camera stays off.',
    ],
    OnboardingText.coachUpright: [
      'Держите телефон чуть вертикальнее.',
      'Телефонды сәл тіктеп ұстаңыз.',
      'Hold the phone a little more upright.',
    ],
    OnboardingText.coachFlat: [
      'Держите телефон чуть горизонтальнее.',
      'Телефонды сәл көлденең ұстаңыз.',
      'Hold the phone a little flatter.',
    ],
    OnboardingText.coachLevel: [
      'Уберите наклон телефона вбок.',
      'Телефонның бүйірге қисаюын түзетіңіз.',
      'Level the phone from side to side.',
    ],
    OnboardingText.coachHold: [
      'Удерживайте телефон неподвижно.',
      'Телефонды қозғалтпай ұстаңыз.',
      'Hold the phone still.',
    ],
    OnboardingText.coachReady: [
      'Положение устойчиво. Подтвердите сами, что задняя камера направлена вперёд и не закрыта. Оставайтесь на месте.',
      'Қалып тұрақты. Артқы камераның алға бағытталғанын және жабылмағанын өзіңіз растаңыз. Орныңызда қалыңыз.',
      'The position is stable. Confirm yourself that the rear camera faces forward and is uncovered. Stay stationary.',
    ],
    OnboardingText.coachRetry: [
      'Помощь завершена без устойчивого положения. Можно начать заново или проверить положение вручную.',
      'Көмек тұрақты қалыпсыз аяқталды. Қайта бастауға немесе қалыпты қолмен тексеруге болады.',
      'Guidance ended without a stable position. Start again or use the manual position check.',
    ],
    OnboardingText.coachStopped: [
      'Помощь остановлена. Положение нужно проверить заново.',
      'Көмек тоқтатылды. Қалыпты қайта тексеру керек.',
      'Guidance stopped. Check the position again.',
    ],
    OnboardingText.limitAidTitle: [
      'Трость и помощь',
      'Таяқ және көмек',
      'Mobility aids',
    ],
    OnboardingText.limitErrorsTitle: [
      'Возможные ошибки',
      'Ықтимал қателер',
      'Possible errors',
    ],
    OnboardingText.limitSilenceTitle: [
      'Если сигнала нет',
      'Сигнал болмаса',
      'When there is no alert',
    ],
    OnboardingText.limitStationaryTitle: [
      'Проверка на месте',
      'Бір орында тексеру',
      'Stationary checks',
    ],
    OnboardingText.privacyLocalTitle: [
      'Обработка на телефоне',
      'Телефонда өңдеу',
      'Processing on your phone',
    ],
    OnboardingText.privacyRecordTitle: [
      'Без записи',
      'Жазбасыз',
      'No recording',
    ],
    OnboardingText.privacyPermissionsTitle: [
      'Разрешения',
      'Рұқсаттар',
      'Permissions',
    ],
    OnboardingText.limitAidDetails: [
      'Продолжайте пользоваться привычным средством ориентирования. Учебная подсказка не разрешает идти.',
      'Үйреншікті бағдарлау құралын қолдана беріңіз. Оқу нұсқауы жүруге рұқсат бермейді.',
      'Keep using your usual mobility aid. A training prompt does not authorize walking.',
    ],
    OnboardingText.limitErrorsDetails: [
      'Сигнал может быть ошибочным, а реальное препятствие может остаться незамеченным. Проверяйте пространство привычным способом.',
      'Сигнал қате болуы, ал нақты кедергі байқалмай қалуы мүмкін. Айналаны үйреншікті тәсілмен тексеріңіз.',
      'An alert may be wrong and a real obstacle may be missed. Check your surroundings using your usual method.',
    ],
    OnboardingText.limitSilenceDetails: [
      'Приложение может потерять данные или не распознать объект. Тишина не подтверждает безопасность движения.',
      'Қолданба деректерді жоғалтуы немесе нысанды танымауы мүмкін. Тыныштық қозғалыстың қауіпсіздігін растамайды.',
      'The app may lose data or fail to recognize an object. Silence does not establish safe movement.',
    ],
    OnboardingText.limitStationaryDetails: [
      'Выберите знакомое помещение. Оставайтесь на месте во время примеров, настройки положения и проверки камеры.',
      'Таныс бөлмені таңдаңыз. Мысалдар, қалыпты баптау және камераны тексеру кезінде орныңызда қалыңыз.',
      'Choose a familiar indoor space. Stay stationary during examples, position setup and camera checks.',
    ],
    OnboardingText.privacyLocalDetails: [
      'Камера открывается только при явном запуске проверки. Язык, упражнения и голосовые примеры работают без камеры.',
      'Камера тек тексеруді өзіңіз бастағанда ашылады. Тіл, жаттығулар және дауыстық мысалдар камерасыз жұмыс істейді.',
      'The camera opens only when you explicitly start a check. Language selection, exercises and voice examples work without it.',
    ],
    OnboardingText.privacyRecordDetails: [
      'Проверка получает кадры для оценки камеры, но не сохраняет их как фото или видео и не отправляет их на сервер.',
      'Тексеру камераны бағалау үшін кадрларды алады, бірақ оларды фото не бейне ретінде сақтамайды және серверге жібермейді.',
      'A check receives frames to assess the camera, but does not save them as photos or video or send them to a server.',
    ],
    OnboardingText.privacyPermissionsDetails: [
      'Разрешение камеры можно отложить и продолжить обучение. Прослушивание инструкций не требует микрофона; для голосовых ответов нужно отдельно включить микрофон. Положение измеряется датчиком телефона.',
      'Камера рұқсатын кейінге қалдырып, оқуды жалғастыруға болады. Нұсқауларды тыңдауға микрофон керек емес; дауыспен жауап беру үшін микрофонды бөлек қосу керек. Қалып телефон датчигімен өлшенеді.',
      'You can defer camera permission and continue training. Listening to instructions does not need a microphone; voice answers require separately enabling it. Position is measured using the phone sensor.',
    ],
    OnboardingText.readBlock: [
      'Прослушать: {title}',
      'Тыңдау: {title}',
      'Listen: {title}',
    ],
    OnboardingText.moreDetails: [
      'Подробнее: {title}',
      'Толығырақ: {title}',
      'More about: {title}',
    ],
    OnboardingText.hideDetails: [
      'Скрыть пояснение: {title}',
      'Түсіндірмені жасыру: {title}',
      'Hide explanation: {title}',
    ],
    OnboardingText.back: ['Назад', 'Артқа', 'Back'],
    OnboardingText.next: ['Продолжить', 'Жалғастыру', 'Continue'],
    OnboardingText.later: [
      'Продолжить позже',
      'Кейін жалғастыру',
      'Continue later',
    ],
    OnboardingText.laterHint: [
      'Прогресс сохранён. Можно вернуться к настройке.',
      'Барысы сақталды. Баптауға қайта оралуға болады.',
      'Progress saved. You can return to setup.',
    ],
    OnboardingText.repeat: ['Повторить', 'Қайталау', 'Repeat'],
    OnboardingText.listen: [
      'Прослушать пример',
      'Мысалды тыңдау',
      'Listen to an example',
    ],
    OnboardingText.unavailable: ['Недоступно', 'Қолжетімсіз', 'Unavailable'],
    OnboardingText.notChecked: ['Не проверено', 'Тексерілмеген', 'Not checked'],
    OnboardingText.confirmed: ['Подтверждено', 'Расталды', 'Confirmed'],
    OnboardingText.retry: ['Проверить снова', 'Қайта тексеру', 'Check again'],
    OnboardingText.settings: [
      'Открыть настройки',
      'Баптауларды ашу',
      'Open settings',
    ],
    OnboardingText.saveError: [
      'Не удалось сохранить прогресс. Повторите действие.',
      'Барысын сақтау мүмкін болмады. Әрекетті қайталаңыз.',
      'Could not save progress. Try the action again.',
    ],
    OnboardingText.restoreError: [
      'Не удалось прочитать сохранённую настройку. Повторите загрузку или обучайтесь без сохранения. «Начать настройку заново» заменит сохранённый прогресс; осмотр потребует всех проверок.',
      'Сақталған баптау оқылмады. Жүктеуді қайталаңыз немесе сақтаусыз оқыңыз. «Баптауды қайта бастау» сақталған нәтижені алмастырады; тексеру үшін барлық тексерулер қажет.',
      'Saved setup could not be read. Retry loading or train without saving. Restart setup replaces saved progress; inspection still requires every check.',
    ],
    OnboardingText.restoreFuture: [
      'Настройка сохранена другой версией приложения. Обновите приложение. Обучение доступно без сохранения.',
      'Баптау басқа қолданба нұсқасында сақталған. Қолданбаны жаңартыңыз. Оқуды сақтаусыз өтуге болады.',
      'Setup was saved by a different app version. Update the app. Training is available without saving.',
    ],
    OnboardingText.restart: [
      'Начать настройку заново',
      'Баптауды қайта бастау',
      'Restart setup',
    ],
    OnboardingText.languageTitle: [
      'На каком языке\nвам удобнее?',
      'Қай тіл сізге\nыңғайлы?',
      'Which language\ndo you prefer?',
    ],
    OnboardingText.languageBody: [
      'Выберите язык интерфейса и подсказок.',
      'Интерфейс пен нұсқаулар тілін таңдаңыз.',
      'Choose the language for the interface and prompts.',
    ],
    OnboardingText.languageFooter: [
      'Язык можно изменить позже.',
      'Тілді кейін өзгертуге болады.',
      'You can change the language later.',
    ],
    OnboardingText.ruContinue: [
      'Продолжить на русском',
      'Орыс тілінде жалғастыру',
      'Continue in Russian',
    ],
    OnboardingText.kkContinue: [
      'Продолжить на казахском',
      'Қазақша жалғастыру',
      'Continue in Kazakh',
    ],
    OnboardingText.enContinue: [
      'Продолжить на английском',
      'Ағылшын тілінде жалғастыру',
      'Continue in English',
    ],
    OnboardingText.accessTitle: [
      'Как вам удобнее\nпользоваться?',
      'Қалай қолданған\nыңғайлы?',
      'How would you\nlike to use Bagdar?',
    ],
    OnboardingText.accessBody: [
      'Настроим интерфейс под вас. Выбор можно изменить.',
      'Интерфейсті өзіңізге бейімдейік. Таңдауды өзгертуге болады.',
      'Adapt the interface to your needs. You can change this later.',
    ],
    OnboardingText.voice: [
      'С голосовыми подсказками',
      'Дауыстық нұсқаулармен',
      'With voice prompts',
    ],
    OnboardingText.voiceBody: [
      'Обычный текст и звук',
      'Қалыпты мәтін мен дыбыс',
      'Standard text and audio',
    ],
    OnboardingText.largeText: [
      'Крупный текст и голос',
      'Ірі мәтін және дауыс',
      'Large text and voice',
    ],
    OnboardingText.largeTextBody: [
      'Увеличенные подписи и элементы',
      'Үлкейтілген жазулар мен элементтер',
      'Larger labels and controls',
    ],
    OnboardingText.helper: [
      'С помощником',
      'Көмекшімен бірге',
      'With a helper',
    ],
    OnboardingText.helperBody: [
      'Настройка вместе с другим человеком',
      'Басқа адаммен бірге баптау',
      'Set up together with another person',
    ],
    OnboardingText.limitsTitle: [
      'Перед началом',
      'Бастамас бұрын',
      'Before you begin',
    ],
    OnboardingText.limitsBody: [
      'Пожалуйста, прочитайте ограничения Bagdar.',
      'Bagdar шектеулерін оқып шығыңыз.',
      'Please read Bagdar’s limitations.',
    ],
    OnboardingText.limit1: [
      'Bagdar не заменяет трость, собаку-проводника или помощника.',
      'Bagdar таяқты, жетектеуші итті немесе көмекшіні алмастырмайды.',
      'Bagdar does not replace a cane, guide dog or helper.',
    ],
    OnboardingText.limit2: [
      'Приложение может пропустить препятствие или предупредить по ошибке.',
      'Қолданба кедергіні байқамай қалуы немесе қате ескертуі мүмкін.',
      'The app may miss an obstacle or warn by mistake.',
    ],
    OnboardingText.limit3: [
      'Отсутствие сигнала не означает, что путь свободен.',
      'Сигналдың болмауы жолдың ашық екенін білдірмейді.',
      'No alert does not mean the path is clear.',
    ],
    OnboardingText.limit4: [
      'Первую проверку проводите стоя на месте, в знакомом помещении.',
      'Алғашқы тексеруді таныс бөлмеде, орныңызда тұрып жасаңыз.',
      'Do the first check while stationary in a familiar indoor space.',
    ],
    OnboardingText.understand: [
      'Я понимаю эти ограничения',
      'Осы шектеулерді түсінемін',
      'I understand these limitations',
    ],
    OnboardingText.feedbackTitle: [
      'Проверим сигналы',
      'Сигналдарды тексерейік',
      'Check the signals',
    ],
    OnboardingText.feedbackBody: [
      'Воспроизведите примеры и отметьте только те, которые слышите или чувствуете.',
      'Мысалдарды ойнатып, тек естіген немесе сезген сигналдарды белгілеңіз.',
      'Play the examples and confirm only the signals you hear or feel.',
    ],
    OnboardingText.ordinaryVoice: [
      'Обычная подсказка',
      'Қалыпты нұсқау',
      'Ordinary voice prompt',
    ],
    OnboardingText.stopVoice: [
      'Голосовой сигнал «Стоп»',
      '«Тоқта» дауыстық сигналы',
      'Voice “Stop” signal',
    ],
    OnboardingText.stopHaptic: [
      'Вибрация «Стоп»',
      '«Тоқта» дірілі',
      '“Stop” vibration',
    ],
    OnboardingText.heard: [
      'Я слышу оба голосовых сигнала',
      'Екі дауыстық сигналды да естимін',
      'I hear both voice signals',
    ],
    OnboardingText.felt: [
      'Я чувствую вибрацию «Стоп»',
      '«Тоқта» дірілін сеземін',
      'I feel the “Stop” vibration',
    ],
    OnboardingText.feedbackMissing: [
      'Сигналы не подтверждены. Обучение по тексту доступно; проверка с камерой потребует повторной настройки.',
      'Сигналдар расталмады. Мәтінмен оқу қолжетімді; камерамен тексеру үшін қайта баптау қажет.',
      'Signals are not confirmed. Text training is available; camera inspection will require another signal check.',
    ],
    OnboardingText.voiceMissing: [
      'Голос выбранного языка недоступен. В настройках синтеза речи установите голос этого языка, затем повторите пример.',
      'Таңдалған тілдің дауысы қолжетімсіз. Сөйлеу синтезі баптауларында осы тілдің дауысын орнатып, мысалды қайталаңыз.',
      'The selected language voice is unavailable. Install that voice in text-to-speech settings, then repeat the example.',
    ],
    OnboardingText.signalPlayed: [
      'Пример воспроизведён. Подтвердите, если вы его различили.',
      'Мысал ойнатылды. Оны ажыратсаңыз, растаңыз.',
      'Example played. Confirm if you could distinguish it.',
    ],
    OnboardingText.feedbackFooter: [
      'Подтверждение относится к текущему звуку и устройству.',
      'Растау ағымдағы дыбыс пен құрылғыға қатысты.',
      'Confirmation applies to the current audio and device.',
    ],
    OnboardingText.speechSpeed: ['Темп речи', 'Сөйлеу қарқыны', 'Speech speed'],
    OnboardingText.ordinaryHeard: [
      'Я различаю обычную голосовую подсказку',
      'Кәдімгі дауыстық нұсқауды ажыратамын',
      'I can distinguish the ordinary voice prompt',
    ],
    OnboardingText.ordinaryTask: [
      '1. Включите обычную подсказку. Затем подтвердите, что различили её.',
      '1. Кәдімгі нұсқауды тыңдаңыз. Оны ажыратқаныңызды растаңыз.',
      '1. Play the ordinary prompt. Then confirm you could distinguish it.',
    ],
    OnboardingText.stopTask: [
      '2. Включите «Стоп». Подтвердите, только если различаете оба голосовых сигнала.',
      '2. «Тоқта» сигналын тыңдаңыз. Екі дауыстық сигналды да ажыратсаңыз ғана растаңыз.',
      '2. Play “Stop”. Confirm only if you can distinguish both voice signals.',
    ],
    OnboardingText.hapticTask: [
      'Проверка вибрации. Включите «Стоп», затем подтвердите, если почувствовали сигнал.',
      'Дірілді тексеру. «Тоқта» сигналын қосып, оны сезсеңіз растаңыз.',
      'Vibration check. Play “Stop”, then confirm if you felt the signal.',
    ],
    OnboardingText.useHaptic: [
      'Проверить вибрацию',
      'Дірілді тексеру',
      'Check vibration',
    ],
    OnboardingText.useVoice: [
      'Вернуться к голосовым сигналам',
      'Дауыстық сигналдарға оралу',
      'Return to voice signals',
    ],
    OnboardingText.hapticRecovery: [
      'Нет вибрации? Проверьте системные настройки вибрации и повторите. Можно проверить голос или продолжить обучение по тексту. Осмотр останется недоступен без подтверждённого сигнала.',
      'Діріл жоқ па? Жүйедегі діріл баптауларын тексеріп, қайталаңыз. Дауысты тексеруге немесе мәтінмен оқуға болады. Расталған сигналсыз тексеру қолжетімсіз.',
      'No vibration? Check system vibration settings and retry. You can check voice or continue text training. Inspection stays unavailable without a confirmed signal.',
    ],
    OnboardingText.trainingWithoutSignals: [
      'Продолжить обучение без проверки сигналов',
      'Сигналдарды тексермей оқуды жалғастыру',
      'Continue training without checking signals',
    ],
    OnboardingText.bootLoading: [
      'Загружаем сохранённую настройку',
      'Сақталған баптауды жүктеп жатырмыз',
      'Loading saved setup',
    ],
    OnboardingText.bootError: [
      'Не удалось загрузить настройку',
      'Баптауды жүктеу мүмкін болмады',
      'Could not load setup',
    ],
    OnboardingText.bootTimeout: [
      'Загрузка настройки не завершилась',
      'Баптауды жүктеу аяқталмады',
      'Setup loading did not finish',
    ],
    OnboardingText.bootRecovery: [
      'Повторите загрузку или начните обучение без сохранения. Осмотр пока недоступен. Сохранённые согласия и обучение не будут сброшены.',
      'Жүктеуді қайталаңыз немесе сақтаусыз оқуды бастаңыз. Әзірге тексеру қолжетімсіз. Сақталған келісімдер мен оқу өшірілмейді.',
      'Retry loading or start training without saving. Inspection is unavailable for now. Saved consents and training will not be reset.',
    ],
    OnboardingText.sessionOnlyNotice: [
      'Обучение без сохранения. Прогресс этого сеанса исчезнет после закрытия. Осмотр недоступен; сохранённые согласия не меняются. Для обычной настройки закройте и снова откройте приложение.',
      'Сақтаусыз оқу. Бұл сеанстың нәтижесі жабылған соң жоғалады. Тексеру қолжетімсіз; сақталған келісімдер өзгермейді. Қалыпты баптау үшін қолданбаны жауып, қайта ашыңыз.',
      'Training without saving. This session’s progress is lost when closed. Inspection is unavailable; saved consents stay unchanged. Close and reopen the app to load normal setup.',
    ],
    OnboardingText.privacyTitle: [
      'О ваших данных',
      'Деректеріңіз туралы',
      'About your data',
    ],
    OnboardingText.privacyBody: [
      'Для этой настройки нужен только доступ к камере — когда вы решите её проверить.',
      'Бұл баптауға камераға рұқсат қана керек — оны тексеруді таңдаған кезде.',
      'This setup needs camera access only, when you choose to test it.',
    ],
    OnboardingText.privacyLocal: [
      'Кадры для проверки обрабатываются на устройстве.',
      'Тексеру кадрлары құрылғыда өңделеді.',
      'Inspection frames are processed on the device.',
    ],
    OnboardingText.privacyRecord: [
      'В этом обучении нет записи или отправки фото и видео.',
      'Бұл оқуда фото мен бейне жазылмайды және жіберілмейді.',
      'This training does not record or send photos or video.',
    ],
    OnboardingText.privacyOptional: [
      'Микрофон запрашивается только при включении голосовых ответов. Геолокация, контакты и SMS здесь не запрашиваются. Диагностика не включается.',
      'Микрофон рұқсаты тек дауыстық жауаптарды қосқанда сұралады. Мұнда геолокация, контактілер және SMS сұралмайды. Диагностика қосылмайды.',
      'Microphone permission is requested only when you enable voice answers. Location, contacts and SMS are not requested here. Diagnostics are not enabled.',
    ],
    OnboardingText.vocabularyTitle: [
      'Что означают\nподсказки',
      'Нұсқаулар нені\nбілдіреді',
      'What the\nprompts mean',
    ],
    OnboardingText.vocabularyBody: [
      'Эти примеры учебные. Не двигайтесь по их указанию.',
      'Бұл оқу мысалдары. Олардың нұсқауымен қозғалмаңыз.',
      'These are training examples. Do not move in response to them.',
    ],
    OnboardingText.stopMeaning: [
      'Остановитесь. Проверьте пространство привычным способом.',
      'Тоқтаңыз. Айналаны үйреншікті тәсілмен тексеріңіз.',
      'Stop. Check your surroundings using your usual method.',
    ],
    OnboardingText.sideMeaning: [
      'Слева замечен объект. Это не команда повернуть направо.',
      'Сол жақтан нысан байқалды. Бұл оңға бұрылу бұйрығы емес.',
      'An object was detected on the left. This is not an instruction to turn right.',
    ],
    OnboardingText.lostMeaning: [
      'Данные камеры недоступны. Не считайте тишину разрешением идти.',
      'Камера деректері қолжетімсіз. Тыныштықты жүруге рұқсат деп қабылдамаңыз.',
      'Camera data is unavailable. Silence is not permission to walk.',
    ],
    OnboardingText.pauseMeaning: [
      'Пауза останавливает упражнение. Возобновление требует отдельного действия.',
      'Үзіліс жаттығуды тоқтатады. Жалғастыру үшін жеке әрекет қажет.',
      'Pause stops the exercise. Resuming requires a separate action.',
    ],
    OnboardingText.practiceTitle: [
      'Попробуем\nбез камеры',
      'Камерасыз\nсынап көрейік',
      'Try it\nwithout the camera',
    ],
    OnboardingText.practiceBody: [
      'Оставайтесь на месте. Выберите действие для каждого учебного сигнала.',
      'Орныңызда қалыңыз. Әр оқу сигналына сай әрекетті таңдаңыз.',
      'Stay stationary. Choose an action for each training signal.',
    ],
    OnboardingText.trainingLabel: [
      'Учебный пример · камера выключена',
      'Оқу мысалы · камера өшірулі',
      'Training example · camera off',
    ],
    OnboardingText.scene: ['Упражнение', 'Жаттығу', 'Exercise'],
    OnboardingText.stopAction: ['Остановиться', 'Тоқтау', 'Stop'],
    OnboardingText.moveAction: [
      'Продолжить движение',
      'Қозғалысты жалғастыру',
      'Keep walking',
    ],
    OnboardingText.checkAction: [
      'Проверить пространство',
      'Айналаны тексеру',
      'Check surroundings',
    ],
    OnboardingText.pauseAction: ['Поставить на паузу', 'Үзіліске қою', 'Pause'],
    OnboardingText.resumeAction: ['Возобновить', 'Жалғастыру', 'Resume'],
    OnboardingText.wrongAction: [
      'Попробуйте ещё раз. Этот сигнал не разрешает продолжать движение.',
      'Қайта көріңіз. Бұл сигнал қозғалысты жалғастыруға рұқсат бермейді.',
      'Try again. This signal does not authorize walking.',
    ],
    OnboardingText.correctAction: [
      'Верно. Можно перейти к следующему примеру.',
      'Дұрыс. Келесі мысалға өтуге болады.',
      'Correct. You can go to the next example.',
    ],
    OnboardingText.practiceFinished: [
      'Все четыре упражнения пройдены.',
      'Төрт жаттығу да аяқталды.',
      'All four exercises are complete.',
    ],
    OnboardingText.practicePaused: [
      'Упражнение на паузе',
      'Жаттығу үзілісте',
      'Exercise paused',
    ],
    OnboardingText.pauseCue: [
      'Пауза. Подсказки остановлены.',
      'Үзіліс. Нұсқаулар тоқтатылды.',
      'Paused. Prompts stopped.',
    ],
    OnboardingText.resumeCue: [
      'Обучение возобновлено.',
      'Оқу жалғасты.',
      'Training resumed.',
    ],
    OnboardingText.finishPractice: [
      'К настройке камеры',
      'Камераны баптауға өту',
      'Continue to camera setup',
    ],
    OnboardingText.cameraTitle: [
      'Подключим камеру?',
      'Камераны қосайық па?',
      'Connect the camera?',
    ],
    OnboardingText.cameraBody: [
      'Камера нужна для проверки изображения. Можно продолжить обучение без неё.',
      'Камера кескінді тексеру үшін қажет. Оқуды онсыз жалғастыруға болады.',
      'The camera is needed to inspect the image. You can continue training without it.',
    ],
    OnboardingText.cameraRequest: [
      'Разрешить камеру',
      'Камераға рұқсат беру',
      'Allow camera access',
    ],
    OnboardingText.cameraLater: [
      'Продолжить обучение без проверки камеры',
      'Камераны тексермей оқуды жалғастыру',
      'Continue training without checking the camera',
    ],
    OnboardingText.cameraGranted: [
      'Доступ к камере разрешён',
      'Камераға рұқсат берілді',
      'Camera permission granted',
    ],
    OnboardingText.cameraDenied: [
      'Доступ к камере отклонён. Его можно запросить снова.',
      'Камераға рұқсат берілмеді. Қайта сұрауға болады.',
      'Camera access denied. You can request it again.',
    ],
    OnboardingText.cameraSettingsUnavailable: [
      'Не удалось открыть настройки приложения. Откройте их через настройки Android и проверьте разрешение камеры.',
      'Қолданба баптауларын ашу мүмкін болмады. Оларды Android баптауларынан ашып, камера рұқсатын тексеріңіз.',
      'App settings could not be opened. Open them through Android settings and check camera permission.',
    ],
    OnboardingText.cameraPermanent: [
      'Доступ к камере отключён. Измените разрешение в настройках устройства.',
      'Камераға рұқсат өшірулі. Құрылғы баптауларында рұқсатты өзгертіңіз.',
      'Camera access is disabled. Change permission in device settings.',
    ],
    OnboardingText.cameraRestricted: [
      'Доступ к камере ограничен на этом устройстве.',
      'Бұл құрылғыда камераға рұқсат шектелген.',
      'Camera access is restricted on this device.',
    ],
    OnboardingText.cameraNotRequested: [
      'Доступ к камере ещё не запрашивался',
      'Камераға рұқсат әлі сұралмады',
      'Camera permission has not been requested',
    ],
    OnboardingText.deviceTitle: [
      'Проверим устройство',
      'Құрылғыны тексерейік',
      'Check the device',
    ],
    OnboardingText.deviceBody: [
      'Проверим поступление кадров и температуру. Проверка занимает несколько секунд и закрывает камеру.',
      'Кадрлардың келуі мен температураны тексереміз. Тексеру бірнеше секундқа созылып, камераны жабады.',
      'Check incoming frames and temperature. The check takes a few seconds and closes the camera.',
    ],
    OnboardingText.checkDevice: [
      'Запустить проверку',
      'Тексеруді бастау',
      'Run checks',
    ],
    OnboardingText.cameraFrames: [
      'Изображение камеры',
      'Камера кескіні',
      'Camera image',
    ],
    OnboardingText.temperature: [
      'Температура устройства',
      'Құрылғы температурасы',
      'Device temperature',
    ],
    OnboardingText.checking: ['Проверяем…', 'Тексерілуде…', 'Checking…'],
    OnboardingText.cameraUnavailable: [
      'Не удалось получить свежие кадры. Проверьте разрешение и повторите.',
      'Жаңа кадрларды алу мүмкін болмады. Рұқсатты тексеріп, қайталаңыз.',
      'Could not receive fresh frames. Check permission and retry.',
    ],
    OnboardingText.cameraDark: [
      'Изображение слишком тёмное или камера закрыта. Проверьте освещение и объектив.',
      'Кескін тым қараңғы немесе камера жабық. Жарық пен объективті тексеріңіз.',
      'The image is too dark or the camera is covered. Check lighting and the lens.',
    ],
    OnboardingText.cameraFrozen: [
      'Кадры не меняются. Освободите камеру и повторите проверку.',
      'Кадрлар өзгермейді. Камераны босатып, қайта тексеріңіз.',
      'Frames are not changing. Uncover the camera and retry.',
    ],
    OnboardingText.thermalUnavailable: [
      'Данные температуры недоступны',
      'Температура деректері қолжетімсіз',
      'Temperature data is unavailable',
    ],
    OnboardingText.thermalHot: [
      'Устройство перегрето. Дайте ему остыть.',
      'Құрылғы қызып кетті. Суығанын күтіңіз.',
      'The device is too hot. Let it cool down.',
    ],
    OnboardingText.alignmentTitle: [
      'Как держать\nтелефон',
      'Телефонды қалай\nұстау керек',
      'How to hold\nthe phone',
    ],
    OnboardingText.alignmentBody: [
      'Оставайтесь на месте. Направьте заднюю камеру вперёд, не закрывая объектив.',
      'Орныңызда қалыңыз. Объективті жаппай, артқы камераны алға бағыттаңыз.',
      'Stay stationary. Point the rear camera ahead without covering the lens.',
    ],
    OnboardingText.alignmentHold: [
      'Держите телефон ровно и неподвижно. Если используете крепление, установите его сейчас.',
      'Телефонды түзу әрі қозғалтпай ұстаңыз. Бекіткіш қолдансаңыз, қазір орнатыңыз.',
      'Hold the phone steady and level. If using a mount, attach it now.',
    ],
    OnboardingText.checkAlignment: [
      'Проверить положение',
      'Қалпын тексеру',
      'Check position',
    ],
    OnboardingText.alignmentStable: [
      'Положение устойчивое по данным датчика',
      'Датчик деректері бойынша қалпы тұрақты',
      'Sensor data shows a stable position',
    ],
    OnboardingText.alignmentUnavailable: [
      'Нет свежих данных положения. Обучение доступно без них.',
      'Телефон қалпының жаңа деректері жоқ. Оқуды онсыз өтуге болады.',
      'No fresh orientation data. Training remains available.',
    ],
    OnboardingText.alignmentUnstable: [
      'Положение неустойчивое или камера направлена не вперёд. Повторите проверку.',
      'Телефон тұрақсыз немесе камера алға бағытталмаған. Қайта тексеріңіз.',
      'Position is unstable or the camera is not facing ahead. Retry the check.',
    ],
    OnboardingText.alignmentConfirm: [
      'Я сохранил это положение телефона',
      'Телефонды осы қалыпта ұстадым',
      'I have kept the phone in this position',
    ],
    OnboardingText.stationaryTitle: [
      'Первая проверка\nна месте',
      'Орныңызда тұрып\nалғаш тексеру',
      'First check\nwhile stationary',
    ],
    OnboardingText.stationaryBody: [
      'В знакомом помещении проверьте камеру ещё раз. Это проверка работы устройства, а не точности распознавания.',
      'Таныс бөлмеде камераны қайта тексеріңіз. Бұл тану дәлдігін емес, құрылғы жұмысын тексереді.',
      'Check the camera again in a familiar indoor space. This checks the device, not recognition accuracy.',
    ],
    OnboardingText.stationaryConfirm: [
      'Я стою на месте в знакомом помещении',
      'Таныс бөлмеде орнымда тұрмын',
      'I am stationary in a familiar indoor space',
    ],
    OnboardingText.checkStationary: [
      'Проверить камеру на месте',
      'Камераны орнымда тұрып тексеру',
      'Check camera while stationary',
    ],
    OnboardingText.summaryTitle: [
      'Ваши настройки',
      'Сіздің баптауларыңыз',
      'Your setup',
    ],
    OnboardingText.summaryBody: [
      'Обучение и состояние устройства показаны отдельно. Проверки действуют только в текущем сеансе.',
      'Оқу мен құрылғы күйі бөлек көрсетілген. Тексерулер тек ағымдағы сеанста жарамды.',
      'Training and device status are shown separately. Checks apply only to the current session.',
    ],
    OnboardingText.setup: [
      'Настройка интерфейса',
      'Интерфейсті баптау',
      'Interface setup',
    ],
    OnboardingText.signals: [
      'Различимость сигналов',
      'Сигналдарды ажырату',
      'Signal recognition',
    ],
    OnboardingText.training: [
      'Учебные упражнения',
      'Оқу жаттығулары',
      'Training exercises',
    ],
    OnboardingText.alignment: [
      'Положение телефона',
      'Телефон қалпы',
      'Phone position',
    ],
    OnboardingText.inspection: [
      'Открыть проверку камеры',
      'Камера тексеруін ашу',
      'Open camera inspection',
    ],
    OnboardingText.inspectionBody: [
      'Оставайтесь на месте. Эта проверка не разрешает самостоятельную ходьбу с Bagdar.',
      'Орныңызда қалыңыз. Бұл тексеру Bagdar-мен өз бетінше жүруге рұқсат бермейді.',
      'Stay stationary. This inspection does not authorize independent walking with Bagdar.',
    ],
    OnboardingText.genericLimited: [
      'Обнаружение препятствий: исследовательский режим',
      'Кедергілерді анықтау: зерттеу режимі',
      'Obstacle detection: research mode',
    ],
    OnboardingText.genericLimitedBody: [
      'Готовность устройства не подтверждает точность модели. Пространственные подсказки остаются в теневом режиме.',
      'Құрылғы дайындығы модель дәлдігін растамайды. Кеңістіктік нұсқаулар көлеңкелі режимде қалады.',
      'Device readiness does not establish model accuracy. Spatial prompts remain in shadow mode.',
    ],
    OnboardingText.trainingRequired: [
      'Настройка и обучение ещё не завершены',
      'Баптау мен оқу әлі аяқталмады',
      'Setup and training are not yet complete',
    ],
    OnboardingText.recheckRequired: [
      'Для проверки с камерой повторите недостающие проверки',
      'Камерамен тексеру үшін жетіспейтін тексерулерді қайталаңыз',
      'Repeat missing checks before camera inspection',
    ],
    OnboardingText.trainingAgain: [
      'Повторить обучение без камеры',
      'Камерасыз оқуды қайталау',
      'Repeat training without camera',
    ],
    OnboardingText.continueSetup: [
      'Продолжить настройку',
      'Баптауды жалғастыру',
      'Continue setup',
    ],
    OnboardingText.freshCheck: [
      'Проверено сейчас',
      'Қазір тексерілді',
      'Checked this session',
    ],
    OnboardingText.expired: [
      'Нужна повторная проверка',
      'Қайта тексеру қажет',
      'Recheck required',
    ],
    OnboardingText.close: ['Закрыть', 'Жабу', 'Close'],
    OnboardingText.stopped: [
      'Проверка остановлена',
      'Тексеру тоқтатылды',
      'Check stopped',
    ],
    OnboardingText.example: [
      'Это пример голосовой подсказки Bagdar.',
      'Бұл Bagdar дауыстық нұсқауының мысалы.',
      'This is an example of a Bagdar voice prompt.',
    ],
    OnboardingText.storageSessionOnly: [
      'Обучение без сохранения',
      'Сақтаусыз оқу',
      'Training without saving',
    ],
    OnboardingText.stepProgress: [
      'Шаг {current} из {total}',
      '{total} қадамның {current}-қадамы',
      'Step {current} of {total}',
    ],
    OnboardingText.nextRequiredStep: [
      'Следующий обязательный шаг: {step}. Кнопка «Продолжить настройку» откроет его.',
      'Келесі міндетті қадам: {step}. «Баптауды жалғастыру» түймесі оны ашады.',
      'Next required step: {step}. Continue setup opens this step.',
    ],
    OnboardingText.confirmationRequired: [
      'Датчик проверен. Подтвердите, что сохранили положение телефона.',
      'Датчик тексерілді. Телефонды осы қалыпта ұстап тұрғаныңызды растаңыз.',
      'Sensor checked. Confirm that you have kept the phone in this position.',
    ],
    OnboardingText.repeatInstruction: [
      'Повторить инструкцию',
      'Нұсқауды қайталау',
      'Repeat this step’s instructions',
    ],
    OnboardingText.stopSpeech: [
      'Остановить озвучку',
      'Дауысты тоқтату',
      'Stop reading',
    ],
    OnboardingText.reading: [
      'Читаем инструкцию',
      'Нұсқау оқылып жатыр',
      'Reading aloud',
    ],
    OnboardingText.stoppingSpeech: [
      'Останавливаем озвучку',
      'Дауыс тоқтатылып жатыр',
      'Stopping speech',
    ],
    OnboardingText.speechStopped: [
      'Озвучка остановлена. Можно повторить инструкцию.',
      'Дауыс тоқтатылды. Нұсқауды қайта тыңдауға болады.',
      'Reading stopped. You can repeat the instructions.',
    ],
    OnboardingText.sceneProgress: [
      'Упражнение {current} из 4',
      '4 жаттығудың {current}-жаттығуы',
      'Exercise {current} of 4',
    ],
    OnboardingText.alignmentMoreUpright: [
      'Держите телефон чуть вертикальнее и повторите проверку. Оставайтесь на месте.',
      'Телефонды сәл тіктеп, қайта тексеріңіз. Орныңызда қалыңыз.',
      'Hold the phone a little more upright and check again. Stay stationary.',
    ],
    OnboardingText.alignmentMoreFlat: [
      'Держите телефон чуть горизонтальнее и повторите проверку. Оставайтесь на месте.',
      'Телефонды сәл көлденең ұстап, қайта тексеріңіз. Орныңызда қалыңыз.',
      'Hold the phone a little flatter and check again. Stay stationary.',
    ],
    OnboardingText.alignmentLevel: [
      'Выровняйте телефон, убрав наклон вбок, и повторите проверку.',
      'Телефонның бүйірге қисаюын түзетіп, қайта тексеріңіз.',
      'Level the phone from side to side and check again.',
    ],
    OnboardingText.alignmentHoldStill: [
      'Удерживайте телефон неподвижно несколько секунд и повторите проверку.',
      'Телефонды бірнеше секунд қозғалтпай ұстап, қайта тексеріңіз.',
      'Hold the phone still for a few seconds and check again.',
    ],
    OnboardingText.sessionTitle: [
      'Проверка перед запуском',
      'Іске қосар алдында тексеру',
      'Check before starting',
    ],
    OnboardingText.sessionBody: [
      'Обучение сохранено. Проверьте сигналы и телефон для этого сеанса. Оставайтесь на месте.',
      'Оқыту сақталды. Осы сеанс үшін сигналдар мен телефонды тексеріңіз. Орныңызда қалыңыз.',
      'Training is saved. Check signals and your phone for this session. Stay stationary.',
    ],
    OnboardingText.sessionProgress: [
      'Проверка {current} из 3',
      '3 тексерудің {current}-тексеруі',
      'Check {current} of 3',
    ],
    OnboardingText.sessionSignals: [
      '1. Различаете ли вы сигналы?',
      '1. Сигналдарды ажыратасыз ба?',
      '1. Can you distinguish the signals?',
    ],
    OnboardingText.sessionPermission: [
      '2. Доступ к камере',
      '2. Камераға қолжетімділік',
      '2. Camera access',
    ],
    OnboardingText.sessionDevice: [
      '3. Камера и положение телефона',
      '3. Камера және телефон қалпы',
      '3. Camera and phone position',
    ],
    OnboardingText.sessionCheck: [
      'Проверить телефон',
      'Телефонды тексеру',
      'Check phone',
    ],
    OnboardingText.sessionCheckHint: [
      'Сначала подтвердите сигнал и доступ к камере. Затем подтвердите, что стоите на месте, и запустите проверку.',
      'Алдымен сигналды және камераға қолжетімділікті растаңыз. Содан соң орныңызда тұрғаныңызды растап, тексеруді бастаңыз.',
      'First confirm a signal and camera access. Then confirm you are stationary and start the check.',
    ],
    OnboardingText.sessionReady: [
      'Проверки этого сеанса пройдены. Доступен просмотр на месте; точность распознавания препятствий не подтверждена.',
      'Осы сеанс тексерулері өтті. Бір орында қарау қолжетімді; кедергілерді тану дәлдігі расталмады.',
      'Session checks passed. Stationary inspection is available; obstacle recognition accuracy is not established.',
    ],
    OnboardingText.sessionNotReady: [
      'Запуск доступен после проверок и подтверждения положения.',
      'Іске қосу тексерулерден және қалыпты растаудан кейін қолжетімді.',
      'Starting is available after checks and position confirmation.',
    ],
    OnboardingText.sessionSetup: [
      'Открыть настройки и обучение',
      'Баптаулар мен оқытуды ашу',
      'Open setup and training',
    ],
    OnboardingText.practiceRestart: [
      'Начать упражнения заново',
      'Жаттығуларды қайта бастау',
      'Restart exercises',
    ],
    OnboardingText.wrongStop: [
      'Сигнал «Стоп» требует остановиться. Выберите «Остановиться». Он не разрешает продолжать движение.',
      '«Тоқта» сигналы тоқтауды талап етеді. «Тоқтау» таңдаңыз. Ол қозғалысты жалғастыруға рұқсат бермейді.',
      'The stop signal requires stopping. Choose Stop. It does not authorize walking.',
    ],
    OnboardingText.wrongSide: [
      'Сообщение об объекте слева не подтверждает свободный путь. Выберите «Проверить пространство»; начинать движение по этому сигналу нельзя.',
      'Сол жақтағы нысан туралы хабар жолдың бос екенін растамайды. «Айналаны тексеру» таңдаңыз; бұл сигналмен қозғалуға болмайды.',
      'An object on the left does not establish a clear path. Choose Check surroundings; this signal does not authorize walking.',
    ],
    OnboardingText.wrongLost: [
      'Данные камеры потеряны. Остановитесь: приложение сейчас не может оценить сцену. Выберите «Остановиться».',
      'Камера деректері жоғалды. Тоқтаңыз: қолданба қазір көріністі бағалай алмайды. «Тоқтау» таңдаңыз.',
      'Camera data is lost. Stop: the app cannot assess the scene now. Choose Stop.',
    ],
    OnboardingText.wrongPause: [
      'В этом примере нужно включить паузу, затем явно возобновить работу. Нажмите «Пауза», затем «Возобновить».',
      'Бұл мысалда үзілісті қосып, содан кейін жұмысты қайта жалғастыру керек. «Үзіліс», содан кейін «Жалғастыру» басыңыз.',
      'This example requires pausing, then explicitly resuming. Choose Pause, then Resume.',
    ],
    OnboardingText.speechEngineUnavailable: [
      'Синтез речи недоступен. Проверьте, включён ли движок синтеза речи в системных настройках, затем повторите пример.',
      'Сөйлеу синтезі қолжетімсіз. Жүйе баптауларында сөйлеу синтезі қосылғанын тексеріп, мысалды қайталаңыз.',
      'Speech synthesis is unavailable. Check that a text-to-speech engine is enabled in system settings, then retry.',
    ],
    OnboardingText.speechInterrupted: [
      'Озвучка прервана, например звонком или сменой аудиоустройства. Завершите прерывание и повторите воспроизведение.',
      'Дауыс, мысалы қоңырау не аудио құрылғының ауысуынан, үзілді. Кедергіні аяқтап, қайта ойнатыңыз.',
      'Speech was interrupted, for example by a call or an audio device change. Resolve the interruption and retry.',
    ],
    OnboardingText.speechTimedOut: [
      'Озвучка не завершилась вовремя. Повторите её. При повторном отказе проверьте синтез речи в настройках.',
      'Дауыс уақытында аяқталмады. Қайталаңыз. Қайта істемесе, баптаулардағы сөйлеу синтезін тексеріңіз.',
      'Speech did not finish in time. Retry. If it fails again, check text-to-speech settings.',
    ],
    OnboardingText.speechFailed: [
      'Не удалось воспроизвести речь. Проверьте звук и синтез речи, затем повторите.',
      'Дауысты ойнату мүмкін болмады. Дыбыс пен сөйлеу синтезін тексеріп, қайталаңыз.',
      'Speech could not be played. Check audio and text-to-speech settings, then retry.',
    ],
    OnboardingText.speechSettings: [
      'Настройки синтеза речи',
      'Сөйлеу синтезі баптаулары',
      'Text-to-speech settings',
    ],
    OnboardingText.speechSettingsUnavailable: [
      'Не удалось открыть настройки. Откройте системные настройки и найдите «Синтез речи».',
      'Баптауларды ашу мүмкін болмады. Жүйе баптауларынан «Сөйлеу синтезі» табыңыз.',
      'Settings could not be opened. Open system settings and search for text-to-speech.',
    ],
    OnboardingText.checkSound: [
      'Если пример не слышен, проверьте громкость мультимедиа и выбранное аудиоустройство. Подтверждайте только различимый сигнал.',
      'Мысал естілмесе, мультимедиа дыбыс деңгейі мен таңдалған аудио құрылғыны тексеріңіз. Тек ажыратылатын сигналды растаңыз.',
      'If you cannot hear the sample, check media volume and the selected audio device. Confirm only a distinguishable signal.',
    ],
  };
}
