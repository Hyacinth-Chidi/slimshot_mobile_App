import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The home screen's colour field: soft purple, lilac and white light behind
/// the glass cards, in the manner of a Figma blurred-shapes background.
///
/// The cards blur what is behind them, and over a flat near-black there was
/// nothing for the blur to show. Varying colour gives it something to soften.
///
/// Each blob is a radial gradient with a Gaussian-like falloff rather than a
/// shape run through `ImageFiltered`: the two look alike, but a full-screen
/// blur would be recomputed on every frame of a scroll, and this costs
/// nothing beyond a gradient fill. Sizes and places are fractions of the
/// screen, so a tablet gets the same composition as a phone.
class HomeBackdrop extends StatelessWidget {
  const HomeBackdrop({super.key});

  /// Purple and white mixed — the lilac between the two.
  static final Color _lilac =
      Color.lerp(AppColors.primaryStart, AppColors.textPrimary, 0.55)!;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Main purple light, upper right.
              _blob(
                color: AppColors.primaryStart,
                opacity: 0.85,
                centre: Offset(w * 0.90, h * 0.08),
                width: w * 1.6,
                height: w * 1.3,
              ),
              // Lilac, sweeping in from the left.
              _blob(
                color: _lilac,
                opacity: 0.55,
                centre: Offset(w * 0.0, h * 0.34),
                width: w * 1.3,
                height: w * 1.0,
              ),
              // White bloom where the two meet.
              _blob(
                color: AppColors.textPrimary,
                opacity: 0.22,
                centre: Offset(w * 0.40, h * 0.22),
                width: w * 0.9,
                height: w * 0.65,
              ),
              // Deep purple, low right, so the lower cards sit on colour too.
              _blob(
                color: AppColors.primaryEnd,
                opacity: 0.95,
                centre: Offset(w * 0.95, h * 0.70),
                width: w * 1.7,
                height: w * 1.4,
              ),
              // Purple through the middle, joining the top and bottom.
              _blob(
                color: AppColors.primaryStart,
                opacity: 0.40,
                centre: Offset(w * 0.30, h * 0.55),
                width: w * 1.2,
                height: w * 0.9,
              ),
              // Lilac again, lower left.
              _blob(
                color: _lilac,
                opacity: 0.40,
                centre: Offset(w * 0.05, h * 0.95),
                width: w * 1.2,
                height: w * 0.9,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _blob({
    required Color color,
    required double opacity,
    required Offset centre,
    required double width,
    required double height,
  }) {
    // A circle stretched into an ellipse: RadialGradient is round in its box,
    // so the box is drawn square and scaled.
    final size = width;
    return Positioned(
      left: centre.dx - size / 2,
      top: centre.dy - size / 2,
      width: size,
      height: size,
      child: Transform.scale(
        scaleY: height / width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: opacity * 0.72),
                color.withValues(alpha: opacity * 0.36),
                color.withValues(alpha: opacity * 0.10),
                color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
