import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/mask/clip_mask.dart';
import '../../models/video_editor_state.dart';
import '../../providers/video_editor_notifier.dart';
import '../overlay_content_box.dart';
import 'value_ruler.dart';

/// How much one pixel of ruler travel changes the feather (0..0.5 range).
const double kMaskFeatherPerPixel = 0.002;

/// A shape tile's square: as large as six across the panel allow, never
/// smaller than a comfortable touch, never so large the row dwarfs the ruler.
const double _kTileMin = 44;
const double _kTileMax = 56;
const double _kTileGap = 8;
const double _kLabelGap = 4;
const double _kLabelHeight = 14;

/// The Mask tool's panel: a shape, a feather and an invert.
///
/// **An in-place panel, not a sheet**, because the window itself is placed on
/// the canvas — drag to move it, pinch to resize, twist to tilt — and a sheet would cover the
/// surface being edited. The panel holds only what the canvas cannot: which
/// shape, how soft its edge, and which side to keep. Every change writes live
/// through `setMaskOnSelection`; a ruler drag is one undo step.
///
/// **It has no ✕ / title / ✓ bar** (`toolPanelHasHeader`): every change is
/// already applied, so the bar was two buttons that both just closed it. The
/// shapes are tiles in its place.
///
/// Switching shape keeps the window where it is: the user placed it, and a
/// different outline around the same place is what they mean. Circle alone
/// resizes it, to be round on the picture (`maskWithShape`).
/// The shapes as the panel offers them: the two line shapes side by side, as
/// CapCut groups them. The enum's own order is the wire's and append-only, so
/// it cannot be the panel's.
const List<ClipMaskShape> _kShapeOrder = [
  ClipMaskShape.none,
  ClipMaskShape.rectangle,
  ClipMaskShape.circle,
  ClipMaskShape.linear,
  ClipMaskShape.mirror,
  ClipMaskShape.roundedRectangle,
];

