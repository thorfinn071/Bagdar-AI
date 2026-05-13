class LanguagePack {
  final String packId;
  final String name;
  final String nameKk;
  final String nameEn;
  final int sizeBytes;
  final int version;
  final String downloadUrl;
  final String sha256;
  final String localPath;
  final String minAppVersion;
  final bool installed;
  final DateTime? installedAt;
  final DateTime? updatedAt;

  static const Duration _staleAfter = Duration(days: 365);

  const LanguagePack({
    required this.packId,
    required this.name,
    this.nameKk = '',
    this.nameEn = '',
    this.sizeBytes = 0,
    this.version = 0,
    this.downloadUrl = '',
    this.sha256 = '',
    this.localPath = '',
    this.minAppVersion = '',
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

  String get sizeMb => (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

  LanguagePack copyWith({
    String? packId,
    String? name,
    String? nameKk,
    String? nameEn,
    int? sizeBytes,
    int? version,
    String? downloadUrl,
    String? sha256,
    String? localPath,
    String? minAppVersion,
    bool? installed,
    DateTime? installedAt,
    DateTime? updatedAt,
  }) =>
      LanguagePack(
        packId: packId ?? this.packId,
        name: name ?? this.name,
        nameKk: nameKk ?? this.nameKk,
        nameEn: nameEn ?? this.nameEn,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        version: version ?? this.version,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        sha256: sha256 ?? this.sha256,
        localPath: localPath ?? this.localPath,
        minAppVersion: minAppVersion ?? this.minAppVersion,
        installed: installed ?? this.installed,
        installedAt: installedAt ?? this.installedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'packId': packId,
        'name': name,
        'nameKk': nameKk,
        'nameEn': nameEn,
        'sizeBytes': sizeBytes,
        'version': version,
        'downloadUrl': downloadUrl,
        'sha256': sha256,
        'localPath': localPath,
        'minAppVersion': minAppVersion,
        'installed': installed,
        'installedAt': installedAt?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
      };

  factory LanguagePack.fromJson(Map<String, dynamic> json) => LanguagePack(
        packId: (json['packId'] ?? json['id']) as String? ?? '',
        name: json['name'] as String? ?? '',
        nameKk: json['nameKk'] as String? ?? '',
        nameEn: json['nameEn'] as String? ?? '',
        sizeBytes: json['sizeBytes'] as int? ?? json['size'] as int? ?? 0,
        version: json['version'] is int
            ? json['version'] as int
            : int.tryParse('${json['version'] ?? 0}'.split('.').first) ?? 0,
        downloadUrl: (json['downloadUrl'] ?? json['url']) as String? ?? '',
        sha256: json['sha256'] as String? ?? '',
        localPath: json['localPath'] as String? ?? '',
        minAppVersion: json['minAppVersion'] as String? ?? '',
        installed: json['installed'] as bool? ?? false,
        installedAt: json['installedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['installedAt'] as int)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
            : null,
      );
}

class LanguagePackManifest {
  final int manifestVersion;
  final List<LanguagePack> packs;

  const LanguagePackManifest({
    this.manifestVersion = 1,
    this.packs = const [],
  });

  factory LanguagePackManifest.fromJson(Map<String, dynamic> json) {
    final items = json['packs'] as List<dynamic>? ?? const [];
    return LanguagePackManifest(
      manifestVersion: json['manifestVersion'] as int? ?? 1,
      packs: items
          .map((e) => LanguagePack.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

abstract class LanguagePackIds {
  LanguagePackIds._();

  static const String voskKk = 'vosk-kk';
  static const String rhvoiceKkAigul = 'rhvoice-kk-aigul';
}
