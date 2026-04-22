import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/arcore_depth_whitelist.dart';

void main() {
  group('ArCoreDepthWhitelist.verdict', () {
    test('whitelists Pixel 4', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Google',
          model: 'Pixel 4',
          brand: 'google',
          sdkInt: 30,
        ),
        ArCoreDepthVerdict.supported,
      );
    });

    test('whitelists Pixel 9 Pro XL', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Google',
          model: 'Pixel 9 Pro XL',
          brand: 'google',
          sdkInt: 34,
        ),
        ArCoreDepthVerdict.supported,
      );
    });

    test('whitelists unlisted Pixel generation via prefix rule', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Google',
          model: 'Pixel 10 Ultra',
          brand: 'google',
          sdkInt: 35,
        ),
        ArCoreDepthVerdict.supported,
      );
    });

    test('refuses low-SDK device outright', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Samsung',
          model: 'SM-G900',
          brand: 'samsung',
          sdkInt: 24,
        ),
        ArCoreDepthVerdict.unsupported,
      );
    });

    test('blacklists budget-brand hardware regardless of SDK', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'ITEL',
          model: 'A17',
          brand: 'ITEL',
          sdkInt: 30,
        ),
        ArCoreDepthVerdict.unsupported,
      );
    });

    test('unknown verdict for unlisted mid-range device', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Xiaomi',
          model: 'Redmi Note 12',
          brand: 'xiaomi',
          sdkInt: 33,
        ),
        ArCoreDepthVerdict.unknown,
      );
    });

    test('falls back to unknown when Pixel model lacks numeric suffix', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Google',
          model: 'Pixel Tablet',
          brand: 'google',
          sdkInt: 33,
        ),
        ArCoreDepthVerdict.unknown,
      );
    });

    test('rejects Pixel 3 via prefix rule', () {
      expect(
        ArCoreDepthWhitelist.verdict(
          manufacturer: 'Google',
          model: 'Pixel 3',
          brand: 'google',
          sdkInt: 29,
        ),
        ArCoreDepthVerdict.unknown,
      );
    });
  });
}
