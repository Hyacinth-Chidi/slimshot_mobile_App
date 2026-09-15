import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/animatable_double.dart';
import '../../models/video_editor_state.dart';
import '../../models/video_segment.dart';
import '../../providers/video_editor_notifier.dart';

/// The diamonds that pin a clip effect's intensity to moments of the clip.
///
/// **This widget only exists once a user has asked for it.** The timeline
/// builds it while [VideoEditorState.showsKeyframeRowFor] is true for the
/// selected clip, and nothing sets that but the effects panel's Keyframe
/// button. Someone who taps an effect and leaves — the path most projects take
/// — never sees a diamond, which is the whole shape of the two audiences this
/// feature serves.
///
/// **It does not decide anything about precedence.** Keyframes override the
/// envelope entirely, and that rule lives once, in
/// [AnimatableDouble.resolveAt]. There is no mode here to enter, nothing to
/// switch off, and the envelope is never stripped from the parameter: deleting
/// the last diamond hands the clip back the shape its effect was applied with.
///
/// Geometry is the clip's **effect progress**, 0..1, not seconds and not the
/// whole clip. For a timed effect (an intro) progress runs across
/// [VideoEffect.introSeconds] and then sits at 1, so the row spans exactly the
/// window the effect animates over — drawing diamonds across the whole clip
/// would put them where moving one changes nothing. [progressSpanSeconds]
/// carries that window and [KeyframeRow] converts at its own edge, so one
/// definition of the clock serves the row, the shader and the export.
class KeyframeRow extends ConsumerStatefulWidget {
  const KeyframeRow({
    super.key,
    required this.segment,
    required this.leftPx,
    required this.widthPx,
    required this.height,
    required this.playheadProgress,
    required this.selectedProgress,
    required this.onSelectionChanged,
  });

  /// The clip whose effect intensity is being edited.
  final VideoSegment segment;

  /// Where the clip sits on the timeline and how wide it is drawn, in the same
  /// pixels every other clip-track widget is positioned with — the row is a
  /// strip under one clip, so it has to tile with it exactly.
  final double leftPx;
  final double widthPx;
  final double height;

  /// Where the playhead is in the effect's progress space, or null when it is
  /// not over this clip at all.
  ///
  /// Resolved by the timeline, which owns the mapping from a timeline instant
  /// to a clip: a row that computed it from its own copy of the geometry would
  /// be a second interpretation of the timeline, which is exactly what the
  /// deleted preview cache did.
  final double? playheadProgress;

  /// Which diamond is selected, and how to change that.
  ///
  /// Selection is held by the timeline rather than by this row because the
  /// controls that act on it ([KeyframeRowControls]) sit outside the scrolling
  /// content — two widgets acting on one selection need one owner, or Delete
  /// would be enabled while nothing on the row looked chosen.
  final double? selectedProgress;
  final ValueChanged<double?> onSelectionChanged;

  @override
  ConsumerState<KeyframeRow> createState() => _KeyframeRowState();
}

class _KeyframeRowState extends ConsumerState<KeyframeRow> {
  /// Half a diamond, and the radius within which a tap counts as hitting one.
  static const double _kDiamondSize = 12.0;

  /// How wide a diamond's touch target is, regardless of how it is drawn.
  ///
  /// A 12px diamond is a legible mark and an impossible target. The hit area is
  /// the same rule the trim handles follow: draw small, catch large.
  static const double _kTouchWidth = 36.0;

  /// Which keyframe the live drag is holding, addressed by its **progress**
  /// rather than by its index in the list.
  ///
  /// The list is kept sorted, so dragging one diamond past another renumbers
  /// the rest — an index captured at gesture start would begin moving somebody
  /// else's keyframe halfway through the drag. This address is rewritten every
  /// frame to wherever the held keyframe now sits.
  double? _dragKeyframeProgress;

  /// The anchor the drag is measured from: the finger's x where it went down,
  /// and the keyframe's progress at that instant.
  ///
  /// **A drag is `anchorValue + (fingerX - anchorX)`, never a running sum of
  /// per-frame deltas.** A delta dropped by the 0..1 clamp at either end is
  /// lost for good, and the diamond then sits offset from the finger by however
  /// far it was pushed past the limit — dragging back does nothing until the
  /// overshoot has been paid off. The same rule the trim handles are written to.
  double _dragAnchorGlobalX = 0.0;
  double _dragAnchorProgress = 0.0;

