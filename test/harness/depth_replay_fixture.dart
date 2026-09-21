import 'dart:io';
import 'dart:typed_data';

/// Versioned replay schema for geometric obstacle tests.
///
/// A plain MP4 is not enough. When the corpus file is absent, callers must
/// report `missing fixture` rather than pass.
class DepthReplayFixture {
  static const schemaVersion = 1;

  final int version;
  final int width;
  final int height;
  final int timestampUs;
  final String provider;
  final String semantics;
  final Float32List values;
  final Float32List confidence01;
  final int rotationDegrees;
  final double cropTopFraction;

  const DepthReplayFixture({
    required this.version,
    required this.width,
    required this.height,
    required this.timestampUs,
    required this.provider,
    required this.semantics,
    required this.values,
    required this.confidence01,
    required this.rotationDegrees,
    required this.cropTopFraction,
  });

  static File corpusManifest(String name) =>
      File('test/fixtures/generic_obstacle/$name');

  static bool hasCorpus(String name) => corpusManifest(name).existsSync();
}
