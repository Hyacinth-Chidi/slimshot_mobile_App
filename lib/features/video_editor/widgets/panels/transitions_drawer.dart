import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/transitions/transition_catalog.dart';
import '../../providers/video_editor_notifier.dart';
import 'apply_to_all_toggle.dart';

class TransitionsDrawer extends ConsumerWidget {
  const TransitionsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        height: MediaQuery.of(context).size.height * 0.45,
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
                    style: TextStyle(color: Colors.white54, fontSize: 14),
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

    // `null` is the "None" (hard cut) choice; the rest comes straight from the
    // catalog so this grid can never drift from what preview and export
    // actually support.
    final options = <EditorTransition?>[null, ...EditorTransition.values];

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.45,
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
                subtitle: editorState.transitionAppliesToAll
                    ? 'The same transition at every cut'
                    : 'Only the cut you tapped',
                onChanged: notifier.setTransitionAppliesToAll,
              ),

              // Duration Slider (only when a transition is selected)
              if (currentTransition != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.timer, color: Colors.white54, size: 16),
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
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 16),

              const Divider(height: 1, color: Colors.white10),

              // Presets Grid (4 columns)
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = currentTransition == option?.name;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setSegmentTransition(option?.name, currentDuration);
                      },
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                border: Border.all(
                                  color: isSelected ? AppColors.primaryStart : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                option?.icon ?? LucideIcons.ban,
                                color: isSelected ? AppColors.primaryStart : Colors.white54,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            option?.label ?? 'None',
                            style: TextStyle(
                              color: isSelected ? AppColors.primaryStart : Colors.white54,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
