class MapPackage {
  final String cityId;
  final String name;
  final String nameKk;
  final int sizeBytes;
  final int version;
  final String downloadUrl;
  final String localPath;
  final bool installed;
  final DateTime? installedAt;
  final DateTime? updatedAt;

  static const Duration _staleAfter = Duration(days: 90);

  const MapPackage({
    required this.cityId,
    required this.name,
    this.nameKk = '',
    this.sizeBytes = 0,
    this.version = 0,
    this.downloadUrl = '',
    this.localPath = '',
    this.installed = false,
    this.installedAt,
    this.updatedAt,
  });

  DateTime? get freshnessTimestamp => updatedAt ?? installedAt;

  bool isStale([DateTime? now]) {
    final timestamp = freshnessTimestamp;
    if (timestamp == null) return false;
    final reference = now ?? DateTime.now();
    return reference.difference(timestamp) > _staleAfter;
  }

  MapPackage copyWith({
    String? cityId,
    String? name,
    String? nameKk,
    int? sizeBytes,
    int? version,
    String? downloadUrl,
    String? localPath,
    bool? installed,
    DateTime? installedAt,
    DateTime? updatedAt,
  }) => MapPackage(
    cityId: cityId ?? this.cityId,
    name: name ?? this.name,
    nameKk: nameKk ?? this.nameKk,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    version: version ?? this.version,
    downloadUrl: downloadUrl ?? this.downloadUrl,
    localPath: localPath ?? this.localPath,
    installed: installed ?? this.installed,
    installedAt: installedAt ?? this.installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  String get sizeMb => (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

  Map<String, dynamic> toJson() => {
    'cityId': cityId,
    'name': name,
    'nameKk': nameKk,
    'sizeBytes': sizeBytes,
    'version': version,
    'downloadUrl': downloadUrl,
    'localPath': localPath,
    'installed': installed,
    'installedAt': installedAt?.millisecondsSinceEpoch,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
  };

  factory MapPackage.fromJson(Map<String, dynamic> json) => MapPackage(
    cityId: json['cityId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    nameKk: json['nameKk'] as String? ?? '',
    sizeBytes: json['sizeBytes'] as int? ?? 0,
    version: json['version'] as int? ?? 0,
    downloadUrl: json['downloadUrl'] as String? ?? '',
    localPath: json['localPath'] as String? ?? '',
    installed: json['installed'] as bool? ?? false,
    installedAt: json['installedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['installedAt'] as int)
        : null,
    updatedAt: json['updatedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
        : null,
  );
}

class MapPackageManifest {
  final int manifestVersion;
  final List<MapPackage> packages;
  final String baseUrl;

  const MapPackageManifest({
    this.manifestVersion = 1,
    this.packages = const [],
    this.baseUrl = '',
  });

  factory MapPackageManifest.fromJson(Map<String, dynamic> json) {
    final items = json['packages'] as List<dynamic>? ?? [];
    return MapPackageManifest(
      manifestVersion: json['manifestVersion'] as int? ?? 1,
      baseUrl: json['baseUrl'] as String? ?? '',
      packages: items
          .map((e) => MapPackage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
