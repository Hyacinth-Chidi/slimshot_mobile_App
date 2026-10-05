import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A pane of frosted glass: what is behind it, blurred, under a faint white
/// sheen, with an edge that catches the light at the top left and fades
/// toward the bottom right.
///
/// Made for surfaces over the home screen's colour field (`HomeBackdrop`).
/// The cards there used to be tinted Zinc grey, which over purple reads as
/// mud rather than glass; a white sheen keeps whatever colour is behind and
/// only lifts it.
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

  /// The sheen, strongest where the light comes from.
  static final Color sheenTop = AppColors.textPrimary.withValues(alpha: 0.13);
  static final Color sheenBottom = AppColors.textPrimary.withValues(
    alpha: 0.04,
  );

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
            colors: tint == null
                ? [sheenTop, sheenBottom]
                : [
                    Color.alphaBlend(tint, sheenTop),
                    Color.alphaBlend(tint, sheenBottom),
                  ],
          ),
        ),
        child: child,
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
