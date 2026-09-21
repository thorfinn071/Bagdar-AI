import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/map_package_manifest.dart';

void main() {
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  MapPackageManifest manifest({int size = 1000}) => MapPackageManifest(
    cityId: 'unspecified',
    schemaVersion: '1',
    source: 'osm',
    sourceDate: DateTime.utc(2026, 1, 1),
    appCompatMin: '1.0.0',
    appCompatMax: '2.0.0',
    contentSha256: hash,
    sizeBytes: size,
    license: 'ODbL',
  );

  test('truncated payload is not installed', () {
    expect(
      MapPackageInstallPolicy.verify(
        manifest: manifest(),
        actualSha256: hash,
        actualBytes: 10,
        freeBytes: 10 * 1024 * 1024,
        appVersion: '1.0.0',
      ),
      MapPackageInstallResult.truncated,
    );
  });

  test('hash mismatch is not installed', () {
    expect(
      MapPackageInstallPolicy.verify(
        manifest: manifest(),
        actualSha256: 'bb' * 32,
        actualBytes: 1000,
        freeBytes: 10 * 1024 * 1024,
        appVersion: '1.0.0',
      ),
      MapPackageInstallResult.hashMismatch,
    );
  });

  test('low storage is not installed', () {
    expect(
      MapPackageInstallPolicy.verify(
        manifest: manifest(size: 5000),
        actualSha256: hash,
        actualBytes: 5000,
        freeBytes: 100,
        appVersion: '1.0.0',
      ),
      MapPackageInstallResult.insufficientStorage,
    );
  });

  test('matching hash and size verifies without inventing city data', () {
    expect(
      MapPackageInstallPolicy.verify(
        manifest: manifest(),
        actualSha256: hash,
        actualBytes: 1000,
        freeBytes: 10 * 1024 * 1024,
        appVersion: '1.0.0',
      ),
      MapPackageInstallResult.verified,
    );
  });
}
