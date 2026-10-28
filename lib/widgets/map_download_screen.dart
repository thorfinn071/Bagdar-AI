import 'package:flutter/material.dart';

import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';
import 'bagdar_ui.dart';

import '../models/map_package.dart';
import '../models/strings.dart';
import '../services/map_package_manager.dart';

class MapDownloadScreen extends StatefulWidget {
  final MapPackageManager manager;

  const MapDownloadScreen({super.key, required this.manager});

  @override
  State<MapDownloadScreen> createState() => _MapDownloadScreenState();
}

class _MapDownloadScreenState extends State<MapDownloadScreen> {
  final Map<String, double> _progress = {};
  final Map<String, bool> _downloading = {};

  void Function(String, double)? _prevProgress;
  void Function(String)? _prevComplete;
  void Function(String, String)? _prevError;

  MapPackageManager get _mgr => widget.manager;

  @override
  void initState() {
    super.initState();
    _prevProgress = _mgr.onDownloadProgress;
    _prevComplete = _mgr.onDownloadComplete;
    _prevError = _mgr.onDownloadError;

    _mgr.onDownloadProgress = (cityId, progress) {
      if (mounted) setState(() => _progress[cityId] = progress);
    };
    _mgr.onDownloadComplete = (cityId) {
      if (mounted) {
        setState(() {
          _downloading[cityId] = false;
          _progress.remove(cityId);
        });
      }
      _prevComplete?.call(cityId);
    };
    _mgr.onDownloadError = (cityId, error) {
      if (mounted) {
        setState(() {
          _downloading[cityId] = false;
          _progress.remove(cityId);
        });
        final msg = error == 'insufficient_space'
            ? S.get('nav_disk_space')
            : '${S.get('nav_download_failed')} $error';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      _prevError?.call(cityId, error);
    };
  }

  List<MapPackage> get _cities {
    if (_mgr.available.isNotEmpty) return _mgr.available;
    return const [
      MapPackage(
        cityId: 'astana',
        name: 'Астана',
        nameKk: 'Астана',
        sizeBytes: 20000000,
      ),
      MapPackage(
        cityId: 'almaty',
        name: 'Алматы',
        nameKk: 'Алматы',
        sizeBytes: 30000000,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BagdarPage(
      title: S.get('nav_select_city'),
      children: [for (final city in _cities) _buildCityCard(city)],
    );
  }

  Widget _buildCityCard(MapPackage pkg) {
    final colors = BagdarTheme.colorsOf(context);
    final installed = _mgr.isInstalled(pkg.cityId);
    final isDownloading = _downloading[pkg.cityId] == true;
    final progress = _progress[pkg.cityId];
    final localPkg = _mgr.getInstalled(pkg.cityId);
    final hasUpdate = localPkg != null && pkg.version > localPkg.version;

    return Semantics(
      label:
          '${pkg.name}. ${installed ? S.get('nav_offline_ready') : S.get('nav_download_map')}',
      button: true,
      child: Card(
        color: colors.surfaceElevated,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(BagdarSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    installed ? Icons.check_circle : Icons.cloud_download,
                    color: installed
                        ? colors.stateSuccess
                        : colors.textSecondary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pkg.name,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (pkg.sizeBytes > 0)
                          Text(
                            '${pkg.sizeMb} MB',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasUpdate)
                    Icon(Icons.update, color: colors.stateWarning, size: 24),
                ],
              ),
              if (isDownloading && progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: colors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colors.accentPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${S.get('nav_download_progress')}: ${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: colors.textSecondary, fontSize: 16),
                ),
              ],
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!installed && !isDownloading)
                    SizedBox(
                      child: ElevatedButton.icon(
                        onPressed: () => _download(pkg),
                        icon: const Icon(Icons.download),
                        label: Text(S.get('nav_download_map')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.accentPrimary,
                          foregroundColor: colors.accentOnPrimary,
                        ),
                      ),
                    ),
                  if (installed && !isDownloading) ...[
                    if (hasUpdate)
                      SizedBox(
                        child: ElevatedButton.icon(
                          onPressed: () => _download(pkg),
                          icon: const Icon(Icons.update),
                          label: Text(S.get('nav_map_update')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accentPrimary,
                            foregroundColor: colors.accentOnPrimary,
                          ),
                        ),
                      ),
                    if (hasUpdate) const SizedBox(height: 8),
                    SizedBox(
                      child: OutlinedButton.icon(
                        onPressed: () => _delete(pkg),
                        icon: Icon(
                          Icons.delete_outline,
                          color: colors.stateDanger,
                        ),
                        label: Text(
                          S.get('nav_delete_map'),
                          style: TextStyle(color: colors.stateDanger),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.stateDanger),
                        ),
                      ),
                    ),
                  ],
                  if (isDownloading)
                    SizedBox(
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textSecondary,
                          ),
                        ),
                        label: Text(S.get('nav_downloading_map')),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mgr.onDownloadProgress = _prevProgress;
    _mgr.onDownloadComplete = _prevComplete;
    _mgr.onDownloadError = _prevError;
    super.dispose();
  }

  void _download(MapPackage pkg) {
    setState(() => _downloading[pkg.cityId] = true);
    _mgr.downloadCity(pkg.cityId);
  }

  void _delete(MapPackage pkg) {
    _mgr.deleteCity(pkg.cityId).then((ok) {
      if (mounted) {
        setState(() {});
        if (ok) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(S.get('nav_map_deleted'))));
        }
      }
    });
  }
}
