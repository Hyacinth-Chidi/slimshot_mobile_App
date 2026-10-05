import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A pane of frosted glass: what is behind it, blurred, under a fill that
/// runs from a white sheen through purple, with a lilac glow pooled in the
/// far corner and an edge that catches the light at the top left.
///
/// Made for surfaces over the home screen's colour field (`HomeBackdrop`).
/// The cards there used to be tinted Zinc grey, which over purple reads as
/// mud rather than glass. A plain white sheen fixed that but left each card
/// a window onto whatever was behind it; mixing white into purple gives the
/// card a look of its own — designed, rather than cut out of the backdrop.
///
/// [tint] colours the pane — a pressed card glows purple through it — and
/// defaults to none.
class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    super.key,
    required this.borderRadius,
    required this.child,
    this.tint,
    this.blurSigma = 22,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final Color? tint;
  final double blurSigma;

  /// The fill, top left to bottom right: white where the light comes from,
  /// a purple wash through the middle, deep purple where it falls away.
  static final List<Color> fill = [
    AppColors.textPrimary.withValues(alpha: 0.16),
    AppColors.primaryStart.withValues(alpha: 0.14),
    AppColors.primaryEnd.withValues(alpha: 0.24),
  ];
  static const List<double> _fillStops = [0.0, 0.55, 1.0];

  /// The glow pooled in the bottom right corner.
  static final Color glow = AppColors.lilac.withValues(alpha: 0.20);

  /// The edge, bright at the top left and nearly gone at the bottom right.
  static final Color edgeLit = AppColors.textPrimary.withValues(alpha: 0.30);
  static final Color edgeShade = AppColors.textPrimary.withValues(alpha: 0.06);

  @override
  Widget build(BuildContext context) {
    final tint = this.tint;
    final pane = CustomPaint(
      foregroundPainter: _GlassEdgePainter(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              for (final c in fill)
                if (tint == null) c else Color.alphaBlend(tint, c),
            ],
            stops: _fillStops,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: RadialGradient(
              center: Alignment.bottomRight,
              radius: 1.1,
              colors: [glow, glow.withValues(alpha: 0)],
            ),
          ),
          child: child,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: borderRadius,
      // A blur behind a pane its content covers anyway (a thumbnail) is a
      // full blur pass for nothing; such a pane passes 0.
      child: blurSigma <= 0
          ? pane
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: pane,
            ),
    );
  }
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(this.borderRadius);

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Inset by half the stroke so the whole line sits inside the clip.
    final rrect = borderRadius.toRRect(rect).deflate(0.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          FrostedGlass.edgeLit,
          FrostedGlass.edgeShade,
          FrostedGlass.edgeShade,
          FrostedGlass.edgeLit.withValues(alpha: 0.14),
        ],
        stops: const [0.0, 0.45, 0.8, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
}
