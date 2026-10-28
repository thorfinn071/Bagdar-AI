import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagdar/features/onboarding_v2/onboarding_boot_screen.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_copy.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_entry.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_screen.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/sos_contact_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_v2_test.dart' show TestGateway;

class RetryStore implements OnboardingStore {
  bool fail = true;
  int writes = 0;
  Completer<ProgressLoad>? pending;
  bool failWrites = false;
  @override
  Future<ProgressLoad> load() async {
    if (pending != null) return pending!.future;
    if (fail) throw StateError('unreadable');
    return ProgressLoad(
      ProgressLoadStatus.loaded,
      OnboardingProgress(language: AppLanguage.kk),
    );
  }

  @override
  Future<void> save(OnboardingProgress progress) async {
    writes++;
    if (failWrites) throw StateError('write_failed');
  }
}

void main() {
  final captures = Platform.environment['BAGDAR_CAPTURE_DIR'];
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    AppStrings.setLanguage(AppLanguage.ru);
    SharedPreferences.setMockInitialValues({'untouched-consent': 'kept'});
  });

  Future<void> show(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(390, 844),
    double scale = 1,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? onboardingTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const Key('recovery-capture'),
            child: child!,
          ),
        ),
        home: home,
      ),
    );
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captures == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('recovery-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(captures).create(recursive: true);
      await File(
        '$captures/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  OnboardingController controller({
    OnboardingStore? store,
    TestGateway? gateway,
    AppLanguage language = AppLanguage.ru,
  }) => OnboardingController(
    store: store ?? MemoryOnboardingStore(),
    gateway: gateway ?? TestGateway(DateTime.now),
    initialLanguage: language,
  );

  testWidgets(
    'boot paints loading before load and creates entry only on success',
    (tester) async {
      final pending = Completer<OnboardingEntryFactory>();
      final c = controller();
      var factories = 0;
      await show(
        tester,
        OnboardingBootScreen(
          language: AppLanguage.ru,
          load: () => pending.future,
        ),
      );
      expect(
        find.text(
          const OnboardingCopy(AppLanguage.ru).t(OnboardingText.bootLoading),
        ),
        findsOneWidget,
      );
      expect(find.byType(OnboardingV2Screen), findsNothing);
      pending.complete(() {
        factories++;
        return OnboardingV2Screen(controller: c);
      });
      await tester.pumpAndSettle();
      expect(factories, 1);
      expect(find.byType(OnboardingV2Screen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('boot exception offers retry without resetting saved data', (
    tester,
  ) async {
    var attempts = 0;
    final c = controller();
    await show(
      tester,
      OnboardingBootScreen(
        language: AppLanguage.ru,
        load: () async {
          if (++attempts == 1) throw StateError('storage');
          return () => OnboardingV2Screen(controller: c);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        const OnboardingCopy(AppLanguage.ru).t(OnboardingText.bootError),
      ),
      findsOneWidget,
    );
    await tap(
      tester,
      const OnboardingCopy(AppLanguage.ru).t(OnboardingText.retry),
    );
    expect(attempts, 2);
    expect(
      (await SharedPreferences.getInstance()).getString('untouched-consent'),
      'kept',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'timeout ignores late load until explicit retry and shares pending request',
    (tester) async {
      final pending = Completer<OnboardingEntryFactory>();
      var loads = 0;
      var factories = 0;
      final c = controller();
      await show(
        tester,
        OnboardingBootScreen(
          language: AppLanguage.ru,
          timeout: const Duration(seconds: 2),
          load: () {
            loads++;
            return pending.future;
          },
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      pending.complete(() {
        factories++;
        return OnboardingV2Screen(controller: c);
      });
      await tester.pumpAndSettle();
      expect(factories, 0);
      expect(
        find.text(
          const OnboardingCopy(AppLanguage.ru).t(OnboardingText.bootTimeout),
        ),
        findsOneWidget,
      );
      await tap(
        tester,
        const OnboardingCopy(AppLanguage.ru).t(OnboardingText.retry),
      );
      expect(loads, 1);
      expect(factories, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsaved training never uses late factory or overwrites preferences',
    (tester) async {
      final pending = Completer<OnboardingEntryFactory>();
      var factories = 0;
      await show(
        tester,
        OnboardingBootScreen(
          language: AppLanguage.ru,
          timeout: const Duration(seconds: 1),
          load: () => pending.future,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tap(
        tester,
        const OnboardingCopy(
          AppLanguage.ru,
        ).t(OnboardingText.storageSessionOnly),
      );
      final c = tester
          .widget<OnboardingV2Screen>(find.byType(OnboardingV2Screen))
          .controller;
      expect(c.sessionOnly, isTrue);
      expect(c.admission, Admission.trainingRequired);
      await c.next();
      await c.requestCamera();
      await c.deviceCheck();
      expect(c.evidence.cameraAccess, isNot(CameraAccess.granted));
      expect(c.admission, Admission.trainingRequired);
      pending.complete(() {
        factories++;
        return OnboardingV2Screen(controller: controller());
      });
      await tester.pumpAndSettle();
      expect(factories, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('untouched-consent'),
        'kept',
      );
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          PreferencesOnboardingStore.key,
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('disposing boot ignores late completion', (tester) async {
    final pending = Completer<OnboardingEntryFactory>();
    var factories = 0;
    await show(tester, OnboardingBootScreen(load: () => pending.future));
    await tester.pumpWidget(const SizedBox());
    pending.complete(() {
      factories++;
      return OnboardingV2Screen(controller: controller());
    });
    await tester.pump();
    expect(factories, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry construction failure stays recoverable', (tester) async {
    await show(
      tester,
      OnboardingBootScreen(
        language: AppLanguage.ru,
        load: () async =>
            () => throw StateError('entry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        const OnboardingCopy(AppLanguage.ru).t(OnboardingText.bootError),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed progress write allows unsaved training without further writes',
    (tester) async {
      final store = RetryStore()
        ..fail = false
        ..failWrites = true;
      final c = controller(store: store);
      await show(tester, OnboardingV2Screen(controller: c));
      await tester.pumpAndSettle();
      await c.next();
      await tester.pumpAndSettle();
      expect(c.step, OnboardingStep.language);
      expect(c.message, OnboardingText.saveError);
      await tap(tester, c.copy.t(OnboardingText.storageSessionOnly));
      expect(c.sessionOnly, isTrue);
      expect(store.writes, 1);
      await c.next();
      expect(store.writes, 1);
      expect(c.admission, Admission.trainingRequired);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('voice task requires sample then human response at each stage', (
    tester,
  ) async {
    final c = controller();
    await show(tester, OnboardingV2Screen(controller: c));
    await c.goTo(OnboardingStep.feedback);
    await tester.pumpAndSettle();
    expect(find.text(c.copy.t(OnboardingText.stopVoice)), findsNothing);
    await tap(tester, c.copy.t(OnboardingText.ordinaryVoice));
    expect(c.evidence.criticalChannelVerified, isFalse);
    expect(c.evidence.ordinaryVoiceConfirmed, isFalse);
    await tap(tester, c.copy.t(OnboardingText.ordinaryHeard));
    expect(find.text(c.copy.t(OnboardingText.stopVoice)), findsOneWidget);
    expect(find.text(c.copy.t(OnboardingText.ordinaryVoice)), findsNothing);
    await tap(tester, c.copy.t(OnboardingText.stopVoice));
    expect(c.evidence.criticalChannelVerified, isFalse);
    await tap(tester, c.copy.t(OnboardingText.heard));
    expect(c.evidence.criticalChannelVerified, isTrue);
    await c.changeRate(0.75);
    await tester.pumpAndSettle();
    expect(c.evidence.ordinaryVoiceConfirmed, isFalse);
    expect(c.evidence.criticalChannelVerified, isFalse);
    expect(find.text(c.copy.t(OnboardingText.ordinaryVoice)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed voice offers haptics and playback alone never confirms', (
    tester,
  ) async {
    final gateway = TestGateway(DateTime.now)..audible = false;
    final c = controller(gateway: gateway);
    await show(tester, OnboardingV2Screen(controller: c));
    await c.goTo(OnboardingStep.feedback);
    await tester.pumpAndSettle();
    await tap(tester, c.copy.t(OnboardingText.ordinaryVoice));
    expect(c.evidence.ordinaryVoiceConfirmed, isFalse);
    expect(find.text(c.copy.t(OnboardingText.voiceMissing)), findsOneWidget);
    await tap(tester, c.copy.t(OnboardingText.useHaptic));
    await tap(tester, c.copy.t(OnboardingText.stopHaptic));
    expect(c.evidence.criticalChannelVerified, isFalse);
    await tap(tester, c.copy.t(OnboardingText.felt));
    expect(c.evidence.criticalChannelVerified, isTrue);
    c.suspend(background: true);
    expect(c.evidence.criticalChannelVerified, isFalse);
    expect(c.evidence.ordinaryVoiceConfirmed, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('helper cannot personally confirm an ordinary sample', (
    tester,
  ) async {
    final c = controller();
    await c.initialize();
    await c.selectMode(AccessMode.helper);
    await c.playVoice();
    c.confirmOrdinaryVoice(true);
    expect(c.evidence.ordinaryVoiceConfirmed, isFalse);
    c.dispose();
  });

  testWidgets(
    'unconfirmed signal and denied camera have explicit training labels',
    (tester) async {
      final c = controller();
      await show(tester, OnboardingV2Screen(controller: c));
      await c.goTo(OnboardingStep.feedback);
      await tester.pumpAndSettle();
      expect(
        find.text(c.copy.t(OnboardingText.trainingWithoutSignals)),
        findsOneWidget,
      );
      await c.goTo(OnboardingStep.camera);
      c.evidence.cameraAccess = CameraAccess.denied;
      await tester.pumpAndSettle();
      await tap(tester, c.copy.t(OnboardingText.cameraLater));
      expect(c.step, OnboardingStep.summary);
      expect(c.admission, isNot(Admission.inspectionOnly));
      expect(c.requiredStep, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('storage retry reads original progress without writes', (
    tester,
  ) async {
    final store = RetryStore();
    final c = controller(store: store);
    await show(tester, OnboardingV2Screen(controller: c));
    await tester.pumpAndSettle();
    expect(c.loadStatus, ProgressLoadStatus.corrupt);
    store.fail = false;
    await tap(tester, c.copy.t(OnboardingText.retry));
    expect(c.progress.language, AppLanguage.kk);
    expect(store.writes, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hanging progress load times out and unsaved recovery never writes',
    (tester) async {
      final store = RetryStore()..pending = Completer<ProgressLoad>();
      final c = controller(store: store);
      await show(tester, OnboardingV2Screen(controller: c));
      expect(c.loading, isTrue);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(c.loading, isFalse);
      await tap(tester, c.copy.t(OnboardingText.storageSessionOnly));
      expect(c.sessionOnly, isTrue);
      expect(store.writes, 0);
      store.pending!.complete(
        ProgressLoad(
          ProgressLoadStatus.loaded,
          OnboardingProgress(language: AppLanguage.en),
        ),
      );
      await tester.pump();
      expect(c.progress.language, AppLanguage.ru);
      expect(c.admission, Admission.trainingRequired);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in AppLanguage.values) {
    final copy = OnboardingCopy(language);
    testWidgets(
      'choice descriptions and selected state are spoken ${language.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = controller(language: language);
        await show(tester, OnboardingV2Screen(controller: c));
        await c.goTo(OnboardingStep.access);
        await tester.pumpAndSettle();
        final label =
            '${copy.t(OnboardingText.voice)}. ${copy.t(OnboardingText.voiceBody)}';
        final data = tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData();
        expect(data.flagsCollection.isChecked, ui.CheckedState.isTrue);
        expect(data.locale?.languageCode, language.name);
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );

    for (final landscape in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'recovery and signals ${language.name} landscape=$landscape scale=$scale',
          (tester) async {
            final size = landscape
                ? const Size(844, 390)
                : const Size(390, 844);
            final semantics = tester.ensureSemantics();
            await show(
              tester,
              OnboardingBootScreen(
                language: language,
                load: () async => throw StateError('storage'),
              ),
              size: size,
              scale: scale,
            );
            await tester.pumpAndSettle();
            expect(
              find.bySemanticsLabel(copy.t(OnboardingText.bootError)),
              findsOneWidget,
            );
            await tester.ensureVisible(
              find.text(copy.t(OnboardingText.storageSessionOnly)),
            );
            expect(
              tester
                  .getSize(
                    find.widgetWithText(
                      OutlinedButton,
                      copy.t(OnboardingText.storageSessionOnly),
                    ),
                  )
                  .height,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
            await capture(tester, 'boot-${language.name}-$landscape-$scale');
            final c = controller(language: language);
            await show(
              tester,
              OnboardingV2Screen(controller: c),
              size: size,
              scale: scale,
            );
            await c.goTo(OnboardingStep.feedback);
            await tester.pumpAndSettle();
            await tap(tester, copy.t(OnboardingText.useHaptic));
            expect(tester.takeException(), isNull);
            await capture(tester, 'signals-${language.name}-$landscape-$scale');
            await tester.ensureVisible(
              find.text(copy.t(OnboardingText.trainingWithoutSignals)),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }

    testWidgets(
      'contact form has labels and inline invalid-number recovery ${language.name}',
      (tester) async {
        AppStrings.setLanguage(language);
        var saves = 0;
        final semantics = tester.ensureSemantics();
        await show(
          tester,
          SosContactDialog(
            initialNumber: '',
            pickNumber: () async => throw StateError('denied'),
            saveNumber: (_) async {
              saves++;
              return false;
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(AppStrings.get('sos_contact_number')),
          findsOneWidget,
        );
        expect(
          tester
              .getSemantics(
                find.bySemanticsLabel(AppStrings.get('sos_contact_number')),
              )
              .getSemanticsData()
              .flagsCollection
              .isTextField,
          isTrue,
        );
        expect(
          find.bySemanticsLabel(AppStrings.get('sos_contact_pick')),
          findsOneWidget,
        );
        await tap(tester, AppStrings.get('save'));
        expect(saves, 0);
        expect(find.text(AppStrings.get('sos_invalid_number')), findsOneWidget);
        await tap(tester, AppStrings.get('sos_contact_pick'));
        expect(
          find.text(AppStrings.get('sos_contact_pick_failed')),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField), '+77771234567');
        await tap(tester, AppStrings.get('save'));
        expect(saves, 1);
        expect(find.byType(SosContactDialog), findsOneWidget);
        expect(
          find.text(AppStrings.get('sos_contact_save_failed')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
      },
    );

    for (final theme in [BagdarThemeName.light, BagdarThemeName.dark]) {
      for (final landscape in [false, true]) {
        testWidgets(
          'contact large text ${language.name} ${theme.name} landscape=$landscape',
          (tester) async {
            AppStrings.setLanguage(language);
            final semantics = tester.ensureSemantics();
            await show(
              tester,
              SosContactDialog(
                initialNumber: '',
                pickNumber: () async => null,
                saveNumber: (_) async => false,
              ),
              size: landscape ? const Size(844, 390) : const Size(390, 844),
              scale: 2,
              theme: BagdarTheme.buildMaterialTheme(theme),
            );
            await tester.pumpAndSettle();
            await tap(tester, AppStrings.get('save'));
            await tester.ensureVisible(
              find.text(AppStrings.get('sos_invalid_number')),
            );
            await tester.pumpAndSettle();
            final node = tester.getSemantics(
              find.bySemanticsLabel(AppStrings.get('sos_contact_pick')),
            );
            expect(node.getSemanticsData().locale?.languageCode, language.name);
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              'contact-${language.name}-${theme.name}-$landscape',
            );
            await tester.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'contact selection without number gives recovery and save is single flight',
    (tester) async {
      final pending = Completer<bool>();
      var saves = 0;
      await show(
        tester,
        SosContactDialog(
          initialNumber: '+77771234567',
          pickNumber: () async => '',
          saveNumber: (_) {
            saves++;
            return pending.future;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, AppStrings.get('sos_contact_pick'));
      expect(
        find.text(AppStrings.get('sos_contact_no_number')),
        findsOneWidget,
      );
      await tap(tester, AppStrings.get('save'));
      await tester.tap(find.text(AppStrings.get('save')));
      expect(saves, 1);
      await tester.pumpWidget(const SizedBox());
      pending.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
