import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// One soft light behind the home and Settings screens: where it sits and
/// how big it is in fractions of the screen, so a tablet gets the same
/// composition as a phone.
@immutable
class BackdropGlow {
  const BackdropGlow({
    required this.color,
    required this.opacity,
    required this.centre,
    required this.width,
    required this.height,
  });

  final Color color;
  final double opacity;

  /// Centre as fractions of the screen's width and height.
  final Offset centre;

  /// Size as fractions of the screen's width (both axes, so the shape keeps
  /// its proportions on a tall phone).
  final double width;
  final double height;
}

/// The near-black behind the home and Settings screens, lit by a little
/// purple light.
///
/// It was briefly a full colour field — large purple, lilac and white blobs
/// over the whole screen — and on the device that read as less premium than
/// the plain near-black it replaced, with "too much purple". So the light is
/// used sparingly: one deep purple glow high on the right, a fainter one low
/// on the left, and a whisper of white where the first falls off — enough for
/// the glass cards' blur to have something to soften, and no more. A test
/// holds every glow at or under 30% and the white under 6%.
///
/// Each glow is a radial gradient with a Gaussian-like falloff rather than a
/// shape run through `ImageFiltered`: the two look alike, but a full-screen
/// blur would be recomputed on every frame of a scroll.
class ColourFieldBackdrop extends StatelessWidget {
  const ColourFieldBackdrop({super.key});

  static const List<BackdropGlow> glows = [
    // The main light, high on the right.
    BackdropGlow(
      color: AppColors.primaryStart,
      opacity: 0.26,
      centre: Offset(0.95, 0.06),
      width: 1.5,
      height: 1.2,
    ),
    // A whisper of white where it falls off, so the light has a source.
    BackdropGlow(
      color: AppColors.textPrimary,
      opacity: 0.05,
      centre: Offset(0.70, 0.02),
      width: 0.8,
      height: 0.5,
    ),
    // Deep purple low on the left, so the lower cards are not on flat black.
    BackdropGlow(
      color: AppColors.primaryEnd,
      opacity: 0.22,
      centre: Offset(0.0, 0.80),
      width: 1.4,
      height: 1.1,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [for (final g in glows) _glow(g, w, h)],
          );
        },
      ),
    );
  }

  Widget _glow(BackdropGlow g, double w, double h) {
    // A circle stretched into an ellipse: RadialGradient is round in its box,
    // so the box is drawn square and scaled.
    final size = w * g.width;
    return Positioned(
      left: g.centre.dx * w - size / 2,
      top: g.centre.dy * h - size / 2,
      width: size,
      height: size,
      child: Transform.scale(
        scaleY: g.height / g.width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                g.color.withValues(alpha: g.opacity),
                g.color.withValues(alpha: g.opacity * 0.72),
                g.color.withValues(alpha: g.opacity * 0.36),
                g.color.withValues(alpha: g.opacity * 0.10),
                g.color.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
