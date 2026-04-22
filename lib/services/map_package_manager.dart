import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive.dart';

import '../models/map_package.dart';
import 'device_capability.dart';

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

String resolveMapPackageBaseUrl(String manifestUrl, String baseUrl) {
  if (baseUrl.isNotEmpty) {
    if (manifestUrl.isEmpty) {
      return baseUrl;
    }
    return Uri.parse(manifestUrl).resolve(baseUrl).toString();
  }
  return manifestUrl;
}

String resolveMapPackageDownloadUrl(
  String manifestUrl,
  String baseUrl,
  String downloadUrl,
) {
  if (downloadUrl.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(downloadUrl);
  if (uri != null && uri.hasScheme) {
    return downloadUrl;
  }

  final resolvedBase = resolveMapPackageBaseUrl(manifestUrl, baseUrl);
  if (resolvedBase.isEmpty) {
    return downloadUrl;
  }

  return Uri.parse(resolvedBase).resolve(downloadUrl).toString();
}

class MapPackageManager {
  static const String _prefsKeyInstalled = 'vg_installed_packages';
  static const String _prefsKeyManifestUrl = 'vg_manifest_url';
  static const String _defaultManifestUrl = '';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 300),
    ),
  );

  List<MapPackage> _available = [];
  List<MapPackage> _installed = [];
  String _manifestUrl = '';
  String _manifestBaseUrl = '';

  List<MapPackage> get available => List.unmodifiable(_available);
  List<MapPackage> get installed => List.unmodifiable(_installed);
  bool get hasStaleInstalledPackage =>
      _installed.any((p) => p.installed && p.isStale());
  List<MapPackage> get staleInstalledPackages => _installed
      .where((p) => p.installed && p.isStale())
      .toList(growable: false);

  String _mapsDir = '';

  void Function(String cityId, double progress)? onDownloadProgress;
  void Function(String cityId)? onDownloadComplete;
  void Function(String cityId, String error)? onDownloadError;
  void Function(String cityId)? onUpdateAvailable;

  Future<void> init({String manifestUrl = ''}) async {
    final appDir = await getApplicationDocumentsDirectory();
    _mapsDir = '${appDir.path}/offline_maps';
    await Directory(_mapsDir).create(recursive: true);

    await _loadInstalledFromPrefs();
    final prefs = await SharedPreferences.getInstance();
    final storedManifestUrl = prefs.getString(_prefsKeyManifestUrl) ?? '';
    final effectiveManifestUrl = manifestUrl.isNotEmpty
        ? manifestUrl
        : storedManifestUrl;
    if (effectiveManifestUrl.isNotEmpty) {
      await fetchManifest(effectiveManifestUrl);
    } else {
      _manifestUrl = storedManifestUrl;
    }
    debugPrint(
      'MapPackageManager: init, ${_installed.length} installed, mapsDir=$_mapsDir',
    );
  }

  String getMapPath(String cityId) => '$_mapsDir/$cityId';

  bool isInstalled(String cityId) =>
      _installed.any((p) => p.cityId == cityId && p.installed);

  MapPackage? getInstalled(String cityId) {
    try {
      return _installed.firstWhere((p) => p.cityId == cityId);
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchManifest(String manifestUrl) async {
    try {
      if (manifestUrl.isEmpty) {
        return;
      }

      await setManifestUrl(manifestUrl);
      final resp = await _dio.get<String>(manifestUrl);
      if (resp.statusCode == 200 && resp.data != null) {
        final json = jsonDecode(resp.data!) as Map<String, dynamic>;
        final manifest = MapPackageManifest.fromJson(json);
        _manifestUrl = manifestUrl;
        _manifestBaseUrl = resolveMapPackageBaseUrl(
          manifestUrl,
          manifest.baseUrl,
        );
        _available = manifest.packages
            .map(
              (pkg) => pkg.copyWith(
                downloadUrl: resolveMapPackageDownloadUrl(
                  manifestUrl,
                  manifest.baseUrl,
                  pkg.downloadUrl,
                ),
              ),
            )
            .toList();

        for (final remote in _available) {
          final local = getInstalled(remote.cityId);
          if (local != null &&
              local.installed &&
              remote.version > local.version) {
            onUpdateAvailable?.call(remote.cityId);
          }
        }

        debugPrint(
          'MapPackageManager: manifest loaded, ${_available.length} packages',
        );
      }
    } catch (e) {
      debugPrint('MapPackageManager.fetchManifest error: $e');
    }
  }

  Future<bool> checkForUpdates() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return false;

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_prefsKeyManifestUrl) ?? _defaultManifestUrl;
    if (url.isEmpty) return false;

    await fetchManifest(url);
    return true;
  }

  Future<bool> downloadCity(String cityId, {String? downloadUrl}) async {
    String url = downloadUrl ?? '';
    final remotePkg = _available.where((p) => p.cityId == cityId).firstOrNull;
    if (url.isEmpty) {
      if (remotePkg == null) {
        onDownloadError?.call(cityId, 'Package not found');
        return false;
      }
      url = remotePkg.downloadUrl;
    }

    url = resolveMapPackageDownloadUrl(_manifestUrl, _manifestBaseUrl, url);

    if (url.isEmpty) {
      onDownloadError?.call(cityId, 'No download URL');
      return false;
    }

    final sizeBytes = remotePkg?.sizeBytes ?? 0;
    if (sizeBytes > 0) {
      final free = await DeviceCapabilityProbe.getFreeBytesAtPath(_mapsDir);
      if (free != -1 && free < sizeBytes * 2) {
        onDownloadError?.call(cityId, 'insufficient_space');
        return false;
      }
    }

    final zipPath = '$_mapsDir/${cityId}_temp.zip';
    final cityDir = '$_mapsDir/$cityId';

    try {
      await _dio.download(
        url,
        zipPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onDownloadProgress?.call(cityId, received / total);
          }
        },
      );

      await _extractZip(zipPath, cityDir);

      final zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();

      final pkg = MapPackage(
        cityId: cityId,
        name: remotePkg?.name ?? cityId,
        nameKk: remotePkg?.nameKk ?? '',
        sizeBytes: remotePkg?.sizeBytes ?? 0,
        version: remotePkg?.version ?? 1,
        downloadUrl: url,
        localPath: cityDir,
        installed: true,
        installedAt: DateTime.now(),
        updatedAt: remotePkg?.updatedAt ?? DateTime.now(),
      );

      _installed.removeWhere((p) => p.cityId == cityId);
      _installed.add(pkg);
      await _saveInstalledToPrefs();

      onDownloadComplete?.call(cityId);
      debugPrint('MapPackageManager: $cityId downloaded and extracted');
      return true;
    } catch (e) {
      debugPrint('MapPackageManager.downloadCity error: $e');
      onDownloadError?.call(cityId, e.toString());

      final zipFile = File(zipPath);
      if (await zipFile.exists()) await zipFile.delete();
      return false;
    }
  }

  Future<bool> deleteCity(String cityId) async {
    try {
      final dir = Directory('$_mapsDir/$cityId');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _installed.removeWhere((p) => p.cityId == cityId);
      await _saveInstalledToPrefs();
      debugPrint('MapPackageManager: $cityId deleted');
      return true;
    } catch (e) {
      debugPrint('MapPackageManager.deleteCity error: $e');
      return false;
    }
  }

  Future<int> diskUsageBytes() async {
    int total = 0;
    final dir = Directory(_mapsDir);
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> _extractZip(String zipPath, String targetDir) async {
    await compute(_doExtractZip, (zipPath, targetDir));
  }

  Future<void> _loadInstalledFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKeyInstalled);
    if (jsonStr == null || jsonStr.isEmpty) return;

    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _installed = list
          .map((e) => MapPackage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('MapPackageManager._loadInstalledFromPrefs error: $e');
    }
  }

  Future<void> _saveInstalledToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_installed.map((p) => p.toJson()).toList());
    await prefs.setString(_prefsKeyInstalled, jsonStr);
  }

  Future<void> setManifestUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _manifestUrl = url;
    await prefs.setString(_prefsKeyManifestUrl, url);
  }

  void dispose() {
    _dio.close();
  }
}
