/// Signed/hashed offline map package manifest. No city payload is bundled
/// in Core Safety. This is the install contract for Core Mobility.
class MapPackageManifest {
  final String cityId;
  final String schemaVersion;
  final String source;
  final DateTime sourceDate;
  final String appCompatMin;
  final String appCompatMax;
  final String contentSha256;
  final int sizeBytes;
  final String license;

  const MapPackageManifest({
    required this.cityId,
    required this.schemaVersion,
    required this.source,
    required this.sourceDate,
    required this.appCompatMin,
    required this.appCompatMax,
    required this.contentSha256,
    required this.sizeBytes,
    required this.license,
  });

  bool get hasValidHash =>
      contentSha256.length == 64 &&
      RegExp(r'^[0-9a-f]+$').hasMatch(contentSha256);

  bool compatibleWith(String appVersion) {
    return appVersion.compareTo(appCompatMin) >= 0 &&
        appVersion.compareTo(appCompatMax) <= 0;
  }

  factory MapPackageManifest.fromJson(Map<String, dynamic> json) {
    return MapPackageManifest(
      cityId: json['cityId'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as String? ?? '',
      source: json['source'] as String? ?? '',
      sourceDate:
          DateTime.tryParse(json['sourceDate'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appCompatMin: json['appCompatMin'] as String? ?? '',
      appCompatMax: json['appCompatMax'] as String? ?? '',
      contentSha256: json['contentSha256'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      license: json['license'] as String? ?? '',
    );
  }
}

enum MapPackageInstallResult {
  verified,
  corrupt,
  truncated,
  unsupportedSchema,
  hashMismatch,
  insufficientStorage,
  interrupted,
}

/// Atomic install: verify temp copy, then switch. Never claim a route is safe.
class MapPackageInstallPolicy {
  static MapPackageInstallResult verify({
    required MapPackageManifest manifest,
    required String actualSha256,
    required int actualBytes,
    required int freeBytes,
    required String appVersion,
  }) {
    if (manifest.schemaVersion.isEmpty) {
      return MapPackageInstallResult.unsupportedSchema;
    }
    if (actualBytes < manifest.sizeBytes) {
      return MapPackageInstallResult.truncated;
    }
    if (freeBytes < manifest.sizeBytes) {
      return MapPackageInstallResult.insufficientStorage;
    }
    if (!manifest.hasValidHash || actualSha256 != manifest.contentSha256) {
      return MapPackageInstallResult.hashMismatch;
    }
    if (!manifest.compatibleWith(appVersion)) {
      return MapPackageInstallResult.unsupportedSchema;
    }
    return MapPackageInstallResult.verified;
  }
}
