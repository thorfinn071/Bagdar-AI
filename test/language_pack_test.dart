import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/language_pack.dart';

void main() {
  group('LanguagePack', () {
    test('JSON round-trip preserves all fields', () {
      final original = LanguagePack(
        packId: LanguagePackIds.voskKk,
        name: 'Vosk Kazakh',
        nameKk: 'Vosk қазақша',
        nameEn: 'Vosk Kazakh',
        sizeBytes: 52428800,
        version: 15,
        downloadUrl:
            'https://github.com/thorfinn071/Bagdar-AI/releases/download/lang-packs-v1/vosk-kk-0.15.zip',
        sha256: 'abc123def456',
        localPath: '/data/lang_packs/vosk-kk',
        minAppVersion: '1.1.0',
        installed: true,
        installedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700001000000),
      );

      final json = original.toJson();
      final restored = LanguagePack.fromJson(json);

      expect(restored.packId, original.packId);
      expect(restored.name, original.name);
      expect(restored.nameKk, original.nameKk);
      expect(restored.nameEn, original.nameEn);
      expect(restored.sizeBytes, original.sizeBytes);
      expect(restored.version, original.version);
      expect(restored.downloadUrl, original.downloadUrl);
      expect(restored.sha256, original.sha256);
      expect(restored.localPath, original.localPath);
      expect(restored.minAppVersion, original.minAppVersion);
      expect(restored.installed, original.installed);
      expect(restored.installedAt, original.installedAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('fromJson accepts manifest-style aliases (id, url, size)', () {
      // The GitHub Releases manifest uses {id, url, size} keys — see plan
      // doc § Cross-cutting work. The model must accept both.
      final manifestStyle = {
        'id': LanguagePackIds.voskKk,
        'name': 'Vosk KK',
        'url': 'https://example.com/vosk-kk.zip',
        'size': 50000000,
        'version': 15,
        'sha256': 'deadbeef',
      };
      final pack = LanguagePack.fromJson(manifestStyle);
      expect(pack.packId, LanguagePackIds.voskKk);
      expect(pack.downloadUrl, 'https://example.com/vosk-kk.zip');
      expect(pack.sizeBytes, 50000000);
      expect(pack.sha256, 'deadbeef');
    });

    test('fromJson handles missing optional fields gracefully', () {
      final pack = LanguagePack.fromJson({'packId': 'minimal'});
      expect(pack.packId, 'minimal');
      expect(pack.name, '');
      expect(pack.sizeBytes, 0);
      expect(pack.version, 0);
      expect(pack.installed, false);
      expect(pack.installedAt, isNull);
    });

    test('copyWith updates only specified fields', () {
      const original = LanguagePack(
        packId: 'vosk-kk',
        name: 'Vosk',
        sizeBytes: 100,
        version: 1,
      );
      final updated = original.copyWith(installed: true, version: 2);
      expect(updated.packId, 'vosk-kk');
      expect(updated.name, 'Vosk');
      expect(updated.sizeBytes, 100);
      expect(updated.version, 2);
      expect(updated.installed, true);
    });

    test('isStale returns false when no timestamps', () {
      const pack = LanguagePack(packId: 'x', name: 'X');
      expect(pack.isStale(), false);
    });

    test('isStale returns true after 366 days', () {
      final pack = LanguagePack(
        packId: 'x',
        name: 'X',
        installedAt: DateTime(2020, 1, 1),
      );
      expect(pack.isStale(DateTime(2021, 1, 2)), true);
    });

    test('isStale returns false within freshness window', () {
      final pack = LanguagePack(
        packId: 'x',
        name: 'X',
        installedAt: DateTime(2024, 1, 1),
      );
      expect(pack.isStale(DateTime(2024, 6, 1)), false);
    });

    test('sizeMb formats human-readable size', () {
      const pack = LanguagePack(
        packId: 'x',
        name: 'X',
        sizeBytes: 52428800, // 50 MB exactly
      );
      expect(pack.sizeMb, '50.0');
    });
  });

  group('LanguagePackManifest', () {
    test('parses example GitHub Releases manifest payload', () {
      const sample = '''
{
  "manifestVersion": 1,
  "packs": [
    {
      "id": "vosk-kk",
      "version": 15,
      "url": "https://github.com/thorfinn071/Bagdar-AI/releases/download/lang-packs-v1/vosk-kk-0.15.zip",
      "size": 52428800,
      "sha256": "abc",
      "minAppVersion": "1.1.0"
    },
    {
      "id": "rhvoice-kk-aigul",
      "version": 1,
      "url": "https://github.com/thorfinn071/Bagdar-AI/releases/download/lang-packs-v1/rhvoice-kk-aigul-1.0.zip",
      "size": 31457280,
      "sha256": "def",
      "minAppVersion": "1.2.0"
    }
  ]
}
''';
      final manifest = LanguagePackManifest.fromJson(
        jsonDecode(sample) as Map<String, dynamic>,
      );
      expect(manifest.manifestVersion, 1);
      expect(manifest.packs.length, 2);
      expect(manifest.packs[0].packId, LanguagePackIds.voskKk);
      expect(manifest.packs[1].packId, LanguagePackIds.rhvoiceKkAigul);
    });

    test('empty packs list parses without error', () {
      final manifest = LanguagePackManifest.fromJson({
        'manifestVersion': 1,
        'packs': <Map<String, dynamic>>[],
      });
      expect(manifest.packs, isEmpty);
    });
  });

  group('LanguagePackIds', () {
    test('exposes the IDs referenced in voice_command_service routing', () {
      // These IDs are referenced verbatim in
      // VoiceCommandService._shouldUseVoskForKk and the plan's GitHub
      // Releases manifest. Hardcoding them in a test catches accidental
      // renames before they cause silent routing failures.
      expect(LanguagePackIds.voskKk, 'vosk-kk');
      expect(LanguagePackIds.rhvoiceKkAigul, 'rhvoice-kk-aigul');
    });
  });
}
