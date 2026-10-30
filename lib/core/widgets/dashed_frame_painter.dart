import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A rounded rectangle drawn as dashes: the frame of something not there
/// yet — the Background sheet's empty photo tile, Home's card before any
/// edit.
class DashedFramePainter extends CustomPainter {
  const DashedFramePainter({
    required this.colour,
    required this.radius,
    required this.strokeWidth,
  });

  final Color colour;
  final double radius;
  final double strokeWidth;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    for (final ui.PathMetric metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedFramePainter old) =>
      old.colour != colour || old.radius != radius || old.strokeWidth != strokeWidth;
}
