import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_feature_policy.dart';

final _permission = RegExp(r'android:name="(android\.permission\.[A-Z0-9_]+)"');

void main() {
  final repoRoot = Directory.current;

  String read(String relative) => File(
    '${repoRoot.path}${Platform.pathSeparator}$relative',
  ).readAsStringSync();

  Set<String> permissionsIn(String xml) =>
      _permission.allMatches(xml).map((m) => m.group(1)!).toSet();

  test(
    'Core main manifest does not declare excluded experiment permissions',
    () {
      final mainXml = read('android/app/src/main/AndroidManifest.xml');
      final declared = permissionsIn(mainXml);
      for (final forbidden in kExcludedCorePermissions) {
        expect(
          declared.contains(forbidden),
          isFalse,
          reason: '$forbidden must not be in the shared main manifest',
        );
      }
      expect(mainXml.contains('android.hardware.bluetooth_le'), isFalse);
    },
  );

  test('Core overlay strips excluded permissions if plugins merge them', () {
    final coreXml = read('android/app/src/core/AndroidManifest.xml');
    for (final forbidden in kExcludedCorePermissions) {
      expect(
        coreXml.contains(forbidden),
        isTrue,
        reason: '$forbidden must be tools:node=remove in the Core overlay',
      );
      expect(coreXml.contains('tools:node="remove"'), isTrue);
    }
  });

  test('research overlay restores deferred permissions', () {
    final researchXml = read('android/app/src/research/AndroidManifest.xml');
    expect(researchXml.contains('android.permission.RECEIVE_SMS'), isTrue);
    expect(researchXml.contains('android.permission.BLUETOOTH_SCAN'), isTrue);
    expect(
      researchXml.contains('android.permission.ACCESS_BACKGROUND_LOCATION'),
      isTrue,
    );
  });

  test('approved Core permission set is documented in code', () {
    expect(kApprovedCorePermissions, contains('android.permission.CAMERA'));
    expect(kApprovedCorePermissions, contains('android.permission.SEND_SMS'));
    expect(
      kApprovedCorePermissions.contains('android.permission.RECEIVE_SMS'),
      isFalse,
    );
  });
}
