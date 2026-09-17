import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/mask/clip_mask.dart';
import '../../providers/video_editor_notifier.dart';
import 'value_ruler.dart';

/// How much one pixel of ruler travel changes the feather (0..0.5 range).
const double kMaskFeatherPerPixel = 0.002;

/// The Mask tool's panel: a shape, a feather and an invert.
///
/// **An in-place panel, not a sheet**, because the window itself is placed on
/// the canvas — drag to move it, pinch to resize — and a sheet would cover the
/// surface being edited. The panel holds only what the canvas cannot: which
/// shape, how soft its edge, and which side to keep. Every change writes live
/// through `setMaskOnSelection`; a ruler drag is one undo step.
///
/// Switching shape keeps the window where it is: the user placed it, and a
/// different outline around the same place is what they mean.
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
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final shape in ClipMaskShape.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _shapeChip(
                    shape: shape,
                    active: mask.shape == shape,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (shape == ClipMaskShape.none) {
                        notifier.setMaskOnSelection(ClipMask.none);
                      } else if (mask.isNone) {
                        notifier.setMaskOnSelection(ClipMask(shape: shape));
                      } else {
                        notifier.setMaskOnSelection(mask.copyWith(shape: shape));
                      }
                    },
                  ),
                ),
            ],
          ),
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
            'Drag on the canvas to move the window; pinch to resize it.',
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
      };

  static IconData _glyph(ClipMaskShape s) => switch (s) {
        ClipMaskShape.none => LucideIcons.ban,
        ClipMaskShape.rectangle => LucideIcons.square,
        ClipMaskShape.circle => LucideIcons.circle,
        ClipMaskShape.linear => LucideIcons.alignLeft,
        ClipMaskShape.roundedRectangle => LucideIcons.squareDashedBottom,
      };

  /// The pill the other sheets use for a category: a filled capsule when
  /// active, plain text otherwise.
  Widget _shapeChip({
    required ClipMaskShape shape,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: Key('mask_shape_${shape.name}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryStart : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _glyph(shape),
              size: 14,
              color: active ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              _label(shape),
              style: TextStyle(
                color: active ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
