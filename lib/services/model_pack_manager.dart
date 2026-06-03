import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'device_capability.dart';
import 'field_logger.dart';

/// Metadata for a regional model pack (e.g. livestock YOLO labels /
/// weights for Central Asian environments).
class ModelPack {
  final String id;
  final String name;
  final String region;
  final String modelFileName;
  final String labelsFileName;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final int version;
  final List<String> classes;

  const ModelPack({
    required this.id,
    required this.name,
    required this.region,
    required this.modelFileName,
    required this.labelsFileName,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.version,
    required this.classes,
  });

  factory ModelPack.fromJson(Map<String, dynamic> json) => ModelPack(
        id: json['id'] as String,
        name: json['name'] as String,
        region: json['region'] as String? ?? '',
        modelFileName: json['modelFile'] as String,
        labelsFileName: json['labelsFile'] as String,
        downloadUrl: json['url'] as String,
        sha256: json['sha256'] as String,
        sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
        version: (json['version'] as num?)?.toInt() ?? 1,
        classes: (json['classes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'region': region,
        'modelFile': modelFileName,
        'labelsFile': labelsFileName,
        'url': downloadUrl,
        'sha256': sha256,
        'size': sizeBytes,
        'version': version,
        'classes': classes,
      };
}

/// Installation state of a model pack on disk.
enum ModelPackStatus { notInstalled, downloading, installed, failed }

/// Installed model pack record.
class InstalledModelPack {
  final ModelPack pack;
  final String localModelPath;
  final String localLabelsPath;
  final ModelPackStatus status;

  const InstalledModelPack({
    required this.pack,
    required this.localModelPath,
    required this.localLabelsPath,
    required this.status,
  });
}

/// Manages optional regional YOLO model packs (e.g. livestock-enhanced
/// models for Central Asian bazaar/rural environments).
///
/// Phase 3 — Direction 9 expansion. Follows the existing
/// `LanguagePackManager` / `MapPackageManager` patterns: manifest,
/// download, SHA-256 verification, free-space gate, local install path,
/// graceful fallback.
///
/// Risk gate: Model swap must be atomic and reversible. Missing optional
/// models must not break app startup. The bundled `yolov8n_int8.tflite`
/// is always the fallback.
class ModelPackManager {
  ModelPackManager._();

  static final ModelPackManager instance = ModelPackManager._();

  static const String _kManifestUrl = String.fromEnvironment(
    'VG_MODEL_MANIFEST_URL',
    defaultValue: '',
  );

  static const String _kInstalledFileName = 'model_packs_installed.json';
  static const int _kMinFreeSpaceMb = 100;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 120),
  ));

  List<ModelPack>? _manifest;
  final Map<String, InstalledModelPack> _installed = {};
  String? _activePackId;
  File? _installedFile;

  String? get activePackId => _activePackId;

  List<ModelPack> get availablePacks => _manifest ?? const [];

  InstalledModelPack? get activePack =>
      _activePackId != null ? _installed[_activePackId] : null;

  bool isInstalled(String packId) =>
      _installed[packId]?.status == ModelPackStatus.installed;

  /// Load the installed packs index from disk.
  Future<void> init() async {
    try {
      final file = await _getInstalledFile();
      if (file.existsSync()) {
        final raw = await file.readAsString();
        final list = jsonDecode(raw) as List<dynamic>;
        for (final entry in list) {
          if (entry is Map<String, dynamic>) {
            final pack = ModelPack.fromJson(
                entry['pack'] as Map<String, dynamic>);
            final localModel = entry['localModel'] as String? ?? '';
            final localLabels = entry['localLabels'] as String? ?? '';
            _installed[pack.id] = InstalledModelPack(
              pack: pack,
              localModelPath: localModel,
              localLabelsPath: localLabels,
              status: ModelPackStatus.installed,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('ModelPackManager.init error: $e');
    }
  }

  /// Fetch the remote manifest of available model packs. Network
  /// optional — returns an empty list silently on failure.
  Future<List<ModelPack>> fetchManifest() async {
    if (_kManifestUrl.isEmpty) return const [];
    try {
      final response = await _dio.get<String>(_kManifestUrl);
      if (response.statusCode == 200 && response.data != null) {
        final list = jsonDecode(response.data!) as List<dynamic>;
        _manifest = list
            .whereType<Map<String, dynamic>>()
            .map(ModelPack.fromJson)
            .toList();
        return _manifest!;
      }
    } catch (e) {
      debugPrint('ModelPackManager.fetchManifest error: $e');
    }
    return const [];
  }

  /// Download and install a model pack. Verifies SHA-256 hash after
  /// download. Returns the installation record, or null on failure.
  Future<InstalledModelPack?> install(
    ModelPack pack, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final hw = await DeviceCapabilityProbe.readHardwareCapabilities();
      if (hw.freeStorageMb >= 0 && hw.freeStorageMb < _kMinFreeSpaceMb) {
        FieldLogger.instance.log('model_pack_no_space', {
          'pack': pack.id,
          'freeMb': hw.freeStorageMb,
        });
        return null;
      }
    } catch (_) {}

    try {
      final dir = await _packDir();
      final modelFile = File('${dir.path}/${pack.modelFileName}');
      final labelsFile = File('${dir.path}/${pack.labelsFileName}');

      
      await _dio.download(
        pack.downloadUrl,
        modelFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      
      if (pack.sha256.isNotEmpty) {
        final bytes = await modelFile.readAsBytes();
        final hash = sha256.convert(bytes).toString();
        if (hash != pack.sha256) {
          FieldLogger.instance.log('model_pack_hash_mismatch', {
            'pack': pack.id,
            'expected': pack.sha256,
            'actual': hash,
          });
          try {
            await modelFile.delete();
          } catch (_) {}
          return null;
        }
      }

      
      await labelsFile.writeAsString(pack.classes.join('\n'), flush: true);

      final installed = InstalledModelPack(
        pack: pack,
        localModelPath: modelFile.path,
        localLabelsPath: labelsFile.path,
        status: ModelPackStatus.installed,
      );
      _installed[pack.id] = installed;
      await _saveInstalled();

      FieldLogger.instance.log('model_pack_installed', {
        'pack': pack.id,
        'version': pack.version,
        'classes': pack.classes.length,
      });

      return installed;
    } catch (e) {
      FieldLogger.instance.log('model_pack_install_error', {
        'pack': pack.id,
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Activate an installed pack for runtime use. `ModelService` should
  /// query [activePack] on next model load. Activation is atomic: on
  /// any failure, the bundled default remains active.
  Future<bool> activate(String packId) async {
    final installed = _installed[packId];
    if (installed == null || installed.status != ModelPackStatus.installed) {
      return false;
    }

    final modelExists = File(installed.localModelPath).existsSync();
    final labelsExist = File(installed.localLabelsPath).existsSync();
    if (!modelExists || !labelsExist) {
      FieldLogger.instance.log('model_pack_activate_missing', {
        'pack': packId,
        'model': modelExists,
        'labels': labelsExist,
      });
      _installed.remove(packId);
      await _saveInstalled();
      return false;
    }

    _activePackId = packId;
    FieldLogger.instance.log('model_pack_activated', {'pack': packId});
    return true;
  }

  /// Deactivate any active pack and revert to the bundled default.
  void deactivate() {
    _activePackId = null;
    FieldLogger.instance.log('model_pack_deactivated', {});
  }

  /// Uninstall a pack from disk.
  Future<void> uninstall(String packId) async {
    if (_activePackId == packId) deactivate();
    final installed = _installed.remove(packId);
    if (installed != null) {
      try {
        final modelFile = File(installed.localModelPath);
        final labelsFile = File(installed.localLabelsPath);
        if (modelFile.existsSync()) await modelFile.delete();
        if (labelsFile.existsSync()) await labelsFile.delete();
      } catch (_) {}
    }
    await _saveInstalled();
    FieldLogger.instance.log('model_pack_uninstalled', {'pack': packId});
  }

  Future<Directory> _packDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/model_packs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _getInstalledFile() async {
    if (_installedFile != null) return _installedFile!;
    final docs = await getApplicationDocumentsDirectory();
    _installedFile = File('${docs.path}/$_kInstalledFileName');
    return _installedFile!;
  }

  Future<void> _saveInstalled() async {
    try {
      final file = await _getInstalledFile();
      final list = _installed.values.map((ip) => {
            'pack': ip.pack.toJson(),
            'localModel': ip.localModelPath,
            'localLabels': ip.localLabelsPath,
          }).toList();
      await file.writeAsString(jsonEncode(list), flush: true);
    } catch (e) {
      debugPrint('ModelPackManager._saveInstalled error: $e');
    }
  }

  void dispose() {
    _dio.close(force: true);
  }

  @visibleForTesting
  void resetForTesting() {
    _manifest = null;
    _installed.clear();
    _activePackId = null;
    _installedFile = null;
  }
}
