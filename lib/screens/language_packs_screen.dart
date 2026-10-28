import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';
import '../widgets/bagdar_ui.dart';

import '../core/core_feature_policy.dart';
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
  final bool Function()? canInteract;
  final Future<bool?> Function(BuildContext, WidgetBuilder)?
  showDeleteConfirmation;

  const LanguagePacksScreen({
    super.key,
    required this.tts,
    this.showDeleteConfirmation,
    this.canInteract,
  });

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
  bool get _canInteract => mounted && (widget.canInteract?.call() ?? true);

  @override
  void initState() {
    super.initState();
    _v2Enabled = Settings.instance.enableKazakhStackV2;

    _pm.onDownloadProgress = (packId, progress) {
      if (!_canInteract) return;
      if (packId != _downloadingPackId) return;
      setState(() => _downloadProgress = progress);
    };
    _pm.onDownloadComplete = (packId) {
      if (!_canInteract) return;
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
      if (!_canInteract) return;
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
      if (!_canInteract) return;
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
    if (!_canInteract) return;
    if (!CoreFeaturePolicy.current.mayInitialize(CoreFeature.kazakhStackV2)) {
      return;
    }
    await Settings.instance.setEnableKazakhStackV2(next);
    if (!_canInteract) return;
    setState(() => _v2Enabled = next);
    widget.tts.say(
      next ? S.get('lang_packs_v2_enabled') : S.get('lang_packs_v2_disabled'),
      SpeechPriority.info,
      pan: 0.0,
    );
    HapticService.vibrate(const [0, 50]);
  }

  Future<void> _refreshManifest({bool announceSuccess = true}) async {
    if (!_canInteract || _refreshing) return;
    setState(() => _refreshing = true);
    final ok = await _pm.fetchManifest();
    if (!_canInteract) return;
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
    if (!_canInteract || _busy || _downloadingPackId != null) return;
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
    if (!_canInteract) return;
    setState(() => _busy = false);
    if (!ok) {}
  }

  Future<void> _deletePack(LanguagePack pack) async {
    if (!_canInteract || _busy) return;
    Widget confirmation(BuildContext ctx) =>
        _DeleteConfirmDialog(packName: _packDisplayName(pack));
    final Future<bool?> pendingConfirmation;
    if (widget.showDeleteConfirmation != null) {
      pendingConfirmation = widget.showDeleteConfirmation!(
        context,
        confirmation,
      );
    } else {
      pendingConfirmation = showDialog<bool>(
        context: context,
        builder: confirmation,
      );
    }
    final confirmed = await pendingConfirmation;
    if (!_canInteract || confirmed != true) return;
    setState(() => _busy = true);
    await _pm.deletePack(pack.packId);
    if (!_canInteract) return;
    setState(() => _busy = false);
    widget.tts.say(S.get('lang_packs_delete'), SpeechPriority.info, pan: 0.0);
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
    final colors = BagdarTheme.colorsOf(context);
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

    return BagdarPage(
      title: S.get('lang_packs_screen_title'),
      actions: [
        IconButton(
          tooltip: S.get('lang_packs_refresh'),
          icon: _refreshing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accentPrimary,
                  ),
                )
              : Icon(Icons.refresh, color: colors.accentPrimary),
          onPressed: _refreshing ? null : _refreshManifest,
        ),
      ],
      children: [
        if (CoreFeaturePolicy.current.mayShowInUi(
          CoreFeature.kazakhStackV2,
        )) ...[
          _V2ToggleCard(enabled: _v2Enabled, onChanged: _toggleV2),
          const SizedBox(height: 16),
        ],
        if (merged.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              S.get('lang_packs_no_packs'),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 16),
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
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(S.get('lang_packs_close')),
          ),
        ),
      ],
    );
  }
}

class _V2ToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _V2ToggleCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Semantics(
      toggled: enabled,
      label: S.get('lang_packs_v2_toggle_label'),
      hint: S.get('lang_packs_v2_toggle_desc'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(BagdarRadius.card),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.get('lang_packs_v2_toggle_label'),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    S.get('lang_packs_v2_toggle_desc'),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 16,
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
              activeThumbColor: colors.accentPrimary,
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
    final colors = BagdarTheme.colorsOf(context);
    final installedPack = LanguagePackManager.instance.getInstalled(
      pack.packId,
    );
    final hasUpdate =
        installed &&
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
      padding: const EdgeInsets.all(BagdarSpacing.m),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(BagdarRadius.card),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$stateLabel • $sizeLabel',
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: downloadProgress > 0 ? downloadProgress : null,
              backgroundColor: colors.divider,
              valueColor: AlwaysStoppedAnimation(colors.accentPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '${(downloadProgress * 100).round()}%',
              style: TextStyle(color: colors.textSecondary, fontSize: 16),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!installed)
                  SizedBox(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentPrimary,
                        foregroundColor: colors.accentOnPrimary,
                      ),
                      onPressed: busy ? null : onInstall,
                      child: Text(S.get('lang_packs_install')),
                    ),
                  ),
                if (installed && hasUpdate)
                  SizedBox(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accentPrimary,
                        foregroundColor: colors.accentOnPrimary,
                      ),
                      onPressed: busy ? null : onInstall,
                      child: Text(S.get('lang_packs_update')),
                    ),
                  ),
                if (installed) ...[
                  if (hasUpdate) const SizedBox(height: 8),
                  SizedBox(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.stateDanger),
                        foregroundColor: colors.stateDanger,
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
    final colors = BagdarTheme.colorsOf(context);
    final body = S
        .get('lang_packs_delete_confirm')
        .replaceFirst('{name}', packName);
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Text(
        S.get('lang_packs_delete'),
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Text(
        body,
        style: TextStyle(color: colors.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            S.get('lang_packs_close'),
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            S.get('lang_packs_delete'),
            style: TextStyle(color: colors.stateDanger),
          ),
        ),
      ],
    );
  }
}
