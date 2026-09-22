import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../logic/filter_presets.dart';
import '../../models/filter_preset.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/video_editor_state.dart';
import '../../models/video_segment.dart';
import '../../providers/video_editor_notifier.dart';
import '../../services/video_thumbnail_service.dart';
import 'apply_to_all_toggle.dart';
import 'editor_sheet.dart';

class FiltersDrawer extends ConsumerStatefulWidget {
  const FiltersDrawer({super.key});

  @override
  ConsumerState<FiltersDrawer> createState() => _FiltersDrawerState();
}

class _FiltersDrawerState extends ConsumerState<FiltersDrawer> {
  /// Frame the preset tiles are drawn on.
  ///
  /// Loaded here rather than relying on `VideoEditorState.filterThumbnail`,
  /// which is produced once at import, from the *first* asset only, and is
  /// dropped silently if the extraction fails — leaving every tile showing a
  /// placeholder for the rest of the session with no way to recover. Loading it
  /// in the sheet also means the tiles preview the clip actually being graded
  /// rather than always the first one.
  Uint8List? _frame;
  String? _frameKey;

  /// One pre-graded thumbnail per preset, keyed by preset id.
  ///
  /// The tiles used to be `ColorFiltered` wrapped around the raw frame, which
  /// renders unfiltered under Impeller — every tile showed the same picture, so
  /// there was no way to tell the presets apart before applying one. The grade
  /// is done here on the pixels instead, which is also exactly the arithmetic
  /// `ColorFilter.matrix` documents, so a tile matches what the preset does.
  ///
  /// Only the visible category is graded, and only once per frame.
  final Map<String, ui.Image> _graded = {};

  /// The exact bytes the cache was built from.
  ///
  /// Identity, not the frame *key*: the tiles fall back to
  /// `VideoEditorState.filterThumbnail` — which is always the first clip's
  /// frame — while the selected clip's own frame is still loading. Keying the
  /// cache on the key meant that fallback was graded and then stamped as
  /// current, so when the real frame arrived nothing regraded and the sheet
  /// kept showing the previous clip's picture.
  Uint8List? _gradedFrame;
  bool _grading = false;

  /// Decoded once and reused for every preset in the category.
  Uint8List? _baseRgba;
  int _baseWidth = 0;
  int _baseHeight = 0;

  @override
  void dispose() {
    for (final image in _graded.values) {
      image.dispose();
    }
    _graded.clear();
    super.dispose();
  }

