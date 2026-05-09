import 'package:flutter/material.dart';
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

  const SettingsQrExportScreen({super.key, required this.tts});

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
      widget.tts.say(
        S.get('qr_export_ready'),
        SpeechPriority.info,
        pan: 0.0,
      );
      HapticService.vibrate(const [0, 80]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          S.get('qr_export_title'),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                S.get('qr_export_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Semantics(
                    label: S.get('qr_export_semantics'),
                    image: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: _payload,
                        version: QrVersions.auto,
                        size: 280,
                        gapless: false,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                S.get('qr_export_footer'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(S.get('qr_dismiss')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
