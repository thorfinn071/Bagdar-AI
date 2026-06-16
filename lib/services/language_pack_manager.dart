import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language_pack.dart';
import 'device_capability.dart';
import 'field_logger.dart';
import 'settings_service.dart';

/// Top-level for `compute()` — extract zip in an isolate so the UI thread
/// stays responsive during install (~50 MB packs can take seconds to inflate).
Future<void> _doExtractZip((String, String) args) async {
  final (zipPath, targetDir) = args;
  final bytes = File(zipPath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  Directory(targetDir).createSync(recursive: true);
  for (final file in archive) {
    final filePath = '$targetDir/${file.name}';
    if (file.isFile) {
      final outFile = File(filePath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(file.content as List<int>);
    } else {
      Directory(filePath).createSync(recursive: true);
    }
  }
}

/// Top-level for `compute()` — SHA-256 a file off the UI thread.
Future<String> _doSha256((String,) args) async {
  final (path,) = args;
  final file = File(path);
  final raw = await file.readAsBytes();
  return crypto.sha256.convert(raw).toString();
}

/// Manages download/install/delete of optional Kazakh-language packs (Vosk
/// model, RHVoice voice, etc.). Mirrors the patterns used by
/// `MapPackageManager` but stores artifacts under `appSupport/lang_packs/`
/// and enforces SHA-256 verification before extraction.
///
/// Singleton because installed-pack state is global (consumed by
/// `VoskKkRecognizer`, `TtsService`, settings UI, onboarding).
class LanguagePackManager {
  LanguagePackManager._();

  static final LanguagePackManager instance = LanguagePackManager._();

  /// GitHub Releases manifest URL. The release tag `lang-packs-manifest`
  /// holds a single `manifest.json` asset, while pack `.zip` files live as
  /// regular release assets under `lang-packs-v1`. See plan doc.
  static const String defaultManifestUrl =
      'https://github.com/thorfinn071/Bagdar-AI/releases/download/lang-packs-manifest/manifest.json';

  static const String _prefsKeyInstalled = 'bagdar_lang_packs_installed_v1';
  static const String _prefsKeyManifestUrl = 'bagdar_lang_packs_manifest_url';
  static const String _prefsKeyManifestFetchedAtMs =
      'bagdar_lang_packs_manifest_fetched_at_ms';
  static const String _prefsKeyManifestCachedJson =
      'bagdar_lang_packs_manifest_cached_json';
  static const String _prefsKeyPackSkippedAtMs =
      'bagdar_lang_pack_skipped_at_ms';
  static const String _prefsKeyPromptOnFirstOnline =
      'bagdar_lang_prompt_on_first_online';

  /// Refresh manifest if the cached copy is older than this.
  static const Duration manifestStaleAfter = Duration(hours: 24);

  /// After a user taps "Skip", suppress the same prompt for this long.
  static const Duration skipCooldown = Duration(days: 7);

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 600),
    ),
  );

  List<LanguagePack> _available = const [];
  List<LanguagePack> _installed = const [];
  String _manifestUrl = '';
  String _packsDir = '';
  bool _ready = false;
  DateTime? _lastManifestFetch;

  void Function(String packId, double progress)? onDownloadProgress;
  void Function(String packId)? onDownloadComplete;
  void Function(String packId, String error)? onDownloadError;
  void Function(String packId)? onUpdateAvailable;

  bool get isReady => _ready;
  String get packsDir => _packsDir;
  String get manifestUrl => _manifestUrl;
  List<LanguagePack> get available => List.unmodifiable(_available);
  List<LanguagePack> get installed => List.unmodifiable(_installed);

  /// Initialize storage layout and load any persisted state. Manifest fetch
  /// is best-effort and silently no-ops when offline.
  Future<void> init({String? overrideManifestUrl}) async {
    if (_ready) return;
    try {
      final supportDir = await getApplicationSupportDirectory();
      _packsDir = '${supportDir.path}/lang_packs';
      await Directory(_packsDir).create(recursive: true);

      await _loadInstalledFromPrefs();

      // Auto-extract bundled packs from assets on first run / if not installed yet
      await _extractBundledAssetPack(LanguagePackIds.voskKk, 'assets/lang_packs/vosk-kk.zip');
      await _extractBundledAssetPack(LanguagePackIds.rhvoiceKkAigul, 'assets/lang_packs/rhvoice-kk-aigul.zip');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKeyManifestUrl) ?? '';
      _manifestUrl = (overrideManifestUrl != null &&
              overrideManifestUrl.isNotEmpty)
          ? overrideManifestUrl
          : (stored.isNotEmpty ? stored : defaultManifestUrl);
      final fetchedMs = prefs.getInt(_prefsKeyManifestFetchedAtMs);
      _lastManifestFetch = fetchedMs != null && fetchedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(fetchedMs)
          : null;
      final cached = prefs.getString(_prefsKeyManifestCachedJson);
      if (cached != null && cached.isNotEmpty) {
        _parseManifestJson(cached);
      }
      _ready = true;
      debugPrint(
        'LanguagePackManager: ready. installed=${_installed.length} '
        'available=${_available.length} dir=$_packsDir',
      );
    } catch (e) {
      debugPrint('LanguagePackManager.init error: $e');
      _ready = false;
    }
  }

  /// Returns true if the cached manifest is missing or older than
  /// [manifestStaleAfter].
  bool get manifestNeedsRefresh {
    if (_available.isEmpty) return true;
    final last = _lastManifestFetch;
    if (last == null) return true;
    return DateTime.now().difference(last) > manifestStaleAfter;
  }

  /// Fetch and parse manifest from network. Returns true if a fresh manifest
  /// was loaded and persisted to cache.
  Future<bool> fetchManifest({String? url}) async {
    final effective = (url != null && url.isNotEmpty) ? url : _manifestUrl;
    if (effective.isEmpty) return false;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;

      final resp = await _dio.get<String>(effective);
      if (resp.statusCode != 200 || resp.data == null) return false;

      _parseManifestJson(resp.data!);
      _manifestUrl = effective;
      _lastManifestFetch = DateTime.now();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyManifestUrl, effective);
      await prefs.setString(_prefsKeyManifestCachedJson, resp.data!);
      await prefs.setInt(
        _prefsKeyManifestFetchedAtMs,
        _lastManifestFetch!.millisecondsSinceEpoch,
      );

      for (final remote in _available) {
        final local = getInstalled(remote.packId);
        if (local != null && local.installed && remote.version > local.version) {
          onUpdateAvailable?.call(remote.packId);
        }
      }
      debugPrint(
        'LanguagePackManager: manifest loaded, ${_available.length} packs',
      );
      return true;
    } catch (e) {
      debugPrint('LanguagePackManager.fetchManifest error: $e');
      return false;
    }
  }

  /// Path on disk where pack `packId` is (or would be) extracted.
  String pathFor(String packId) => '$_packsDir/$packId';

  bool isInstalled(String packId) =>
      _installed.any((p) => p.packId == packId && p.installed);

  LanguagePack? getInstalled(String packId) {
    for (final p in _installed) {
      if (p.packId == packId) return p;
    }
    return null;
  }

  LanguagePack? getAvailable(String packId) {
    for (final p in _available) {
      if (p.packId == packId) return p;
    }
    return null;
  }

  /// Download, verify (SHA-256), extract, and register pack [packId].
  /// Returns true on success.
  Future<bool> downloadPack(String packId) async {
    if (!_ready) {
      onDownloadError?.call(packId, 'not_initialized');
      return false;
    }
    final remote = getAvailable(packId);
    if (remote == null || remote.downloadUrl.isEmpty) {
      onDownloadError?.call(packId, 'unknown_pack');
      return false;
    }

    if (remote.sizeBytes > 0) {
      final free = await DeviceCapabilityProbe.getFreeBytesAtPath(_packsDir);
      if (free != -1 && free < remote.sizeBytes * 2) {
        onDownloadError?.call(packId, 'insufficient_space');
        FieldLogger.instance.log('lang_pack_download_failed', {
          'pack': packId,
          'reason': 'insufficient_space',
        });
        return false;
      }
    }

    final zipPath = '$_packsDir/${packId}_temp.zip';
    final extractDir = pathFor(packId);

    FieldLogger.instance.log('lang_pack_download_started', {
      'pack': packId,
      'sizeBytes': remote.sizeBytes,
      'version': remote.version,
    });

    try {
      
      final stale = File(zipPath);
      if (await stale.exists()) await stale.delete();
      final extractDirHandle = Directory(extractDir);
      if (await extractDirHandle.exists()) {
        await extractDirHandle.delete(recursive: true);
      }

      await _dio.download(
        remote.downloadUrl,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onDownloadProgress?.call(packId, received / total);
          }
        },
      );

      
      if (remote.sha256.isNotEmpty) {
        final actual = await compute(_doSha256, (zipPath,));
        if (actual.toLowerCase() != remote.sha256.toLowerCase()) {
          onDownloadError?.call(packId, 'sha256_mismatch');
          FieldLogger.instance.log('lang_pack_download_failed', {
            'pack': packId,
            'reason': 'sha256_mismatch',
            'expected': remote.sha256,
            'actual': actual,
          });
          await File(zipPath).delete();
          return false;
        }
      }

      await _extractZip(zipPath, extractDir);
      await File(zipPath).delete();

      final installed = remote.copyWith(
        localPath: extractDir,
        installed: true,
        installedAt: DateTime.now(),
      );

      final next = List<LanguagePack>.from(_installed)
        ..removeWhere((p) => p.packId == packId)
        ..add(installed);
      _installed = next;
      await _saveInstalledToPrefs();

      onDownloadComplete?.call(packId);
      FieldLogger.instance.log('lang_pack_download_complete', {
        'pack': packId,
        'version': remote.version,
      });
      debugPrint('LanguagePackManager: $packId installed at $extractDir');
      return true;
    } catch (e) {
      debugPrint('LanguagePackManager.downloadPack($packId) error: $e');
      onDownloadError?.call(packId, e.toString());
      FieldLogger.instance.log('lang_pack_download_failed', {
        'pack': packId,
        'reason': 'exception',
        'error': e.toString(),
      });
      try {
        final zipFile = File(zipPath);
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Remove a downloaded pack from disk and the installed registry.
  Future<bool> deletePack(String packId) async {
    try {
      final dir = Directory(pathFor(packId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _installed = _installed
          .where((p) => p.packId != packId)
          .toList(growable: false);
      await _saveInstalledToPrefs();
      debugPrint('LanguagePackManager: $packId deleted');
      return true;
    } catch (e) {
      debugPrint('LanguagePackManager.deletePack($packId) error: $e');
      return false;
    }
  }

  /// Total bytes used by all installed packs.
  Future<int> diskUsageBytes() async {
    int total = 0;
    final dir = Directory(_packsDir);
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  
  Future<void> markPackSkipped(String packId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_prefsKeyPackSkippedAtMs.$packId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> wasPackSkippedRecently(String packId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_prefsKeyPackSkippedAtMs.$packId');
    if (ms == null || ms == 0) return false;
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.now().difference(at) < skipCooldown;
  }

  Future<void> setPromptOnFirstOnline(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyPromptOnFirstOnline, v);
  }

  Future<bool> shouldPromptOnFirstOnline() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyPromptOnFirstOnline) ?? false;
  }

  
  Future<void> _extractZip(String zipPath, String targetDir) async {
    await compute(_doExtractZip, (zipPath, targetDir));
  }

  Future<void> _extractBundledAssetPack(String packId, String assetPath) async {
    final extractDir = pathFor(packId);
    final extractDirHandle = Directory(extractDir);

    if (isInstalled(packId) && await extractDirHandle.exists()) {
      return;
    }

    try {
      debugPrint('LanguagePackManager: extracting bundled asset $assetPath to $extractDir');
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      final tempZipPath = '$_packsDir/${packId}_temp.zip';
      final tempFile = File(tempZipPath);
      await tempFile.writeAsBytes(bytes);

      await _extractZip(tempZipPath, extractDir);
      await tempFile.delete();

      final defaultPack = LanguagePack(
        packId: packId,
        name: packId == LanguagePackIds.voskKk ? 'Vosk KK' : 'RHVoice KK Aigul',
        downloadUrl: '',
        sha256: '',
        sizeBytes: bytes.length,
        version: 1,
        installed: true,
        localPath: extractDir,
        installedAt: DateTime.now(),
      );

      final next = List<LanguagePack>.from(_installed)
        ..removeWhere((p) => p.packId == packId)
        ..add(defaultPack);
      _installed = next;
      await _saveInstalledToPrefs();

      await Settings.instance.setEnableKazakhStackV2(true);
      debugPrint('LanguagePackManager: Bundled pack $packId extracted and installed.');
    } catch (e) {
      debugPrint('LanguagePackManager: Failed to extract bundled asset pack $packId: $e');
    }
  }

  void _parseManifestJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final manifest = LanguagePackManifest.fromJson(decoded);
      _available = manifest.packs;
    } catch (e) {
      debugPrint('LanguagePackManager._parseManifestJson error: $e');
    }
  }

  Future<void> _loadInstalledFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKeyInstalled);
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _installed = list
          .map((e) => LanguagePack.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('LanguagePackManager._loadInstalledFromPrefs error: $e');
    }
  }

  Future<void> _saveInstalledToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_installed.map((p) => p.toJson()).toList());
    await prefs.setString(_prefsKeyInstalled, jsonStr);
  }

  void dispose() {
    _dio.close();
  }

  
  @visibleForTesting
  void debugReset({
    String packsDir = '',
    List<LanguagePack> installed = const [],
    List<LanguagePack> available = const [],
  }) {
    _packsDir = packsDir;
    _installed = installed;
    _available = available;
    _ready = packsDir.isNotEmpty;
  }

  @visibleForTesting
  Future<void> debugIngestManifestJson(String jsonStr) async {
    _parseManifestJson(jsonStr);
  }
}
