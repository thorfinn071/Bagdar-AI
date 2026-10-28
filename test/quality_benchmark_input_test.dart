import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/simulation/quality_benchmark.dart' as benchmark;

void main() {
  late Directory root;
  late Map<String, Object?> manifest;
  late Map<String, Object?> image;

  Future<void> run() async {
    await File(
      '${root.path}/manifest.json',
    ).writeAsString(jsonEncode(manifest));
    await benchmark.main([root.path]);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bagdar-quality-input-');
    final protocol = utf8.encode('{}');
    final bytes = Uint8List(16 * 16)..fillRange(0, 16 * 16, 128);
    await File('${root.path}/protocol.json').writeAsBytes(protocol);
    await File('${root.path}/sample.y8').writeAsBytes(bytes);
    image = {
      'id': 'sample',
      'width': 16,
      'height': 16,
      'rowStride': 16,
      'asset': {
        'path': 'sample.y8',
        'sha256': sha256.convert(bytes).toString(),
      },
    };
    manifest = {
      'schemaVersion': 1,
      'promotionAllowed': false,
      'protocolSha256': sha256.convert(protocol).toString(),
      'images': [image],
    };
  });
  tearDown(() async => root.delete(recursive: true));

  test('changed pixels never produce a diagnostic baseline', () async {
    await File('${root.path}/sample.y8').writeAsBytes(Uint8List(16 * 16));
    await expectLater(run(), throwsFormatException);
    expect(await File('${root.path}/baseline.json').exists(), false);
  });

  test('path traversal is rejected before reading external pixels', () async {
    (image['asset'] as Map)['path'] = '../outside.y8';
    await expectLater(run(), throwsFormatException);
  });

  test('duplicate image identity cannot inflate the measured corpus', () async {
    manifest['images'] = [image, image];
    await expectLater(run(), throwsFormatException);
    expect(await File('${root.path}/baseline.json').exists(), false);
  });

  test(
    'foreign protocol cannot be evaluated under the manifest identity',
    () async {
      await File(
        '${root.path}/protocol.json',
      ).writeAsString('{"changed":true}');
      await expectLater(run(), throwsFormatException);
    },
  );

  test('an existing baseline is preserved exactly', () async {
    final baseline = File('${root.path}/baseline.json');
    await baseline.writeAsString('frozen receipt');
    await expectLater(run(), throwsStateError);
    expect(await baseline.readAsString(), 'frozen receipt');
  });
}