  double _progressToPx(double progress) => progress * widget.widthPx;

  /// The clip's parameter **as the provider currently holds it**.
  ///
  /// Watched, not taken from [KeyframeRow.segment]: a drag writes a keyframe
  /// per frame, and a row painting from a segment captured by its parent would
  /// lag the edit it is making. Watching is also what keeps the `autoDispose`
  /// provider alive while the row is the only thing on screen using it —
  /// `ref.read` alone subscribes to nothing, and the notifier would be reaped
  /// out from under the gestures.
  AnimatableDouble _watchParameter() {
    final state = ref.watch(videoEditorProvider);
    for (final segment in state.segments) {
      if (segment.id == widget.segment.id) return segment.effectIntensity;
    }
    return widget.segment.effectIntensity;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(videoEditorProvider.notifier);
    final keyframes = _watchParameter().keyframes;
    final playhead = widget.playheadProgress;

    return SizedBox(
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The track the diamonds sit on, so an empty row still reads as a
          // place where something can be put rather than as blank space.
          Positioned(
            left: 0,
            top: widget.height / 2 - 1,
            width: widget.widthPx,
            height: 2,
            child: const IgnorePointer(
              child: ColoredBox(color: AppColors.surfaceLight),
            ),
          ),

          // Where the playhead falls in the effect's own progress space —
          // which is where Add will place a keyframe.
          if (playhead != null)
            Positioned(
              left: _progressToPx(playhead) - 1,
              top: 0,
              width: 2,
              height: widget.height,
              child: const IgnorePointer(
                child: ColoredBox(color: AppColors.textTertiary),
              ),
            ),

          for (var i = 0; i < keyframes.length; i++)
            _diamond(notifier: notifier, keyframe: keyframes[i], index: i),
        ],
      ),
    );
  }

  Widget _diamond({
    required VideoEditorNotifier notifier,
    required Keyframe keyframe,
    required int index,
  }) {
    // The keyframe is drawn from its **stored** progress even mid-drag: the
    // drag writes live on every frame, so the stored value already is where
    // the finger is, and a second drawn-position field would be a second
    // answer to the same question.
    final isDragging = _dragKeyframeProgress != null &&
        _isSame(_dragKeyframeProgress!, keyframe.progress);
    final drawnProgress = keyframe.progress;
    final selected = widget.selectedProgress;
    final isSelected = selected != null && _isSame(selected, keyframe.progress);

    return Positioned(
      // Keyed by **position in the row**, not by the keyframe's progress. A
      // drag rewrites that progress every frame, so a progress key would give
      // the diamond a new identity per frame — Flutter would unmount the
      // element under the finger and take the live recogniser with it, and the
      // drag would stop dead after its first pixel. Three keyframes hold three
      // element slots for as long as there are three keyframes, whatever
      // instants they sit on.
      key: ValueKey('keyframe_slot_$index'),
      left: _progressToPx(drawnProgress) - _kTouchWidth / 2,
      top: 0,
      width: _kTouchWidth,
      height: widget.height,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          // Claimed on pointer-down. Left to the ordinary arena the diamond and
          // the horizontally scrolling timeline want the same gesture, and
          // neither wins until the finger has travelled `kTouchSlop` (~18px) —
          // at 50px/second that is a third of a second of drag swallowed, which
          // reads as a handle that ignored the touch and then jumped.
          _ImmediateHorizontalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  _ImmediateHorizontalDragRecognizer>(
            () => _ImmediateHorizontalDragRecognizer(debugOwner: this),
            (instance) {
              instance.onStart = (details) => _beginDrag(
                    notifier: notifier,
                    keyframe: keyframe,
                    globalX: details.globalPosition.dx,
                  );
              instance.onUpdate = (details) => _updateDrag(
                    notifier: notifier,
                    globalX: details.globalPosition.dx,
                  );
              instance.onEnd = (_) => _endDrag();
              instance.onCancel = _endDrag;
            },
          ),
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(debugOwner: this),
            (instance) {
              instance.onTap = () {
                HapticFeedback.selectionClick();
                widget.onSelectionChanged(keyframe.progress);
              };
            },
          ),
        },
        child: KeyframeDiamond(
          isSelected: isSelected,
          isDragging: isDragging,
          size: _kDiamondSize,
        ),
      ),
    );
  }

  void _beginDrag({
    required VideoEditorNotifier notifier,
    required Keyframe keyframe,
    required double globalX,
  }) {
    // **One undo entry for the whole gesture.** The snapshot is taken here and
    // every frame after it writes live; going through the snapshotting setter
    // per pointer move makes undo walk the drag back a pixel at a time.
    notifier.saveStateForUndo();
    widget.onSelectionChanged(keyframe.progress);
    setState(() {
      _dragKeyframeProgress = keyframe.progress;
      _dragAnchorGlobalX = globalX;
      _dragAnchorProgress = keyframe.progress;
    });
  }

  void _updateDrag({
    required VideoEditorNotifier notifier,
    required double globalX,
  }) {
    final from = _dragKeyframeProgress;
    if (from == null || widget.widthPx <= 0) return;

    // Absolute, from the anchor — see [_dragAnchorGlobalX].
    final next = (_dragAnchorProgress +
            (globalX - _dragAnchorGlobalX) / widget.widthPx)
        .clamp(0.0, 1.0)
        .toDouble();
    if (_isSame(next, from)) return;

    notifier.moveEffectIntensityKeyframe(from, next, takeUndoSnapshot: false);
    widget.onSelectionChanged(next);
    // The keyframe now lives at its new progress, so the address every later
    // frame of this drag uses has to move with it — otherwise the second frame
    // would look for a keyframe that is no longer where it was grabbed.
    setState(() => _dragKeyframeProgress = next);
  }

  void _endDrag() {
    if (_dragKeyframeProgress == null) return;
    setState(() => _dragKeyframeProgress = null);
  }

  static bool _isSame(double a, double b) => (a - b).abs() <= 0.001;
}

