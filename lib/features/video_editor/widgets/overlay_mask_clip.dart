import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../logic/mask/clip_mask.dart';

/// Cuts a preview overlay to its [ClipMask].
///
/// **One definition of the shape, two renderers.** The export computes the
/// mask's coverage in a shader; the preview cannot — overlays there are plain
/// Flutter widgets with no shader of their own — so it clips to the same shape
/// instead. Both read the same [ClipMask], so a circle is the same circle in
/// the file and on the canvas.
///
/// What the preview cannot reproduce exactly is the **feather**: a clip is a
/// hard edge, where the shader ramps over the feather width. A soft-edged mask
/// therefore looks very slightly crisper on the canvas than in the file. That
/// is the one honest gap, and it is the right way round — nothing appears in
/// the export that the preview did not show.
///
/// The shape is authored in the overlay's **own box**, which is exactly what
/// [CustomClipper] is handed, so no conversion is needed here.
class OverlayMaskClip extends StatelessWidget {
  const OverlayMaskClip({super.key, required this.mask, required this.child});

  final ClipMask mask;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (mask.isNone) return child;
    return ClipPath(clipper: _MaskClipper(mask), child: child);
  }
}

class _MaskClipper extends CustomClipper<Path> {
  const _MaskClipper(this.mask);

  final ClipMask mask;

  @override
  Path getClip(Size size) {
    final centre = Offset(mask.centerX * size.width, mask.centerY * size.height);
    final halfW = math.max(mask.width * 0.5, kMaskMinExtent) * size.width;
    final halfH = math.max(mask.height * 0.5, kMaskMinExtent) * size.height;
    final box = Rect.fromCenter(
      center: centre,
      width: halfW * 2,
      height: halfH * 2,
    );

    switch (mask.shape) {
      case ClipMaskShape.none:
        return Path()..addRect(Offset.zero & size);
      case ClipMaskShape.rectangle:
        return Path()..addRect(box);
      case ClipMaskShape.circle:
        return Path()..addOval(box);
      case ClipMaskShape.roundedRectangle:
        // Clamped to the box exactly as the coverage clamps it, so the clip
        // and the exported shape agree at every radius.
        final radius = (mask.cornerRadius * size.width)
            .clamp(0.0, math.min(halfW, halfH))
            .toDouble();
        return Path()
          ..addRRect(RRect.fromRectAndRadius(box, Radius.circular(radius)));
      case ClipMaskShape.linear:
        // Keeps everything left of the centre, which is what the coverage
        // does; the shader's gradient becomes a straight edge here.
        final x = centre.dx;
        return Path()..addRect(Rect.fromLTRB(0, 0, x, size.height));
    }
  }

  @override
  bool shouldReclip(_MaskClipper old) => old.mask != mask;
}