  void _ensureGraded(Uint8List frame, List<FilterPreset> presets) {
    if (!identical(_gradedFrame, frame)) {
      // Disposed after the frame is on screen, not here: this runs during
      // build, and the images can still be referenced by the layer tree that
      // is being replaced. Disposing one mid-raster throws.
      final retired = _graded.values.toList(growable: false);
      if (retired.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final image in retired) {
            image.dispose();
          }
        });
      }
      _graded.clear();
      _baseRgba = null;
      _gradedFrame = frame;
    }

    if (_grading) return;
    final missing =
        presets.where((p) => !_graded.containsKey(p.id)).toList(growable: false);
    if (missing.isEmpty) return;

    _grading = true;
    unawaited(
      _gradePresets(frame, missing).whenComplete(() => _grading = false),
    );
  }

  Future<void> _gradePresets(
    Uint8List frame,
    List<FilterPreset> presets,
  ) async {
    // Every await below is a chance for a different clip to be selected, which
    // replaces the frame. Each resumption re-checks that the frame this run
    // started on is still the one the sheet wants.
    bool stale() => !mounted || !identical(_gradedFrame, frame);

    try {
      if (_baseRgba == null) {
        // Small on purpose: a tile is about 80pt wide, and this is per-pixel
        // work repeated for every preset in the category.
        final codec = await ui.instantiateImageCodec(frame, targetWidth: 160);
        final decoded = (await codec.getNextFrame()).image;
        final data = await decoded.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final width = decoded.width;
        final height = decoded.height;
        decoded.dispose();
        if (data == null || stale()) return;
        _baseRgba = data.buffer.asUint8List();
        _baseWidth = width;
        _baseHeight = height;
      }

      final base = _baseRgba;
      if (base == null || stale()) return;

      for (final preset in presets) {
        if (stale()) return;
        final image = await _applyMatrix(base, preset.matrix);
        if (stale()) {
          image.dispose();
          return;
        }
        _graded[preset.id]?.dispose();
        _graded[preset.id] = image;
        setState(() {});
      }
    } catch (_) {
      // Cosmetic: the tiles fall back to the ungraded frame.
    }
  }

  /// Applies a 4×5 `ColorFilter.matrix` to raw RGBA.
  ///
  /// Channels and the translation column are both on a 0–255 scale, which is
  /// the layout Flutter documents for `ColorFilter.matrix`.
  Future<ui.Image> _applyMatrix(Uint8List rgba, List<double> m) {
    final out = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      final r = rgba[i].toDouble();
      final g = rgba[i + 1].toDouble();
      final b = rgba[i + 2].toDouble();
      final a = rgba[i + 3].toDouble();

      out[i] = _clamp255(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]);
      out[i + 1] = _clamp255(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]);
      out[i + 2] = _clamp255(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14]);
      out[i + 3] = _clamp255(m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]);
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out,
      _baseWidth,
      _baseHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static int _clamp255(double value) {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return value.round();
  }

  /// A preset tile's picture: the frame with that preset's grade baked in.
  ///
  /// Falls back to the ungraded frame while the grade is being computed, and to
  /// a placeholder when there is no frame at all.
  Widget _buildPresetPreview(FilterPreset filter, Uint8List? frame) {
    final graded = _graded[filter.id];
    if (graded != null) {
      return RawImage(
        image: graded,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    if (frame != null) {
      return Image.memory(
        frame,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // The same bytes back every tile, so without this each rebuild flashes
        // them out and in again while the decode is repeated.
        gaplessPlayback: true,
      );
    }

    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Center(
        child: Icon(LucideIcons.image, size: 20, color: Colors.white24),
      ),
    );
  }

  void _ensureFrame(VideoEditorState state, VideoSegment? clip) {
    final asset = clip != null
        ? state.assetFor(clip)
        : (state.assets.isEmpty ? null : state.assets.first);
    if (asset == null || asset.path.isEmpty) return;

    // A little way in: the opening frame of a clip is often black or a fade,
    // which makes every tile look identical whatever the filter does.
    final sourceSeconds = clip != null
        ? clip.sourceAtOffset(clip.duration * 0.1)
        : (asset.durationSeconds * 0.1).clamp(0.0, 3.0);
    final timeMs = (sourceSeconds * 1000).round();
    final key = '${asset.path}@$timeMs';
    if (key == _frameKey) return;
    _frameKey = key;

    unawaited(
      VideoThumbnailService.instance
          .singleFrame(path: asset.path, timeMs: timeMs)
          .then((bytes) {
        // A later clip may have been selected while this was in flight.
        if (!mounted || _frameKey != key || bytes == null) return;
        setState(() => _frame = bytes);
      }).catchError((_) {
        // Cosmetic: the filters still work without a preview frame.
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    
    final activeCategory = editorState.activeFilterCategory;
    final filters = FilterPresets.getByCategory(activeCategory);

    // With the switch off the sheet is editing the selected clip, so it has to
    // show that clip's filter — not the project's — or the highlighted tile
    // would describe a grade the user is not editing.
    final appliesToAll = editorState.filterAppliesToAll;
    final selectedSegment = editorState.selectedSegment;
    final selectedFilter = appliesToAll
        ? editorState.selectedFilter
        : FilterPresets.byId(selectedSegment?.filterId);
    final intensity = appliesToAll
        ? editorState.filterIntensity
        : (selectedSegment?.filterIntensity ?? 1.0);
    final canEdit = appliesToAll || selectedSegment != null;

    // Preview the clip being graded, or the opening clip for a project look.
    _ensureFrame(editorState, appliesToAll ? null : selectedSegment);

    // Grade only the frame that belongs to the clip being edited. The project
    // thumbnail is the first clip's, and is used to fill the tiles while the
    // real frame loads — grading it too would flash a filtered picture of the
    // wrong clip and throw the work away a moment later.
    final loadedFrame = _frame;
    if (loadedFrame != null) _ensureGraded(loadedFrame, filters);
    final previewFrame = loadedFrame ?? editorState.filterThumbnail;

    return SizedBox(
      height: MediaQuery.of(context).size.height * kEditorSheetPreviewFraction,
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

              ApplyToAllToggle(
                value: appliesToAll,
                enabled: editorState.segments.length > 1,
                subtitle: appliesToAll
                    ? 'One look over the whole video'
                    : (selectedSegment == null
                        ? 'Select a clip on the timeline to filter it'
                        : 'Filtering the selected clip only'),
                onChanged: notifier.setFilterAppliesToAll,
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
                            value: intensity,
                            onChanged: (value) => notifier.setFilterIntensity(value),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${(intensity * 100).round()}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 16), // Spacer if no filter is selected

              // Filters Grid. Dimmed and inert when the sheet is set to grade
              // one clip and none is selected — there is nothing to grade, and
              // tapping a tile would otherwise do nothing with no explanation.
              Expanded(
                child: IgnorePointer(
                  ignoring: !canEdit,
                  child: Opacity(
                    opacity: canEdit ? 1.0 : 0.4,
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
                                // The ungraded frame, so there is something to
                                // compare the presets against.
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: previewFrame != null
                                      ? Image.memory(
                                          previewFrame,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          gaplessPlayback: true,
                                        )
                                      : const Icon(
                                          LucideIcons.ban,
                                          color: Colors.white54,
                                        ),
                                ),
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
                                child: _buildPresetPreview(filter, previewFrame),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