/// One keyframe's mark: a square on its corner.
///
/// A widget of its own rather than an inline `Transform` so a test can find the
/// diamonds *as diamonds* and read their state off them, instead of counting
/// render objects that the surrounding controls also produce — the same route
/// [EffectTile] and `TextAnimationTile` take.
class KeyframeDiamond extends StatelessWidget {
  const KeyframeDiamond({
    super.key,
    required this.isSelected,
    required this.isDragging,
    required this.size,
  });

  final bool isSelected;
  final bool isDragging;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.rotate(
        angle: 0.785398, // 45°: a square on its corner is a diamond.
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isSelected || isDragging
                ? AppColors.textPrimary
                : AppColors.primaryStart,
            border: Border.all(color: AppColors.background, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// A horizontal drag that claims the pointer the moment it goes down.
///
/// The diamonds sit inside a horizontally scrolling timeline, so the diamond
/// and the scroll view want the same gesture. Left to the normal arena neither
/// wins until the finger has travelled `kTouchSlop`, which is what makes a
/// handle feel like it did not pick up when touched: it ignores the start of
/// the drag and then jumps. [DragStartBehavior.down] then measures the drag
/// from the touch itself, so none of that travel is lost.
///
/// A deliberate twin of the one inside `scrollable_timeline.dart`: that one is
/// private to a 3000-line file, and reaching into it would mean either making
/// it public or moving it, both of which are edits to a file this row only
/// needs to be *positioned* by.
class _ImmediateHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _ImmediateHorizontalDragRecognizer({super.debugOwner}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// The controls beside the keyframe row: add at the playhead, delete the
/// selected diamond, and choose how it travels.
///
/// A separate widget from the row because they live in different places — the
/// row is content inside the scrolling timeline, positioned over one clip,
/// while the controls are chrome that must stay reachable whatever the timeline
/// is scrolled to. Anything interactive placed in the run-in before 00:00
/// paints but is never hit-tested (`RenderBox.hitTest` gates on `size.contains`
/// even where painting does not), which is the trap the cover card already
/// documents.
class KeyframeRowControls extends ConsumerWidget {
  const KeyframeRowControls({
    super.key,
    required this.segment,
    required this.playheadProgress,
    required this.selectedProgress,
    required this.onSelectionChanged,
  });

  final VideoSegment segment;

  /// The playhead in the effect's progress space, or null when it is not over
  /// this clip — Add is disabled then rather than guessing at an instant.
  final double? playheadProgress;

  final double? selectedProgress;
  final ValueChanged<double?> onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(videoEditorProvider.notifier);
    // Watched rather than read off the passed segment: Delete and the
    // interpolation chips light up from what the parameter holds *now*, and
    // the watch is also what keeps the `autoDispose` provider alive while
    // these controls are on screen.
    final state = ref.watch(videoEditorProvider);
    final keyframes = _liveParameter(state).keyframes;
    final selected = _selectedKeyframe(keyframes);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          icon: LucideIcons.diamond,
          label: 'Add',
          enabled: playheadProgress != null,
          onTap: () {
            final at = playheadProgress;
            if (at == null) return;
            HapticFeedback.selectionClick();
            // **No value is passed.** The keyframe takes the parameter's own
            // value at this instant, so placing one never changes the picture
            // — see [VideoEditorNotifier.addEffectIntensityKeyframe].
            notifier.addEffectIntensityKeyframe(at);
            onSelectionChanged(at);
          },
        ),
        const SizedBox(width: 8),
        _button(
          icon: LucideIcons.trash2,
          label: 'Delete',
          enabled: selected != null,
          onTap: () {
            if (selected == null) return;
            HapticFeedback.selectionClick();
            notifier.removeEffectIntensityKeyframe(selected.progress);
            onSelectionChanged(null);
          },
        ),
        const SizedBox(width: 8),
        for (final interpolation in KeyframeInterpolation.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _interpolationChip(
              interpolation: interpolation,
              selected: selected,
              onTap: () {
                if (selected == null) return;
                HapticFeedback.selectionClick();
                notifier.setEffectIntensityKeyframeInterpolation(
                  selected.progress,
                  interpolation,
                );
              },
            ),
          ),
      ],
    );
  }

