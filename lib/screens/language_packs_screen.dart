import 'dart:async';

import 'package:flutter/material.dart';

import '../models/language_pack.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/haptic_service.dart';
import '../services/language_pack_manager.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';

/// Settings screen for managing optional Kazakh-language packs and toggling
/// the `enableKazakhStackV2` feature flag.
///
/// Designed to be operable by both sighted helpers and blind primary users:
/// - All buttons have explicit Semantics labels with size + state hints.
/// - Entry announces purpose via TTS so a blind user knows where they are.
/// - Per-pack download progress is announced via TTS (not just visual).
/// - Destructive actions (delete) require a confirmation dialog.
///
/// Pushed from `camera_screen.dart` via voice command
/// "language packs" / "тіл пакеттері" / "языковые пакеты" or from
/// onboarding via the kk-language download prompt's "later" path.
class LanguagePacksScreen extends StatefulWidget {
  final TtsService tts;

  const LanguagePacksScreen({super.key, required this.tts});

  @override
  State<LanguagePacksScreen> createState() => _LanguagePacksScreenState();
}

class _LanguagePacksScreenState extends State<LanguagePacksScreen> {
  final LanguagePackManager _pm = LanguagePackManager.instance;

  bool _busy = false;
  bool _refreshing = false;
  String? _downloadingPackId;
  double _downloadProgress = 0.0;

  late bool _v2Enabled;

