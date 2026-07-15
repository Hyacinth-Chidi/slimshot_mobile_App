import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/video_editor_notifier.dart';
import '../../models/overlay_animation.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AnimationDrawer extends ConsumerStatefulWidget {
  const AnimationDrawer({super.key});

  @override
  ConsumerState<AnimationDrawer> createState() => _AnimationDrawerState();
}

class _AnimationDrawerState extends ConsumerState<AnimationDrawer> {
  int _activeTabIndex = 0; // 0 = In, 1 = Out, 2 = Combo

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    String? currentAnimIn;
    String? currentAnimOut;
    double currentAnimInDuration = 0.5;
    double currentAnimOutDuration = 0.5;

    if (editorState.selectedTextId != null) {
      final txt = editorState.textOverlays.firstWhere((t) => t.id == editorState.selectedTextId);
      currentAnimIn = txt.inAnimation != 'none' ? txt.inAnimation : null;
      currentAnimOut = txt.outAnimation != 'none' ? txt.outAnimation : null;
    } else if (editorState.selectedImageId != null) {
      final img = editorState.imageOverlays.firstWhere((i) => i.id == editorState.selectedImageId);
      currentAnimIn = img.animationIn;
      currentAnimOut = img.animationOut;
      currentAnimInDuration = img.animationInDuration;
      currentAnimOutDuration = img.animationOutDuration;
    } else if (editorState.selectedVideoOverlayId != null) {
      final vid = editorState.videoOverlays.firstWhere((v) => v.id == editorState.selectedVideoOverlayId);
      currentAnimIn = vid.animationIn;
      currentAnimOut = vid.animationOut;
      currentAnimInDuration = vid.animationInDuration;
      currentAnimOutDuration = vid.animationOutDuration;
    }

    final activeDuration = _activeTabIndex == 0 ? currentAnimInDuration : currentAnimOutDuration;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E121A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Tabs
              SizedBox(
                height: 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTab(0, 'In'),
                    _buildTab(1, 'Out'),
                    _buildTab(2, 'Combo'),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),

              // Duration Slider
              if (_activeTabIndex != 2 &&
                  ((_activeTabIndex == 0 && currentAnimIn != null) ||
                   (_activeTabIndex == 1 && currentAnimOut != null)))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                            value: activeDuration,
                            min: 0.1,
                            max: 2.0,
                            onChanged: (val) {
                              if (_activeTabIndex == 0) {
                                notifier.setOverlayAnimation(animationInDuration: val);
                              } else {
                                notifier.setOverlayAnimation(animationOutDuration: val);
                              }
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${activeDuration.toStringAsFixed(1)}s',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 16),

              // Grid
              Expanded(
                child: _activeTabIndex == 2
                    ? const Center(child: Text("Combo coming soon!", style: TextStyle(color: Colors.white54)))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: _activeTabIndex == 0
                            ? OverlayAnimation.inAnimations.length + 1
                            : OverlayAnimation.outAnimations.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final isSelected = _activeTabIndex == 0 ? currentAnimIn == null : currentAnimOut == null;
                            return _buildGridItem(
                              icon: LucideIcons.ban,
                              name: 'None',
                              isSelected: isSelected,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                if (_activeTabIndex == 0) {
                                  notifier.setOverlayAnimation(animationIn: 'none');
                                } else {
                                  notifier.setOverlayAnimation(animationOut: 'none');
                                }
                              },
                            );
                          }

                          final animList = _activeTabIndex == 0 ? OverlayAnimation.inAnimations : OverlayAnimation.outAnimations;
                          final anim = animList[index - 1];
                          final isSelected = _activeTabIndex == 0 ? currentAnimIn == anim.id : currentAnimOut == anim.id;

                          return _buildGridItem(
                            icon: anim.icon,
                            name: anim.name,
                            isSelected: isSelected,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              if (_activeTabIndex == 0) {
                                notifier.setOverlayAnimation(animationIn: anim.id);
                              } else {
                                notifier.setOverlayAnimation(animationOut: anim.id);
                              }
                            },
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

  Widget _buildTab(int index, String label) {
    final isSelected = _activeTabIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeTabIndex = index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: isSelected
              ? const Border(bottom: BorderSide(color: Colors.white, width: 2))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildGridItem({
    required IconData icon,
    required String name,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
              child: Icon(icon, color: isSelected ? AppColors.primaryStart : Colors.white54),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
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
  }
}
