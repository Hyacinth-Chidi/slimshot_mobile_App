import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../logic/filter_presets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/video_editor_notifier.dart';

class FiltersDrawer extends ConsumerStatefulWidget {
  const FiltersDrawer({super.key});

  @override
  ConsumerState<FiltersDrawer> createState() => _FiltersDrawerState();
}

class _FiltersDrawerState extends ConsumerState<FiltersDrawer> {
  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    
    final activeCategory = editorState.activeFilterCategory;
    final filters = FilterPresets.getByCategory(activeCategory);
    final selectedFilter = editorState.selectedFilter;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background, // Dark background matching the theme
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Drag Handle
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

              // Categories Tab Bar
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: FilterPresets.categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 24),
                  itemBuilder: (context, index) {
                    final category = FilterPresets.categories[index];
                    final isSelected = category == activeCategory;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setActiveFilterCategory(category);
                      },
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: isSelected
                              ? const Border(bottom: BorderSide(color: Colors.white, width: 2))
                              : null,
                        ),
                        child: Text(
                          category,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1, color: Colors.white10),
              
              // Intensity Slider (Sticky if a filter is selected)
              if (selectedFilter != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.sun, color: Colors.white54, size: 16),
                      Expanded(
                        child: SliderTheme(
                          data: const SliderThemeData(
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: Colors.white,
                            trackHeight: 2,
                            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: editorState.filterIntensity,
                            onChanged: (value) => notifier.setFilterIntensity(value),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${(editorState.filterIntensity * 100).round()}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 16), // Spacer if no filter is selected

              // Filters Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.75, // Taller than wide to fit text
                  ),
                  itemCount: filters.length + 1,
                  itemBuilder: (context, index) {
                    // "None" option
                    if (index == 0) {
                      final isSelected = selectedFilter == null;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          notifier.setSelectedFilter(null);
                        },
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(LucideIcons.ban, color: Colors.white54),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'None',
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white54,
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

                    // Actual filters
                    final filter = filters[index - 1];
                    final isSelected = selectedFilter?.id == filter.id;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setSelectedFilter(filter);
                      },
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: editorState.filterThumbnail != null
                                    ? ColorFiltered(
                                        colorFilter: ColorFilter.matrix(filter.matrix),
                                        child: Image.memory(editorState.filterThumbnail!, fit: BoxFit.cover),
                                      )
                                    : Container(
                                        color: Colors.white.withValues(alpha: 0.05),
                                        child: const Center(
                                          child: Icon(
                                            LucideIcons.image,
                                            size: 20,
                                            color: Colors.white24,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            filter.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white54,
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
}