  @override
  void initState() {
    super.initState();
    _v2Enabled = Settings.instance.enableKazakhStackV2;

    _pm.onDownloadProgress = (packId, progress) {
      if (!mounted) return;
      if (packId != _downloadingPackId) return;
      setState(() => _downloadProgress = progress);
    };
    _pm.onDownloadComplete = (packId) {
      if (!mounted) return;
      setState(() {
        _downloadingPackId = null;
        _downloadProgress = 0.0;
      });
      widget.tts.say(
        S.get('lang_pack_install_complete'),
        SpeechPriority.info,
        pan: 0.0,
      );
      HapticService.vibrate(const [0, 80, 60, 80]);
    };
    _pm.onDownloadError = (packId, error) {
      if (!mounted) return;
      setState(() {
        _downloadingPackId = null;
        _downloadProgress = 0.0;
      });
      widget.tts.say(
        S.get('lang_pack_install_failed'),
        SpeechPriority.warning,
        pan: 0.0,
      );
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.tts.say(
        S.get('lang_packs_screen_intro'),
        SpeechPriority.info,
        pan: 0.0,
      );
      
      
      if (_pm.manifestNeedsRefresh) {
        unawaited(_refreshManifest(announceSuccess: false));
      }
    });
  }

  @override
  void dispose() {
    _pm.onDownloadProgress = null;
    _pm.onDownloadComplete = null;
    _pm.onDownloadError = null;
    super.dispose();
  }

  Future<void> _toggleV2(bool next) async {
    await Settings.instance.setEnableKazakhStackV2(next);
    if (!mounted) return;
    setState(() => _v2Enabled = next);
    widget.tts.say(
      next
          ? S.get('lang_packs_v2_enabled')
          : S.get('lang_packs_v2_disabled'),
      SpeechPriority.info,
      pan: 0.0,
    );
    HapticService.vibrate(const [0, 50]);
  }

  Future<void> _refreshManifest({bool announceSuccess = true}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final ok = await _pm.fetchManifest();
    if (!mounted) return;
    setState(() => _refreshing = false);
    if (ok && announceSuccess) {
      widget.tts.say(
        S.get('lang_packs_refresh_done'),
        SpeechPriority.info,
        pan: 0.0,
      );
    } else if (!ok) {
      widget.tts.say(
        S.get('lang_packs_refresh_failed'),
        SpeechPriority.warning,
        pan: 0.0,
      );
    }
  }

  Future<void> _installPack(LanguagePack pack) async {
    if (_busy || _downloadingPackId != null) return;
    setState(() {
      _busy = true;
      _downloadingPackId = pack.packId;
      _downloadProgress = 0.0;
    });
    widget.tts.say(
      S.get('lang_pack_downloading'),
      SpeechPriority.info,
      pan: 0.0,
    );
    final ok = await _pm.downloadPack(pack.packId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      
    }
  }

  Future<void> _deletePack(LanguagePack pack) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(
        packName: _packDisplayName(pack),
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await _pm.deletePack(pack.packId);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.tts.say(
      S.get('lang_packs_delete'),
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  String _packDisplayName(LanguagePack pack) {
    switch (AppStrings.current) {
      case AppLanguage.kk:
        return pack.nameKk.isNotEmpty ? pack.nameKk : pack.name;
      case AppLanguage.en:
        return pack.nameEn.isNotEmpty ? pack.nameEn : pack.name;
      case AppLanguage.ru:
        return pack.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _pm.available;
    final installedIds = {
      for (final p in _pm.installed)
        if (p.installed) p.packId,
    };
    final merged = [
      ...available,
      
      
      ..._pm.installed.where(
        (p) => p.installed && !available.any((a) => a.packId == p.packId),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          S.get('lang_packs_screen_title'),
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: S.get('lang_packs_refresh'),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.cyanAccent,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.cyanAccent),
            onPressed: _refreshing ? null : _refreshManifest,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _V2ToggleCard(
              enabled: _v2Enabled,
              onChanged: _toggleV2,
            ),
            const SizedBox(height: 16),
            if (merged.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  S.get('lang_packs_no_packs'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
              )
            else
              ...merged.map(
                (p) => _PackTile(
                  pack: p,
                  installed: installedIds.contains(p.packId),
                  displayName: _packDisplayName(p),
                  downloading: _downloadingPackId == p.packId,
                  downloadProgress: _downloadProgress,
                  busy: _busy,
                  onInstall: () => _installPack(p),
                  onDelete: () => _deletePack(p),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[850],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(S.get('lang_packs_close')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _V2ToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _V2ToggleCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: enabled,
      label: S.get('lang_packs_v2_toggle_label'),
      hint: S.get('lang_packs_v2_toggle_desc'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.get('lang_packs_v2_toggle_label'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.get('lang_packs_v2_toggle_desc'),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: Colors.cyanAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  final LanguagePack pack;
  final bool installed;
  final String displayName;
  final bool downloading;
  final double downloadProgress;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onDelete;

  const _PackTile({
    required this.pack,
    required this.installed,
    required this.displayName,
    required this.downloading,
    required this.downloadProgress,
    required this.busy,
    required this.onInstall,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final installedPack = LanguagePackManager.instance.getInstalled(pack.packId);
    final hasUpdate = installed &&
        installedPack != null &&
        pack.version > installedPack.version;
    final sizeLabel = S
        .get('lang_packs_size_mb')
        .replaceFirst('{size}', pack.sizeMb);
    final stateLabel = installed
        ? S.get('lang_packs_installed')
        : S.get('lang_packs_not_installed');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$stateLabel • $sizeLabel',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: downloadProgress > 0 ? downloadProgress : null,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            ),
            const SizedBox(height: 4),
            Text(
              '${(downloadProgress * 100).round()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (!installed)
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: busy ? null : onInstall,
                      child: Text(S.get('lang_packs_install')),
                    ),
                  ),
                if (installed && hasUpdate)
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: busy ? null : onInstall,
                      child: Text(S.get('lang_packs_update')),
                    ),
                  ),
                if (installed) ...[
                  if (hasUpdate) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: busy ? null : onDelete,
                      child: Text(S.get('lang_packs_delete')),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeleteConfirmDialog extends StatelessWidget {
  final String packName;

  const _DeleteConfirmDialog({required this.packName});

  @override
  Widget build(BuildContext context) {
    final body = S
        .get('lang_packs_delete_confirm')
        .replaceFirst('{name}', packName);
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      title: Text(
        S.get('lang_packs_delete'),
        style: const TextStyle(color: Colors.white),
      ),
      content: Text(
        body,
        style: const TextStyle(color: Colors.white70, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            S.get('lang_packs_close'),
            style: const TextStyle(color: Colors.white60),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            S.get('lang_packs_delete'),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }
}
