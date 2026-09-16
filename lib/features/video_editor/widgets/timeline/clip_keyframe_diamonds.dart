import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/video_segment.dart';
import '../../providers/video_editor_notifier.dart';

/// The diamonds that mark a clip's keyframed instants, drawn **on the
/// filmstrip**.
///
/// On the thumbnail rather than in a row of its own, for two reasons. It is
/// where a user looking for them expects them — and a row is a lie about what a
/// keyframe is here: a row implies one lane per animated property, while a
/// diamond pins every property at once. It also costs the timeline no height;
/// the row this replaces pushed every lane down whenever it opened.
///
/// **Drawn inside the clip's own layout box**, so it inherits the filmstrip's
/// position through trims, reorders and transition overlaps without a second
/// copy of the geometry — positioned by `_clipLayouts()` like everything else
/// on the clip track.
///
/// **The selection is the playhead.** A diamond draws as selected when the
/// playhead is on it; there is no stored selection that could fall out of step
/// with the playback bar's plus/minus control.
///
/// **Long-press-drag moves a diamond.** Tap seeks, and a plain drag anywhere
/// on the filmstrip scrubs or reorders, so moving is the gesture those leave
/// free — the same one that picks up a clip. The playhead rides along, one
/// undo snapshot covers the drag, and the diamond stops short of a neighbour
/// rather than merging into it (`moveKeyframe`).
class ClipKeyframeDiamonds extends ConsumerStatefulWidget {
  const ClipKeyframeDiamonds({
    super.key,
    required this.segment,
    required this.widthPx,
    required this.height,
  });

  final VideoSegment segment;

  /// The clip's drawn width, which is what a progress is laid out across.
  final double widthPx;

  /// The filmstrip's height, so a diamond can sit at its vertical centre.
  final double height;

  /// How wide a diamond's touch target is, regardless of how it is drawn.
  ///
  /// An 11px diamond is a legible mark and an impossible target. The hit area
  /// is a comfortable square centred on the same point — the same split the
  /// trim handles make.
  static const double _kHitSize = 32.0;

  /// How big a diamond is drawn.
  static const double _kDiamondSize = 11.0;

  @override
  ConsumerState<ClipKeyframeDiamonds> createState() => _ClipKeyframeDiamondsState();
}

class _ClipKeyframeDiamondsState extends ConsumerState<ClipKeyframeDiamonds> {
  /// Where the dragged diamond was picked up, and where it is now. The
  /// diamond's identity is its progress, so each accepted move re-anchors
  /// [_dragCurrent]; a refused move leaves it, and the finger keeps dragging
  /// from where the diamond really is.
  double? _dragOrigin;
  double? _dragCurrent;

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final progresses = editorState.selectedClipKeyframes;
    if (progresses.isEmpty) return const SizedBox.shrink();

    final selected = editorState.playheadKeyframeProgress;

    return SizedBox(
      width: widget.widthPx,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final progress in progresses)
            Positioned(
              left: progress * widget.widthPx - ClipKeyframeDiamonds._kHitSize / 2,
              // Vertically centred on the thumbnail — not above it and not
              // below it.
              top: (widget.height - ClipKeyframeDiamonds._kHitSize) / 2,
              width: ClipKeyframeDiamonds._kHitSize,
              height: ClipKeyframeDiamonds._kHitSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tapping a diamond moves the playhead onto it, which is what
                // makes the playback bar's control flip to minus — the flip
                // reads the playhead, so the playhead has to actually arrive.
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.seekToKeyframe(progress);
                },
                onLongPressStart: (_) {
                  HapticFeedback.mediumImpact();
                  // One snapshot for the whole drag; the frames write live.
                  notifier.saveStateForUndo();
                  _dragOrigin = progress;
                  _dragCurrent = progress;
                },
                onLongPressMoveUpdate: (details) {
                  final origin = _dragOrigin;
                  final current = _dragCurrent;
                  if (origin == null || current == null) return;
                  // Pixels of travel since the pick-up, as a fraction of the
                  // clip's drawn width — the same mapping the diamonds are
                  // laid out with.
                  final to = origin + details.offsetFromOrigin.dx / widget.widthPx;
                  final moved = notifier.moveKeyframeLive(current, to);
                  if (moved != null) _dragCurrent = moved;
                },
                onLongPressEnd: (_) {
                  _dragOrigin = null;
                  _dragCurrent = null;
                },
                onLongPressCancel: () {
                  _dragOrigin = null;
                  _dragCurrent = null;
                },
                child: Center(
                  child: KeyframeDiamond(
                    isSelected: selected != null &&
                        (selected - progress).abs() <= 1e-6,
                    size: ClipKeyframeDiamonds._kDiamondSize,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A diamond, drawn as a square on its corner.
///
/// Its own widget so tests can find diamonds *as diamonds* and read their state
/// off them, rather than counting boxes.
///
/// **Outlined as well as filled.** This draws over arbitrary footage, and a
/// plain white diamond disappears on a bright thumbnail — the dark border is
/// what keeps it legible on a snow scene as well as on a night one.
class KeyframeDiamond extends StatelessWidget {
  const KeyframeDiamond({
    super.key,
    required this.isSelected,
    this.size = 11.0,
  });

  final bool isSelected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.785398, // 45°: a square on its corner is a diamond.
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryStart : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.black54,
            width: 1.2,
          ),
        ),
      ),
    );
  }
}
