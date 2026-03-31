import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tracker/track.dart';

class Mapping {
  final double scale, dx, dy;
  const Mapping(this.scale, this.dx, this.dy);

  Rect toRect(double x1, double y1, double x2, double y2) => Rect.fromLTRB(
        x1 * scale + dx,
        y1 * scale + dy,
        x2 * scale + dx,
        y2 * scale + dy,
      );
}

Mapping mapImageToCanvas({
  required Size canvasSize,
  required double imgW,
  required double imgH,
}) {
  final scaleX = canvasSize.width / imgW;
  final scaleY = canvasSize.height / imgH;
  final scale = math.max(scaleX, scaleY);
  final dx = (canvasSize.width - imgW * scale) / 2.0;
  final dy = (canvasSize.height - imgH * scale) / 2.0;
  return Mapping(scale, dx, dy);
}

class TrackPainter extends CustomPainter {
  final List<Track> tracks;
  final int imgW, imgH;
  final Size? previewSize;

  const TrackPainter({
    required this.tracks,
    required this.imgW,
    required this.imgH,
    required this.previewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tracks.isEmpty || imgW == 0 || imgH == 0) return;

    final mapping = mapImageToCanvas(
      canvasSize: size,
      imgW: imgW.toDouble(),
      imgH: imgH.toDouble(),
    );

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    for (final t in tracks) {
      boxPaint.color = t.dist == 'very close'
          ? Colors.red
          : t.dist == 'close'
              ? Colors.orangeAccent
              : Colors.greenAccent;

      final rect = mapping.toRect(t.x1, t.y1, t.x2, t.y2);
      canvas.drawRect(rect, boxPaint);

      if (t.approaching) {
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..color = Colors.yellow.withValues(alpha: 0.6);
        canvas.drawRect(rect.inflate(3), glowPaint);
      }

      final distLabel = t.distM > 0 ? ' ~${t.distM.toStringAsFixed(1)}m' : '';

      textPainter.text = TextSpan(
        text: '${t.label}$distLabel',
        style: const TextStyle(
          color:           Colors.white,
          fontSize:        13,
          backgroundColor: Colors.black54,
        ),
      );
      textPainter.layout(maxWidth: math.max(30, rect.width));
      textPainter.paint(
          canvas, Offset(rect.left, math.max(0, rect.top - 18)));
    }
  }

  @override
  bool shouldRepaint(covariant TrackPainter old) =>
      old.tracks != tracks || old.imgW != imgW || old.imgH != imgH;
}
