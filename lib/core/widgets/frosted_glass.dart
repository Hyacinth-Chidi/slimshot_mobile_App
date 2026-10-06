import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A pane of smoked glass: what is behind it, blurred, under a faint white
/// sheen that fades from the top left, with an edge that catches the light
/// there.
///
/// Made for surfaces over the home and Settings backdrop
/// (`ColourFieldBackdrop`). The glass adds no colour of its own — a version
/// that mixed purple into the fill read, with the backdrop, as "too much
/// purple" on the device. Neutral glass over near-black, with the colour left
/// to the backdrop's light and the one solid card, is what reads as premium.
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

  /// The sheen, top left to bottom right: strongest where the light comes
  /// from, nearly gone where it falls away.
  static final List<Color> fill = [
    AppColors.textPrimary.withValues(alpha: 0.08),
    AppColors.textPrimary.withValues(alpha: 0.04),
    AppColors.textPrimary.withValues(alpha: 0.02),
  ];
  static const List<double> _fillStops = [0.0, 0.5, 1.0];

  /// The edge, lit at the top left and nearly gone at the bottom right.
  static final Color edgeLit = AppColors.textPrimary.withValues(alpha: 0.22);
  static final Color edgeShade = AppColors.textPrimary.withValues(alpha: 0.05);

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
