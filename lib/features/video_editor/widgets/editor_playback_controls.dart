import 'package:flutter/material.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/theme/app_colors.dart';

class EditorPlaybackControls extends StatelessWidget {
  const EditorPlaybackControls({
    super.key,
    required this.isPlaying,
    required this.timelineLabel,
    required this.canUndo,
    required this.canRedo,
    required this.onTogglePreview,
    required this.onUndo,
    required this.onRedo,
    this.onExpandPreview,
    this.showsKeyframeControls = false,
    this.isOnKeyframe = false,
    this.canEditCurve = false,
    this.canToggleKeyframe = true,
    this.onToggleKeyframe,
    this.onOpenEasing,
  });

  final bool isPlaying;
  final String timelineLabel;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onTogglePreview;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback? onExpandPreview;

  /// Whether the keyframe controls are shown at all.
  ///
  /// **Only while a clip is selected.** A keyframe belongs to a clip; with none
  /// selected there is nothing for the button to act on, and a control that is
  /// present but inert is a control that lies.
  final bool showsKeyframeControls;

  /// Whether the playhead is sitting on a diamond, which flips the control from
  /// "place one here" to "remove this one".
  final bool isOnKeyframe;

  /// Whether the curve control has anything to shape.
  ///
  /// **Disabled, not hidden.** A curve needs two diamonds to run between, so it
  /// is inert until there are — and a control that vanishes and reappears is
  /// harder to find than one that dims. Dimming also teaches what it wants:
  /// place a second diamond and it lights up.
  final bool canEditCurve;

  /// Whether the playhead is on an instant of the selected clip at all.
  ///
  /// A clip stays selected while the playhead moves onto its neighbour. There
  /// is then no instant of *this* clip to pin, so the toggle dims — the same
  /// disabled-not-hidden rule as the curve — rather than acting on an edge.
  final bool canToggleKeyframe;

  final VoidCallback? onToggleKeyframe;
  final VoidCallback? onOpenEasing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onTogglePreview,
                child: Icon(
                  isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: AppColors.textPrimary,
                  size: 24,
                ),
              ),
              if (showsKeyframeControls) ...[
                const SizedBox(width: 18),
                GestureDetector(
                  key: const Key('keyframe_toggle'),
                  onTap: canToggleKeyframe ? onToggleKeyframe : null,
                  // **One control, not two.** "Place a diamond here" and
                  // "remove this one" are never both available at the same
                  // instant, so a second button would always have one of them
                  // dead.
                  child: KeyframeToggleIcon(
                    isOnKeyframe: isOnKeyframe,
                    enabled: canToggleKeyframe,
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  key: const Key('keyframe_easing'),
                  onTap: canEditCurve ? onOpenEasing : null,
                  child: Icon(
                    LucideIcons.spline,
                    color: canEditCurve
                        ? AppColors.textSecondary
                        : AppColors.textTertiary.withValues(alpha: 0.3),
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
          Text(
            timelineLabel,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onExpandPreview,
                child: const Icon(
                  LucideIcons.maximize,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: canUndo ? onUndo : null,
                child: Icon(
                  LucideIcons.undo2,
                  color: canUndo ? AppColors.textSecondary : AppColors.textTertiary.withValues(alpha: 0.3),
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: canRedo ? onRedo : null,
                child: Icon(
                  LucideIcons.redo2,
                  color: canRedo ? AppColors.textSecondary : AppColors.textTertiary.withValues(alpha: 0.3),
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The diamond-with-plus / diamond-with-minus control.
///
/// **Drawn rather than taken from the icon set.** `lucide_icons` 0.257.0 is a
/// snapshot of Lucide that predates `diamond-plus` and `diamond-minus`; it ships
/// `diamond`, `plus` and `minus` and nothing between them. Substituting an
/// unrelated icon was the other option and is worse: the diamond is how the
/// control is recognised, and it has to match the diamonds on the thumbnail.
class KeyframeToggleIcon extends StatelessWidget {
  const KeyframeToggleIcon({
    super.key,
    required this.isOnKeyframe,
    this.enabled = true,
  });

  /// True when the playhead is on a diamond, so the control removes rather than
  /// places.
  final bool isOnKeyframe;

  /// False when there is no instant of the clip under the playhead; drawn dim,
  /// the same way the curve icon dims with nothing to shape.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // On a diamond the mark is "live" — it is the one thing on screen the
    // control is about — so it fills; off one it is an outline, the same
    // unselected/selected language the diamonds on the filmstrip use.
    final colour = !enabled
        ? AppColors.textTertiary.withValues(alpha: 0.3)
        : isOnKeyframe
            ? AppColors.primaryStart
            : AppColors.textPrimary;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: 0.785398, // 45°: a square on its corner is a diamond.
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: isOnKeyframe ? colour : Colors.transparent,
                border: Border.all(color: colour, width: 1.6),
              ),
            ),
          ),
          Icon(
            isOnKeyframe ? LucideIcons.minus : LucideIcons.plus,
            size: 10,
            color: isOnKeyframe ? Colors.white : colour,
          ),
        ],
      ),
    );
  }
}
