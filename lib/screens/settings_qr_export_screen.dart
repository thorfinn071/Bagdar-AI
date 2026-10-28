import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/bagdar_tokens.dart';
import '../widgets/bagdar_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/haptic_service.dart';
import '../services/settings_codec.dart';
import '../services/tts_service.dart';

/// Renders a QR code that contains the user's accessibility settings so a
/// sighted helper can scan it from another device. Payload built by
/// [SettingsCodec] — never includes PII (e.g. SOS contact).
///
/// On open the screen announces "QR ready, show it to your helper" via
/// TTS so a blind primary user understands what is on screen.
class SettingsQrExportScreen extends StatefulWidget {
  final TtsService tts;
  final bool Function()? canInteract;

  const SettingsQrExportScreen({
    super.key,
    required this.tts,
    this.canInteract,
  });

  @override
  State<SettingsQrExportScreen> createState() => _SettingsQrExportScreenState();
}

class _SettingsQrExportScreenState extends State<SettingsQrExportScreen> {
  late final String _payload;

  @override
  void initState() {
    super.initState();
    _payload = SettingsCodec.instance.exportToJson();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(widget.canInteract?.call() ?? true)) return;
      widget.tts.say(S.get('qr_export_ready'), SpeechPriority.info, pan: 0.0);
      HapticService.vibrate(const [0, 80]);
    });
  }

  @override
  Widget build(BuildContext context) => BagdarPage(
    title: S.get('qr_export_title'),
    subtitle: S.get('qr_export_hint'),
    children: [
      Center(
        child: Semantics(
          label: S.get('qr_export_semantics'),
          image: true,
          child: LayoutBuilder(
            builder: (context, bounds) => Container(
              padding: const EdgeInsets.all(BagdarSpacing.m),
              decoration: BoxDecoration(
                // QR quiet zone stays white in every theme for scanning.
                color: Colors.white,
                borderRadius: BorderRadius.circular(BagdarRadius.card),
              ),
              child: QrImageView(
                data: _payload,
                version: QrVersions.auto,
                size: math.min(280, bounds.maxWidth - 32),
                backgroundColor: Colors.white,
                gapless: false,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: BagdarSpacing.l),
      Text(
        S.get('qr_export_footer'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: BagdarSpacing.l),
      FilledButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: Text(S.get('qr_dismiss')),
      ),
    ],
  );
}
