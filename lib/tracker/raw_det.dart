class RawDet {
  final String label;
  final double x1, y1, x2, y2;
  final double cx, cy;
  final double conf;
  final String dist;
  final double distM;

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
  });
}
