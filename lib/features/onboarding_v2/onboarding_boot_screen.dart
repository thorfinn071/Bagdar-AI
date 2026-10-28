import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/strings.dart';
import '../../services/settings_service.dart';
import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';
import 'onboarding_controller.dart';
import 'onboarding_copy.dart';
import 'onboarding_entry.dart';
import 'onboarding_gateway.dart';
import 'onboarding_screen.dart';
import 'onboarding_store.dart';

/// Owns no native runtime. Retries share one pending load, so a hanging
/// preferences request cannot accumulate concurrent initializations.
class OnboardingBootScreen extends StatefulWidget {
  final Future<OnboardingEntryFactory> Function()? load;
  final Duration timeout;
  final AppLanguage? language;
  const OnboardingBootScreen({
    super.key,
    this.load,
    this.timeout = const Duration(seconds: 15),
    this.language,
  });

  @override
  State<OnboardingBootScreen> createState() => _OnboardingBootScreenState();
}

class _OnboardingBootScreenState extends State<OnboardingBootScreen> {
  Future<OnboardingEntryFactory>? _pending;
  Widget? _home;
  Timer? _timer;
  int _generation = 0;
  OnboardingText? _failure;
  late final AppLanguage _language =
      widget.language ??
      switch (ui.PlatformDispatcher.instance.locale.languageCode) {
        'kk' => AppLanguage.kk,
        'en' => AppLanguage.en,
        _ => AppLanguage.ru,
      };

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final generation = ++_generation;
    _failure = null;
    _timer?.cancel();
    _timer = Timer(widget.timeout, () {
      if (!mounted || generation != _generation) return;
      ++_generation; // Late completion must leave the recovery screen visible.
      setState(() => _failure = OnboardingText.bootTimeout);
    });
    final source = _pending ??= Future.sync(
      widget.load ?? loadOnboardingV2Entry,
    );
    unawaited(
      source.then(
        (factory) {
          if (!mounted || generation != _generation) return;
          _timer?.cancel();
          try {
            if (widget.load == null) {
              bagdarThemeNotifier.value = Settings.instance.themeMode;
            }
            final home = factory();
            setState(() => _home = home);
          } catch (_) {
            _pending = null;
            setState(() => _failure = OnboardingText.bootError);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_pending, source)) _pending = null;
          if (!mounted || generation != _generation) return;
          _timer?.cancel();
          setState(() => _failure = OnboardingText.bootError);
        },
      ),
    );
  }

  void _trainWithoutSaving() {
    ++_generation;
    _timer?.cancel();
    setState(() {
      _home = OnboardingV2Screen(
        controller: OnboardingController(
          store: MemoryOnboardingStore(),
          gateway: UnavailableOnboardingGateway(),
          initialLanguage: _language,
          sessionOnly: true,
        ),
      );
    });
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_home != null) return _home!;
    final copy = OnboardingCopy(_language);
    return BagdarThemeScope(
      child: Semantics(
        localeForSubtree: Locale(_language.name),
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Bagdar AI'),
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          copy.t(_failure ?? OnboardingText.bootLoading),
                          style: BagdarTypography.title,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_failure == null)
                        const ExcludeSemantics(child: LinearProgressIndicator())
                      else ...[
                        Text(copy.t(OnboardingText.bootRecovery)),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => setState(_start),
                          child: Text(copy.t(OnboardingText.retry)),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _trainWithoutSaving,
                          child: Text(
                            copy.t(OnboardingText.storageSessionOnly),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
