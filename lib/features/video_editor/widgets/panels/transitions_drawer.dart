import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/transitions/transition_catalog.dart';
import '../../logic/transitions/transition_preview_frames.dart';
import '../../providers/transition_preview_provider.dart';
import '../../providers/video_editor_notifier.dart';
import '../text_overlay/text_preview_tile.dart';
import 'apply_to_all_toggle.dart';
import 'editor_sheet.dart';

/// One turn of every tile's loop: a rest, the transition, a rest.
const Duration _kTileLoop = Duration(milliseconds: 1800);

/// Four to a row, nearly square. Not the text grids' three: under the pills,
/// the duration and Apply to all, a sheet held to
/// [kEditorSheetPreviewFraction] of the screen leaves the grid about 180px on
/// a phone — one and a half rows of three, two and more of four — and a
/// transition reads at this size where a caption would not.
const SliverGridDelegateWithFixedCrossAxisCount kTransitionGrid =
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 4,
  childAspectRatio: 0.9,
  crossAxisSpacing: 8,
  mainAxisSpacing: 8,
);

/// The transitions sheet: category pills over a grid of tiles, each playing
/// the real transition between two sample pictures.
///
/// **A tile is the engine's own drawing** (`renderTransitionPreview`): the
/// transition's shader run between the samples and read back as frames — so a
/// tile cannot promise a look the canvas and the file do not deliver. Until
/// its frames arrive, or where the engine could not draw them, a tile shows
/// the transition's icon.
class TransitionsDrawer extends ConsumerStatefulWidget {
  const TransitionsDrawer({super.key, this.onTransitionChosen});

  /// Called with the seam's clip id after a tile applies a transition, so the
  /// screen can play it on the canvas. Not called for None.
  final ValueChanged<String>? onTransitionChosen;

  @override
  ConsumerState<TransitionsDrawer> createState() => _TransitionsDrawerState();
}

