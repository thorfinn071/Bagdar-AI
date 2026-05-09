import 'dart:typed_data';

class RawDet {
  final String label;
  final double x1, y1, x2, y2;
  final double cx, cy;
  final double conf;
  final String dist;
  final double distM;
  // OPT-01: optional appearance histogram for anti-ID-switch matching in
  // the tracker. `null` means the caller didn't compute one (e.g. unit
  // tests or a pipeline without Y-plane access), in which case the tracker
  // falls back to pure IoU matching.
  final Float32List? appearance;

  const RawDet({
    required this.label,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.cx,
    required this.cy,
    required this.conf,
    required this.dist,
    required this.distM,
    this.appearance,
  });
}
