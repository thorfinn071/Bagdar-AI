import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';
import '../widgets/bagdar_ui.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/haptic_service.dart';
import '../services/settings_codec.dart';
import '../services/tts_service.dart';

/// Scans a settings-backup QR (produced by `SettingsQrExportScreen`),
/// previews the payload via TTS, and applies it only after a deliberate
/// long-press confirmation — designed for blind users who cannot tap a
/// small "Apply" button precisely.
///
/// IMPORTANT: the host (CameraScreen) MUST release its own camera
/// controller before pushing this screen and reinitialise it after pop,
/// because mobile_scanner opens its own camera and Android only allows
/// one foreground camera consumer.
class SettingsQrImportScreen extends StatefulWidget {
  final TtsService tts;
  final bool Function()? canInteract;

  const SettingsQrImportScreen({
    super.key,
    required this.tts,
    this.canInteract,
  });

  @override
  State<SettingsQrImportScreen> createState() => _SettingsQrImportScreenState();
}

class _SettingsQrImportScreenState extends State<SettingsQrImportScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  String? _rawPayload;
  Map<String, dynamic>? _preview;
  bool _torchOn = false;
  bool _applying = false;
  bool _announcedReady = false;
  bool get _canInteract => mounted && (widget.canInteract?.call() ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canInteract || _announcedReady) return;
      _announcedReady = true;
      widget.tts.say(
        S.get('qr_import_aim_camera'),
        SpeechPriority.info,
        pan: 0.0,
      );
    });
  }

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_canInteract || _preview != null) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final preview = SettingsCodec.instance.peek(raw);
      if (preview == null) continue;

      _rawPayload = raw;
      setState(() => _preview = preview);
      HapticService.vibrate(const [0, 80, 60, 80]);
      _flashTorchPulse();
      _announcePreview(preview);
      unawaited(_scanner.stop());
      return;
    }
  }

  Future<void> _flashTorchPulse() async {
    try {
      await _scanner.toggleTorch();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!_canInteract) return;
      await _scanner.toggleTorch();
    } catch (_) {}
  }

  void _announcePreview(Map<String, dynamic> preview) {
    final parts = <String>[
      S.get('qr_import_found'),
      '${S.get('qr_import_version')} ${preview['v']}',
    ];
    final lang = preview['lang'];
    if (lang is int && lang >= 0 && lang < AppLanguage.values.length) {
      parts.add('${S.get('qr_import_lang')} ${AppLanguage.values[lang].name}');
    }
    final sr = preview['speech_rate'];
    if (sr is num) {
      parts.add('${S.get('qr_import_speech_rate')} ${sr.toStringAsFixed(1)}x');
    }
    final tv = preview['tts_volume'];
    if (tv is num) {
      parts.add('${S.get('qr_import_tts_volume')} ${(tv * 100).round()}%');
    }
    parts.add(S.get('qr_import_hold_to_apply'));
    widget.tts.say(parts.join('. '), SpeechPriority.info, pan: 0.0);
  }

  Future<void> _applyImport() async {
    if (!_canInteract || _applying) return;
    final raw = _rawPayload;
    if (raw == null) return;
    setState(() => _applying = true);
    HapticService.vibrate(const [0, 200, 100, 200]);
    final ok = await SettingsCodec.instance.importFromJson(raw);
    if (!mounted || !_canInteract) return;
    if (ok) {
      widget.tts.say(
        S.get('qr_import_applied'),
        SpeechPriority.warning,
        pan: 0.0,
      );
      Navigator.of(context).pop(true);
    } else {
      widget.tts.say(
        S.get('qr_import_failed'),
        SpeechPriority.warning,
        pan: 0.0,
      );
      setState(() {
        _applying = false;
        _rawPayload = null;
        _preview = null;
      });
      try {
        await _scanner.start();
      } catch (_) {}
    }
  }

  Future<void> _retry() async {
    if (!_canInteract) return;
    setState(() {
      _rawPayload = null;
      _preview = null;
    });
    try {
      await _scanner.start();
    } catch (_) {}
    if (!_canInteract) return;
    widget.tts.say(
      S.get('qr_import_aim_camera'),
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  Future<void> _toggleTorch() async {
    if (!_canInteract) return;
    try {
      await _scanner.toggleTorch();
      if (!_canInteract) return;
      setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return BagdarPage(
      title: S.get('qr_import_title'),
      subtitle: S.get(
        _preview == null ? 'qr_import_aim_hint' : 'qr_import_hold_to_apply',
      ),
      actions: [
        IconButton(
          tooltip: S.get('qr_import_torch'),
          icon: Icon(
            _torchOn ? Icons.flash_on_outlined : Icons.flash_off_outlined,
          ),
          onPressed: _toggleTorch,
        ),
      ],
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BagdarRadius.card),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _scanner, onDetect: _onDetect),
                IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.75,
                      heightFactor: 0.75,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: BagdarOverlay.signal(colors),
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(
                            BagdarRadius.control,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_preview != null) ...[
          const SizedBox(height: BagdarSpacing.m),
          _PreviewSheet(
            preview: _preview!,
            applying: _applying,
            onLongPressApply: _applyImport,
            onRetry: _retry,
          ),
        ],
      ],
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  final Map<String, dynamic> preview;
  final bool applying;
  final Future<void> Function() onLongPressApply;
  final VoidCallback onRetry;

  const _PreviewSheet({
    required this.preview,
    required this.applying,
    required this.onLongPressApply,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => BagdarCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '${S.get('qr_import_found')} v${preview['v']}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: BagdarSpacing.s),
        ..._summaryLines(preview).map(
          (line) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(line),
          ),
        ),
        const SizedBox(height: BagdarSpacing.m),
        _LongPressApplyButton(
          applying: applying,
          onConfirmed: onLongPressApply,
        ),
        const SizedBox(height: BagdarSpacing.s),
        OutlinedButton(
          onPressed: applying ? null : onRetry,
          child: Text(S.get('qr_import_retry')),
        ),
      ],
    ),
  );

  List<String> _summaryLines(Map<String, dynamic> p) {
    final lines = <String>[];
    final lang = p['lang'];
    if (lang is int && lang >= 0 && lang < AppLanguage.values.length) {
      lines.add('${S.get('qr_import_lang')}: ${AppLanguage.values[lang].name}');
    }
    final sr = p['speech_rate'];
    if (sr is num) {
      lines.add('${S.get('qr_import_speech_rate')}: ${sr.toStringAsFixed(2)}x');
    }
    final tv = p['tts_volume'];
    if (tv is num) {
      lines.add('${S.get('qr_import_tts_volume')}: ${(tv * 100).round()}%');
    }
    final ev = p['earcon_volume'];
    if (ev is num) {
      lines.add('${S.get('qr_import_earcon_volume')}: ${(ev * 100).round()}%');
    }
    return lines;
  }
}