class MaskPanel extends ConsumerWidget {
  const MaskPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    // The panel serves a clip, a photo overlay or a video overlay — whichever
    // is selected — so a shape means the same thing wherever it is applied and
    // there is no second mask editor to drift from this one.
    final hasTarget = state.selectedSegment != null ||
        state.selectedImageId != null ||
        state.selectedVideoOverlayId != null;
    if (!hasTarget) {
      return const Center(
        child: Text(
          'Select a clip or an overlay to mask it.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }
    final mask = notifier.maskOnSelection;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The row takes the width it is given: six tiles fit across a 360dp
        // phone, and only a narrower one scrolls.
        LayoutBuilder(
          builder: (context, constraints) {
            final count = _kShapeOrder.length;
            final side = ((constraints.maxWidth - _kTileGap * (count - 1)) / count)
                .clamp(_kTileMin, _kTileMax)
                .toDouble();
            return SizedBox(
              height: side + _kLabelGap + _kLabelHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(width: _kTileGap),
                itemBuilder: (context, index) {
                  final shape = _kShapeOrder[index];
                  return _shapeTile(
                    shape: shape,
                    side: side,
                    active: mask.shape == shape,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      notifier.setMaskOnSelection(maskWithShape(
                        mask,
                        shape,
                        aspect: _pictureAspect(state),
                      ));
                    },
                  );
                },
              ),
            );
          },
        ),
        if (!mask.isNone) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 56,
                child: Text(
                  'Feather',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ValueRuler(
                  value: mask.feather,
                  min: 0.0,
                  max: 0.5,
                  unitsPerPixel: kMaskFeatherPerPixel,
                  snapPoints: const [0.05],
                  format: (v) => '${(v * 100).round()}%',
                  onChangeStart: notifier.saveStateForUndo,
                  onChanged: (v) => notifier.setMaskOnSelection(
                    mask.copyWith(feather: v),
                    takeUndoSnapshot: false,
                  ),
                  onReset: () => notifier.setMaskOnSelection(mask.copyWith(feather: 0.05)),
                ),
              ),
              const SizedBox(width: 10),
              _toggle(
                key: const Key('mask_invert'),
                icon: LucideIcons.flipVertical2,
                label: 'Invert',
                on: mask.inverted,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.setMaskOnSelection(mask.copyWith(inverted: !mask.inverted));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Drag to move, pinch to resize, twist to tilt.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
      ],
    );
  }

  static String _label(ClipMaskShape s) => switch (s) {
        ClipMaskShape.none => 'None',
        ClipMaskShape.rectangle => 'Rectangle',
        ClipMaskShape.circle => 'Circle',
        ClipMaskShape.linear => 'Linear',
        ClipMaskShape.roundedRectangle => 'Rounded',
        ClipMaskShape.mirror => 'Mirror',
      };

  /// The shape of the picture the window is drawn on, width over height in
  /// pixels — what makes a Circle round. The same selection [maskOnSelection]
  /// serves, a clip first: a clip's picture as the canvas fits it, an
  /// overlay's as its box measured it. Null until known, read as square.
  static double? _pictureAspect(VideoEditorState state) {
    final segment = state.selectedSegment;
    if (segment != null) return state.maskPictureAspect(segment);
    final imageId = state.selectedImageId;
    if (imageId != null) {
      for (final o in state.imageOverlays) {
        if (o.id == imageId) return OverlayContentBox.cachedAspect(o.imagePath);
      }
    }
    final videoId = state.selectedVideoOverlayId;
    if (videoId != null) {
      for (final o in state.videoOverlays) {
        if (o.id == videoId) return OverlayContentBox.cachedAspect(o.videoPath);
      }
    }
    return null;
  }

  /// A shape as a tile, CapCut's way: a picture of the shape, its name small
  /// under it. Styled as the crop panel's ratio tiles — the purple accent over
  /// a resting border for the chosen one — so the two in-place panels read as
  /// one family. The name scales down rather than overflow at large text.
  Widget _shapeTile({
    required ClipMaskShape shape,
    required double side,
    required bool active,
    required VoidCallback onTap,
  }) {
    final ink = active ? AppColors.textPrimary : AppColors.textSecondary;
    return GestureDetector(
      key: Key('mask_shape_${shape.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: side,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? AppColors.primaryStart : AppColors.border,
                  width: 2,
                ),
              ),
              child: CustomPaint(painter: _MaskShapeGlyph(shape, ink)),
            ),
            const SizedBox(height: _kLabelGap),
            SizedBox(
              height: _kLabelHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _label(shape),
                  maxLines: 1,
                  style: TextStyle(
                    color: ink,
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A toggle in the sheets' selection language, as the Transform sheet's
  /// flips are drawn.
  Widget _toggle({
    required Key key,
    required IconData icon,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.highlight : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on ? AppColors.primaryStart : AppColors.border,
            width: on ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: on ? AppColors.textPrimary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: on ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Each shape drawn as what it does, untilted: a picture reads at tile size
/// where the old 14px icons — a text-alignment glyph for Linear, an equals
/// sign for Mirror — only stood in for one. Linear keeps the left of a
/// vertical line; Mirror keeps the band between two horizontal ones.
class _MaskShapeGlyph extends CustomPainter {
  const _MaskShapeGlyph(this.shape, this.color);

  final ClipMaskShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    // The glyph's edge, about half the tile, so every shape sits in the same
    // square of air.
    final e = size.shortestSide * 0.46;
    final box = Rect.fromCenter(center: c, width: e, height: e * 0.72);

    switch (shape) {
      case ClipMaskShape.none:
        canvas.drawCircle(c, e / 2, pen);
        final d = e / 2 * math.sqrt1_2;
        canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), pen);
      case ClipMaskShape.rectangle:
        canvas.drawRect(box, pen);
      case ClipMaskShape.circle:
        canvas.drawCircle(c, e / 2, pen);
      case ClipMaskShape.linear:
        canvas.drawLine(c + Offset(0, -e / 2), c + Offset(0, e / 2), pen);
      case ClipMaskShape.mirror:
        for (final dy in [-e * 0.18, e * 0.18]) {
          canvas.drawLine(c + Offset(-e / 2, dy), c + Offset(e / 2, dy), pen);
        }
      case ClipMaskShape.roundedRectangle:
        canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(e * 0.2)), pen);
    }
  }

  @override
  bool shouldRepaint(_MaskShapeGlyph old) => old.shape != shape || old.color != color;
}
