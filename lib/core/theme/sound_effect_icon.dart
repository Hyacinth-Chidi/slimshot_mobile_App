import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Sound effects' glyph: a beamed note with a burst at its shoulder — a
/// sound with a hit in it. Lucide has nothing like it, so it is drawn here in
/// Lucide's own manner (a 24-unit grid, round strokes) to sit beside the
/// vendored icons, and takes the size and colour an [Icon] would.
class SoundEffectIcon extends StatelessWidget {
  const SoundEffectIcon({super.key, this.size = 24, required this.color});

  final double size;
  final Color color;

  /// For a const tool declaration: `glyph: SoundEffectIcon.glyph`.
  static Widget glyph(double size, Color color) =>
      SoundEffectIcon(size: size, color: color);

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _SoundEffectPainter(color)),
      );
}

class _SoundEffectPainter extends CustomPainter {
  _SoundEffectPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 24;
    canvas.scale(unit);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final burst = _burst();
    // The burst overlaps the note's shoulder: the note is cut away under it,
    // so the two outlines do not tangle.
    canvas.saveLayer(Offset.zero & const Size(24, 24), Paint());
    _drawNote(canvas, stroke);
    canvas.drawPath(
      burst,
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      burst,
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
    canvas.drawPath(burst, stroke);

    // Short rays off the burst, the way a hit is drawn.
    for (final degrees in const [-150.0, -30.0, 30.0]) {
      final a = degrees * math.pi / 180;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(_centre + d * 6.0, _centre + d * 7.0, stroke);
    }
  }

  static const _centre = Offset(17.3, 6.6);

  /// Uneven points read as an impact; even ones read as a flower.
  static Path _burst() {
    const outer = [5.0, 3.9, 5.3, 4.0, 4.9, 3.7, 4.7];
    const inner = 2.3;
    final path = Path();
    for (var i = 0; i < outer.length * 2; i++) {
      final r = i.isEven ? outer[i ~/ 2] : inner;
      final a = -math.pi * 0.56 + i * math.pi / outer.length;
      final p = _centre + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  /// Lucide's `music`, scaled into the lower left.
  static void _drawNote(Canvas canvas, Paint stroke) {
    Offset note(double x, double y) => Offset(x * 0.68 - 1.2, y * 0.68 + 7.4);
    canvas.drawPath(
      Path()
        ..moveTo(note(9, 18).dx, note(9, 18).dy)
        ..lineTo(note(9, 5).dx, note(9, 5).dy)
        ..lineTo(note(21, 3).dx, note(21, 3).dy)
        ..lineTo(note(21, 16).dx, note(21, 16).dy),
      stroke,
    );
    canvas.drawCircle(note(6, 18), 2.05, stroke);
    canvas.drawCircle(note(18, 16), 2.05, stroke);
  }

  @override
  bool shouldRepaint(_SoundEffectPainter old) => old.color != color;
}