  AnimatableDouble _liveParameter(VideoEditorState state) {
    for (final s in state.segments) {
      if (s.id == segment.id) return s.effectIntensity;
    }
    return segment.effectIntensity;
  }

  Keyframe? _selectedKeyframe(List<Keyframe> keyframes) {
    final progress = selectedProgress;
    if (progress == null) return null;
    for (final keyframe in keyframes) {
      if ((keyframe.progress - progress).abs() <= 0.001) return keyframe;
    }
    return null;
  }

  Widget _button({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color:
                    enabled ? AppColors.textPrimary : AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      enabled ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One interpolation choice.
  ///
  /// The flag belongs to the segment that **starts** at the selected keyframe,
  /// not the one that ends at it — see [Keyframe.interpolation] — which is what
  /// makes `Hold` mean "stay here until the next one".
  Widget _interpolationChip({
    required KeyframeInterpolation interpolation,
    required Keyframe? selected,
    required VoidCallback onTap,
  }) {
    final isActive = selected?.interpolation == interpolation;
    final enabled = selected != null;
    return Semantics(
      button: true,
      selected: isActive,
      enabled: enabled,
      label: keyframeInterpolationLabel(interpolation),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? AppColors.highlight : AppColors.surface,
            border: Border.all(
              color: isActive ? AppColors.primaryStart : AppColors.border,
            ),
          ),
          child: Text(
            keyframeInterpolationLabel(interpolation),
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// What an interpolation is called on screen.
///
/// Here rather than on the enum: the enum's names are persisted into drafts and
/// cross the channel to Kotlin, so they are identifiers, not copy — renaming
/// one is a migration. A label can change freely.
String keyframeInterpolationLabel(KeyframeInterpolation interpolation) =>
    switch (interpolation) {
      KeyframeInterpolation.linear => 'Linear',
      KeyframeInterpolation.ease => 'Ease',
      KeyframeInterpolation.hold => 'Hold',
    };
