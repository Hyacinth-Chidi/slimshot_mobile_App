import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../logic/mask/clip_mask.dart';

/// The mask window's outline over the picture it masks: the edge, and a
/// fainter line one feather out to show how far the soft edge reaches. The
/// picture itself already shows the mask live through the engine, so this
/// draws only what the engine cannot — where to grab — and, while the window
/// is being twisted, its angle.
///
/// **One painter for every mask**: the canvas uses it over a clip's fitted
/// frame, and each overlay layer inside the overlay's own box, which is
/// already turned and scaled to where the engine draws the picture. Drawn
/// turned by the window's tilt about its centre, in pixels — the turn the
/// coverage makes, rigid on the picture.
class MaskOutlinePainter extends CustomPainter {
  const MaskOutlinePainter({
    required this.mask,
    this.frame,
    this.angleLabel,
    this.strokeScale = 1.0,
    this.labelRotation = 0.0,
  });

  final ClipMask mask;

  /// The picture the mask is a fraction of, in the paint's pixels, or null
  /// for the whole paint area — an overlay's box is exactly its paint area.
  final Rect? frame;

  /// The readout while the window is being twisted, or null.
  final String? angleLabel;

  /// Multiplies line widths and the readout: an overlay's box is drawn
  /// scaled, so it passes the inverse to keep the lines one width on screen.
  final double strokeScale;

  /// Turns the readout back upright inside a turned box (radians).
  final double labelRotation;

  @override
  void paint(Canvas canvas, Size size) {
    if (mask.isNone) return;
    final frame = this.frame ?? Offset.zero & size;
    final edge = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * strokeScale;
    final soft = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 * strokeScale;

    Offset at(double fx, double fy) =>
        Offset(frame.left + fx * frame.width, frame.top + fy * frame.height);
    final centre = at(mask.centerX, mask.centerY);
    final halfW = mask.width / 2 * frame.width;
    final halfH = mask.height / 2 * frame.height;
    final featherX = mask.feather * frame.width;
    final featherY = mask.feather * frame.height;

    canvas.save();
    // A line or a band runs edge to edge, so it is cut to the picture it
    // divides.
    if (mask.shape == ClipMaskShape.linear || mask.shape == ClipMaskShape.mirror) {
      canvas.clipRect(frame);
    }
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(mask.angle * math.pi / 180);
    switch (mask.shape) {
      case ClipMaskShape.none:
        break;
      case ClipMaskShape.rectangle:
        final r = Rect.fromCenter(center: Offset.zero, width: halfW * 2, height: halfH * 2);
        canvas.drawRect(r, edge);
        canvas.drawRect(r.inflate(featherX), soft);
      case ClipMaskShape.circle:
        final r = Rect.fromCenter(center: Offset.zero, width: halfW * 2, height: halfH * 2);
        canvas.drawOval(r, edge);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: halfW * 2 + featherX * 2,
            height: halfH * 2 + featherY * 2,
          ),
          soft,
        );
      case ClipMaskShape.roundedRectangle:
        final r = Rect.fromCenter(center: Offset.zero, width: halfW * 2, height: halfH * 2);
        // The arc in canvas pixels, clamped to the box exactly as the coverage
        // clamps it — an outline wider than the shape would lie about it.
        final radius = (mask.cornerRadius * frame.width)
            .clamp(0.0, halfW < halfH ? halfW : halfH)
            .toDouble();
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), edge);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            r.inflate(featherX),
            Radius.circular(radius + featherX),
          ),
          soft,
        );
      case ClipMaskShape.mirror:
        // The band's two edges, and their soft edges one feather out.
        final reach = frame.longestSide * 2;
        for (final y in [-halfH, halfH]) {
          canvas.drawLine(Offset(-reach, y), Offset(reach, y), edge);
          final out = y < 0 ? y - featherY : y + featherY;
          canvas.drawLine(Offset(-reach, out), Offset(reach, out), soft);
        }
      case ClipMaskShape.linear:
        // Long enough to cross the picture at any tilt; the clip trims it.
        final reach = frame.longestSide * 2;
        canvas.drawLine(Offset(0, -reach), Offset(0, reach), edge);
        canvas.drawLine(Offset(-featherX, -reach), Offset(-featherX, reach), soft);
        canvas.drawLine(Offset(featherX, -reach), Offset(featherX, reach), soft);
    }
    canvas.restore();

    // A grab point at the centre, so the window reads as a thing to hold.
    final dot = 5 * strokeScale;
    canvas.drawCircle(centre, dot, Paint()..color = Colors.white);
    canvas.drawCircle(
      centre,
      dot,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * strokeScale,
    );

    final label = angleLabel;
    if (label != null) _paintAngle(canvas, frame, label);
  }

  /// The angle while twisting, in a small pill near the top of the picture —
  /// where CapCut shows its mask's angle, clear of the fingers — kept upright
  /// and one size on screen however the picture is turned or scaled.
  void _paintAngle(Canvas canvas, Rect frame, String label) {
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(frame.center.dx, frame.top + 24 * strokeScale);
    canvas.rotate(labelRotation);
    canvas.scale(strokeScale);
    final pill = Rect.fromCenter(
      center: Offset.zero,
      width: text.width + 20,
      height: text.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)),
      Paint()..color = Colors.black54,
    );
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MaskOutlinePainter old) =>
      old.mask != mask ||
      old.frame != frame ||
      old.angleLabel != angleLabel ||
      old.strokeScale != strokeScale ||
      old.labelRotation != labelRotation;
}