/// Apply button that requires a deliberate 1.5s hold. The 500 ms default
/// long-press is far too easy to trigger accidentally with shaky hands;
/// 1.5 s gives the user time to abort by lifting the finger.
class _LongPressApplyButton extends StatefulWidget {
  final bool applying;
  final Future<void> Function() onConfirmed;

  const _LongPressApplyButton({
    required this.applying,
    required this.onConfirmed,
  });

  @override
  State<_LongPressApplyButton> createState() => _LongPressApplyButtonState();
}

class _LongPressApplyButtonState extends State<_LongPressApplyButton> {
  static const Duration _kHold = Duration(milliseconds: 1500);
  static const Duration _kTickPeriod = Duration(milliseconds: 100);

  Timer? _holdTimer;
  Timer? _tickTimer;
  DateTime? _pressStartedAt;
  double _progress = 0.0;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  void _onDown() {
    if (widget.applying) return;
    HapticService.vibrate(const [0, 30]);
    _pressStartedAt = DateTime.now();
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    _holdTimer = Timer(_kHold, () async {
      _stopTicker();
      if (!mounted) return;
      setState(() => _progress = 1.0);
      await widget.onConfirmed();
    });
    _tickTimer = Timer.periodic(_kTickPeriod, (_) => _updateProgress());
  }

  void _onUpOrCancel() {
    if (_holdTimer == null) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _stopTicker();
    if (!mounted) return;
    setState(() => _progress = 0.0);
  }

  void _updateProgress() {
    final start = _pressStartedAt;
    if (start == null) return;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final p = (elapsed / _kHold.inMilliseconds).clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() => _progress = p);
  }

  void _stopTicker() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.applying;
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      button: true,
      label: S.get('qr_import_hold_to_apply'),
      enabled: !disabled,
      child: GestureDetector(
        onTapDown: (_) => _onDown(),
        onTapUp: (_) => _onUpOrCancel(),
        onTapCancel: _onUpOrCancel,
        child: Stack(
          children: [
            Container(
              constraints: const BoxConstraints(
                minHeight: BagdarSpacing.tapMinimum,
              ),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: disabled ? colors.disabledFill : colors.accentPrimary,
                borderRadius: BorderRadius.circular(BagdarRadius.control),
              ),
              child: Center(
                child: Text(
                  disabled
                      ? S.get('qr_import_applying')
                      : S.get('qr_import_long_press'),
                  style: TextStyle(
                    color: colors.accentOnPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(BagdarRadius.control),
                  bottomRight: Radius.circular(BagdarRadius.control),
                ),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colors.accentOnPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