class _TransitionsDrawerState extends ConsumerState<TransitionsDrawer>
    with SingleTickerProviderStateMixin {
  /// One clock for every tile, as the text preview grids have.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: _kTileLoop)..repeat();

  /// The pill showing; null until the user picks one, which shows the
  /// category of the seam's own transition.
  TransitionCategory? _category;

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    // Use the explicitly-selected transition segment, or fall back to the
    // currently selected clip (for when opened via the edit contextual menu).
    final requestedSegmentId = editorState.selectedTransitionSegmentId
        ?? editorState.selectedSegmentId;
    var targetSegmentId = requestedSegmentId;
    if (targetSegmentId != null && editorState.segments.length > 1) {
      final requestedIndex = editorState.segments.indexWhere(
        (segment) => segment.id == targetSegmentId,
      );
      if (requestedIndex >= editorState.segments.length - 1) {
        targetSegmentId = editorState.segments[editorState.segments.length - 2].id;
      }
    }

    final resolvedTargetSegmentId = targetSegmentId;
    if (resolvedTargetSegmentId == null || editorState.segments.length < 2) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * kEditorSheetPreviewFraction,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _buildHandle(),
              const Expanded(
                child: Center(
                  child: Text(
                    'Split the video first to add\ntransitions between clips.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Auto-select if not already set
    if (editorState.selectedTransitionSegmentId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.selectTransition(resolvedTargetSegmentId);
      });
    }

    final activeSegment = editorState.segments.firstWhere(
      (s) => s.id == resolvedTargetSegmentId,
      orElse: () => editorState.segments.first,
    );

    if (activeSegment.id != resolvedTargetSegmentId) {
      return const SizedBox.shrink();
    }

    final currentTransition = activeSegment.transitionType;
    final currentDuration = activeSegment.transitionDuration ?? 0.8;
    final categories = offeredTransitionCategories();
    var category = _category ?? categoryForTransition(currentTransition);
    if (!categories.contains(category)) category = categories.first;

    // `null` is the "None" (hard cut) choice, first in every category so a cut
    // is one tap from anywhere; the rest comes straight from the catalog so
    // this grid can never drift from what preview and export support.
    final options = <EditorTransition?>[null, ...transitionsIn(category)];
    final frames = ref.watch(transitionPreviewFramesProvider);

    void choose(EditorTransition? option) {
      HapticFeedback.selectionClick();
      notifier.setSegmentTransition(option?.name, currentDuration);
      if (option != null) {
        widget.onTransitionChosen?.call(resolvedTargetSegmentId);
      }
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height * kEditorSheetPreviewFraction,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Handle
              _buildHandle(),

              ApplyToAllToggle(
                value: editorState.transitionAppliesToAll,
                enabled: editorState.segments.length > 2,
                onChanged: notifier.setTransitionAppliesToAll,
              ),

              // Duration Slider (only when a transition is selected)
              if (currentTransition != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.timer, color: AppColors.textSecondary, size: 16),
                      Expanded(
                        child: SliderTheme(
                          data: const SliderThemeData(
                            activeTrackColor: AppColors.primaryStart,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                            trackHeight: 2,
                            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: currentDuration.clamp(
                              kMinTransitionSeconds,
                              kMaxTransitionSeconds,
                            ),
                            min: kMinTransitionSeconds,
                            max: kMaxTransitionSeconds,
                            onChanged: (val) {
                              notifier.setSegmentTransition(currentTransition, val);
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${currentDuration.toStringAsFixed(1)}s',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 8),

              _categoryRow(categories, category),

              Expanded(
                child: NotificationListener<ScrollNotification>(
                  // Still while it scrolls — see [holdPreviewClockWhileScrolling].
                  onNotification: (notification) =>
                      mounted && holdPreviewClockWhileScrolling(notification, _clock),
                  child: GridView.builder(
                    key: ValueKey(category),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: kTransitionGrid,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return _TransitionTile(
                        key: ValueKey('transition_tile_${option?.name ?? 'none'}'),
                        transition: option,
                        isSelected: currentTransition == option?.name,
                        frames: frames,
                        clock: _clock,
                        onTap: () => choose(option),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The pills, in the shape the effects and easing sheets use: a filled
  /// capsule for the one showing, plain text otherwise.
  Widget _categoryRow(
    List<TransitionCategory> categories,
    TransitionCategory showing,
  ) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isActive = category == showing;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (isActive) return;
              setState(() => _category = category);
              // A grid replaced mid-scroll never reports the scroll's end.
              if (!_clock.isAnimating) _clock.repeat();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.highlight : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                category.label,
                style: TextStyle(
                  color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 16),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// One transition played between the two sample pictures — or the cut.
class _TransitionTile extends StatefulWidget {
  const _TransitionTile({
    super.key,
    required this.transition,
    required this.isSelected,
    required this.frames,
    required this.clock,
    required this.onTap,
  });

  /// Null for None.
  final EditorTransition? transition;
  final bool isSelected;
  final TransitionPreviewFrames frames;
  final Animation<double> clock;
  final VoidCallback onTap;

  @override
  State<_TransitionTile> createState() => _TransitionTileState();
}

class _TransitionTileState extends State<_TransitionTile> {
  List<Uint8List>? _frames;

  @override
  void initState() {
    super.initState();
    final name = widget.transition?.name;
    if (name == null) return;
    _frames = widget.frames.peek(name);
    if (_frames != null || widget.frames.hasFailed(name)) return;
    // Asked as the grid builds the tile, so what is on screen is drawn first.
    widget.frames.request(name).then((frames) {
      if (mounted && frames != null) setState(() => _frames = frames);
    });
  }

  @override
  Widget build(BuildContext context) {
    final transition = widget.transition;
    final frames = _frames;
    final label = transition?.label ?? 'None';

    final Widget stage = frames == null
        ? Center(
            child: Icon(
              transition?.icon ?? LucideIcons.ban,
              color: widget.isSelected
                  ? AppColors.primaryStart
                  : AppColors.textSecondary,
            ),
          )
        : AnimatedBuilder(
            animation: widget.clock,
            builder: (context, _) => Image.memory(
              frames[previewFrameAt(widget.clock.value, frames.length)],
              fit: BoxFit.cover,
              // Swapping frames must never flash the stage between them.
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
            ),
          );

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: label,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isSelected ? AppColors.highlight : AppColors.surface,
            border: Border.all(
              color: widget.isSelected ? AppColors.primaryStart : AppColors.border,
              width: widget.isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.previewStage,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: stage,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: widget.isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
