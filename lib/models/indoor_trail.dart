import 'dart:convert';

/// A single sample captured during a trail recording, at roughly one
/// step's worth of cadence. We deliberately do *not* persist raw audio
/// or images; only summary scalars that fit the offline-first, on-device
/// telemetry discipline.
class IndoorTrailSample {
  /// Monotonically increasing step index from session start.
  final int stepIndex;

  /// Compass heading in degrees (0–360, magnetic north).
  final double headingDeg;

  /// Magnetometer vector magnitude in microteslas. Derived feature used
  /// by the particle filter to match against the recorded trail.
  final double magMicroT;

  /// Mean linear acceleration magnitude over the step window (m/s^2),
  /// useful for distinguishing standing/walking on replay.
  final double accelMag;

  /// Mean angular speed magnitude over the step window (rad/s).
  final double gyroMag;

  /// Optional barometer pressure (hPa). Null when the device has no
  /// barometer or the value is stale.
  final double? pressureHpa;

  /// Optional short voice landmark recorded by the user
  /// (e.g. "pharmacy", "elevator"). Plain string; up to ~64 chars.
  final String? landmark;

  /// Sample timestamp.
  final DateTime at;

  const IndoorTrailSample({
    required this.stepIndex,
    required this.headingDeg,
    required this.magMicroT,
    required this.accelMag,
    required this.gyroMag,
    required this.at,
    this.pressureHpa,
    this.landmark,
  });

  Map<String, dynamic> toJson() => {
        'i': stepIndex,
        'h': _round(headingDeg, 1),
        'm': _round(magMicroT, 2),
        'a': _round(accelMag, 2),
        'g': _round(gyroMag, 2),
        if (pressureHpa != null) 'p': _round(pressureHpa!, 1),
        if (landmark != null && landmark!.isNotEmpty) 'l': landmark,
        't': at.millisecondsSinceEpoch,
      };

  factory IndoorTrailSample.fromJson(Map<String, dynamic> json) =>
      IndoorTrailSample(
        stepIndex: (json['i'] as num).toInt(),
        headingDeg: (json['h'] as num).toDouble(),
        magMicroT: (json['m'] as num).toDouble(),
        accelMag: (json['a'] as num).toDouble(),
        gyroMag: (json['g'] as num).toDouble(),
        pressureHpa: json['p'] == null ? null : (json['p'] as num).toDouble(),
        landmark: json['l'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(
          (json['t'] as num).toInt(),
        ),
      );

  static double _round(double v, int places) {
    final f = _pow10(places);
    return (v * f).roundToDouble() / f;
  }

  static double _pow10(int n) {
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      r *= 10.0;
    }
    return r;
  }
}

/// A recorded trail (named, persisted). Trails are stored as JSON files
/// under the app documents directory, never uploaded.
class IndoorTrail {
  /// Stable identifier (slug of [name] + creation timestamp). Used as
  /// the filename without extension.
  final String id;

  /// Human-readable name the user spoke when starting the recording
  /// (e.g. "pharmacy", "elevator", "office").
  final String name;

  /// Two-letter language code the name was recorded in (`ru`, `kk`,
  /// `en`). Influences how `IndoorTrailReplay` formats prompts.
  final String langCode;

  /// Creation time.
  final DateTime createdAt;

  /// Total number of samples in the trail.
  final int sampleCount;

  /// Trail samples in recording order. May be empty if the trail was
  /// aborted before any step was registered.
  final List<IndoorTrailSample> samples;

  const IndoorTrail({
    required this.id,
    required this.name,
    required this.langCode,
    required this.createdAt,
    required this.samples,
  }) : sampleCount = samples.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lang': langCode,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'samples': samples.map((s) => s.toJson()).toList(),
        'v': 1,
      };

  factory IndoorTrail.fromJson(Map<String, dynamic> json) {
    final raw = json['samples'];
    final samples = <IndoorTrailSample>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          samples.add(IndoorTrailSample.fromJson(entry));
        }
      }
    }
    return IndoorTrail(
      id: json['id'] as String,
      name: json['name'] as String,
      langCode: (json['lang'] as String?) ?? 'ru',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num).toInt(),
      ),
      samples: samples,
    );
  }

  String encode() => jsonEncode(toJson());

  static IndoorTrail decode(String raw) =>
      IndoorTrail.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Generate a stable id from a name + timestamp. Lower-case ASCII +
  /// digits + dashes; no path separators.
  static String makeId(String name, DateTime at) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яёіңғүұқөһәій]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final ts = at.millisecondsSinceEpoch.toRadixString(36);
    return slug.isEmpty ? 'trail-$ts' : '$slug-$ts';
  }
}
