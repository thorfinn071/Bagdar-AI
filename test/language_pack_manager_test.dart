import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/models/language_pack.dart';
import 'package:bagdar/services/language_pack_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    LanguagePackManager.instance.debugReset(packsDir: '/tmp/test_lang_packs');
  });

  group('LanguagePackManager.debugIngestManifestJson', () {
    test('parses a valid manifest into the available list', () async {
      const json = '''
{
  "manifestVersion": 1,
  "packs": [
    {"id": "vosk-kk", "name": "Vosk KK", "url": "https://x/vosk.zip", "size": 1000, "version": 15, "sha256": "deadbeef"}
  ]
}
''';
      await LanguagePackManager.instance.debugIngestManifestJson(json);
      final available = LanguagePackManager.instance.available;
      expect(available.length, 1);
      expect(available.first.packId, LanguagePackIds.voskKk);
      expect(available.first.downloadUrl, 'https://x/vosk.zip');
    });

    test('malformed JSON does not throw, leaves available empty', () async {
      await LanguagePackManager.instance.debugIngestManifestJson('{not json');
      expect(LanguagePackManager.instance.available, isEmpty);
    });

    test('manifest with empty packs array yields empty list', () async {
      await LanguagePackManager.instance.debugIngestManifestJson(
        '{"manifestVersion": 1, "packs": []}',
      );
      expect(LanguagePackManager.instance.available, isEmpty);
    });
  });

  group('LanguagePackManager.isInstalled / getInstalled', () {
    test('returns false / null when no packs are installed', () {
      expect(
        LanguagePackManager.instance.isInstalled(LanguagePackIds.voskKk),
        false,
      );
      expect(
        LanguagePackManager.instance.getInstalled(LanguagePackIds.voskKk),
        isNull,
      );
    });

    test('reflects packs injected via debugReset', () {
      LanguagePackManager.instance.debugReset(
        packsDir: '/tmp/test_lang_packs',
        installed: const [
          LanguagePack(
            packId: 'vosk-kk',
            name: 'Vosk KK',
            localPath: '/tmp/test_lang_packs/vosk-kk',
            installed: true,
          ),
        ],
      );
      expect(
        LanguagePackManager.instance.isInstalled(LanguagePackIds.voskKk),
        true,
      );
      final pack = LanguagePackManager.instance.getInstalled(
        LanguagePackIds.voskKk,
      );
      expect(pack, isNotNull);
      expect(pack!.localPath, '/tmp/test_lang_packs/vosk-kk');
    });

    test(
      'isInstalled returns false for an injected-but-not-installed pack',
      () {
        LanguagePackManager.instance.debugReset(
          packsDir: '/tmp/test_lang_packs',
          installed: const [LanguagePack(packId: 'vosk-kk', name: 'Vosk KK')],
        );
        expect(
          LanguagePackManager.instance.isInstalled(LanguagePackIds.voskKk),
          false,
        );
      },
    );
  });

  group('LanguagePackManager.pathFor', () {
    test('returns the predictable subdirectory layout', () {
      LanguagePackManager.instance.debugReset(
        packsDir: '/data/user/0/com.example/files/lang_packs',
      );
      expect(
        LanguagePackManager.instance.pathFor(LanguagePackIds.voskKk),
        '/data/user/0/com.example/files/lang_packs/vosk-kk',
      );
    });
  });

  group('LanguagePackManager skip / re-prompt cooldown', () {
    test('wasPackSkippedRecently returns false when never skipped', () async {
      LanguagePackManager.instance.debugReset(packsDir: '/tmp');
      expect(
        await LanguagePackManager.instance.wasPackSkippedRecently(
          LanguagePackIds.voskKk,
        ),
        false,
      );
    });

    test(
      'wasPackSkippedRecently returns true immediately after skip',
      () async {
        LanguagePackManager.instance.debugReset(packsDir: '/tmp');
        await LanguagePackManager.instance.markPackSkipped(
          LanguagePackIds.voskKk,
        );
        expect(
          await LanguagePackManager.instance.wasPackSkippedRecently(
            LanguagePackIds.voskKk,
          ),
          true,
        );
      },
    );

    test('shouldPromptOnFirstOnline default false, toggleable', () async {
      LanguagePackManager.instance.debugReset(packsDir: '/tmp');
      expect(
        await LanguagePackManager.instance.shouldPromptOnFirstOnline(),
        false,
      );
      await LanguagePackManager.instance.setPromptOnFirstOnline(true);
      expect(
        await LanguagePackManager.instance.shouldPromptOnFirstOnline(),
        true,
      );
    });
  });

  group('LanguagePackManager.manifestNeedsRefresh', () {
    test('returns true when no manifest cached', () {
      LanguagePackManager.instance.debugReset(packsDir: '/tmp');
      expect(LanguagePackManager.instance.manifestNeedsRefresh, true);
    });
  });
}
