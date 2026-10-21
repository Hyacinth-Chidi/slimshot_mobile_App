import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/effects/effect_preview_layout.dart';
import '../../logic/effects/effect_catalog.dart';
import '../../providers/effect_preview_provider.dart';
import '../text_overlay/text_preview_tile.dart';
import 'effect_preview_stage.dart';
import '../../providers/video_editor_notifier.dart';
import 'editor_sheet.dart';

/// The Effects sheet: a category row, a grid of effect tiles, and one
/// intensity slider — working on **effect bars**.
///
/// **With no bar selected, a tap adds one** at the playhead and selects it;
/// **with a bar selected, a tap changes it.** So opened from the main menu the
/// first tap adds a bar and every later one swaps its effect — browsing the
/// shelves never litters the timeline — and opened from a bar's Edit it
/// changes that bar. There is no None tile: a bar is removed with Delete, and
/// backing out of an add is Undo. No title either: the sheet opened from
/// Effects is the effects.
///
/// **It lists the catalog, never a list of its own.** The text animation tab
/// shipped with a hardcoded seven names while the engine played thirty, and the
/// device tester's report was simply "the new animations, I'm not seeing them".
/// Everything offered here comes from [effectsInCategory], so adding a catalog
/// entry reaches the UI with no edit in this file — and a test counts the
/// grid's `itemCount` against the catalog so the wiring cannot rot quietly.
///
/// **A tile plays its effect, drawn by the engine** ([EffectPreviewStage]):
/// a new bar's opening on the sample picture, through the effect's own
/// shaders, as one atlas drawn a few frames per GL turn and kept for the
/// session — so a tile cannot promise a look a bar does not have, and the
/// canvas never waits on a shelf of tiles. Until an effect's atlas arrives,
/// or where this phone could not draw it, its tile keeps the icon. The grid
/// keeps no tiles off screen (`cacheExtent: 0`): each visible tile owns one
/// ~2.3 MB decoded picture, and tiles scrolled out give theirs back.
class EffectsPanel extends ConsumerStatefulWidget {
  const EffectsPanel({super.key});

  @override
  ConsumerState<EffectsPanel> createState() => _EffectsPanelState();
}

/// The categories the panel shelves, **fullest first**.
///
/// The sheet opens on the first tab, and opening on a shelf of two or three
/// tiles reads as "this is all there is" while Intro alone holds fourteen.
/// Counted from the catalog, so a new entry can reorder the tabs with no edit
/// here; equal shelves keep the enum's order.
///
/// [EffectCategory.none] is skipped on purpose: it names the *absence* of an
/// effect and holds no catalog entries, so a tab for it would be an empty
/// shelf.
final List<EffectCategory> kEffectPanelCategories = () {
  final categories =
      EffectCategory.values.where((c) => c != EffectCategory.none).toList();
  // List.sort is not stable, so ties fall back to the enum's own order.
  categories.sort((a, b) {
    final bySize =
        effectsInCategory(b).length.compareTo(effectsInCategory(a).length);
    return bySize != 0 ? bySize : a.index.compareTo(b.index);
  });
  return List<EffectCategory>.unmodifiable(categories);
}();

/// What each category's tab is called.
///
/// The enum names what an effect *is* to the renderer; these name what the
/// shelf is to a person browsing it.
String effectCategoryLabel(EffectCategory category) => switch (category) {
      EffectCategory.none => 'None',
      EffectCategory.grade => 'Colour',
      EffectCategory.retro => 'Retro',
      EffectCategory.distort => 'Distort',
      EffectCategory.light => 'Light',
      EffectCategory.motion => 'Focus',
      EffectCategory.intro => 'Intro',
      EffectCategory.reveal => 'Reveal',
      EffectCategory.motionLoop => 'Motion',
    };

/// A tile's glyph.
///
/// Keyed by effect id rather than declared on [VideoEffect] deliberately: the
/// catalog is shared with the Kotlin renderer and the composer, neither of
/// which has any use for a Flutter icon, and a field they must carry and
/// ignore is a field that will drift. An id with no entry here falls back to
/// the category's own glyph, so a new catalog entry shows a sensible tile
/// before anyone picks an icon for it — it is never a blank.
const Map<String, IconData> _kEffectIcons = {
  'vignette': LucideIcons.circleDot,
  'duotone': LucideIcons.contrast,
  'chromatic': LucideIcons.layers,
  'grain': LucideIcons.grip,
  'vhs': LucideIcons.tv2,
  'scanlines': LucideIcons.alignJustify,
  'rgb_split': LucideIcons.copy,
  'glitch': LucideIcons.zapOff,
  'fisheye': LucideIcons.circle,
  'ripple': LucideIcons.waves,
  'swirl': LucideIcons.tornado,
  'mirror': LucideIcons.flipHorizontal,
  'light_leak': LucideIcons.sun,
  'glow': LucideIcons.sparkle,
  'sharpen': LucideIcons.focus,
  'blur': LucideIcons.droplet,
  'fade_in': LucideIcons.sunrise,
  // -- intro ---------------------------------------------------------------
  'cinema_zoom': LucideIcons.clapperboard,
  'zoom_in': LucideIcons.zoomIn,
  'super_zoom': LucideIcons.scan,
  'pulse_zoom': LucideIcons.activity,
  'bounce': LucideIcons.arrowDownUp,
  'spin': LucideIcons.rotateCw,
  'roll': LucideIcons.iterationCw,
  'tilt': LucideIcons.galleryVerticalEnd,
  'blur_in': LucideIcons.aperture,
  'pixel_in': LucideIcons.grid,
  'hue_shift': LucideIcons.paintbrush,
  'bw_fade': LucideIcons.droplets,
  'steady_in': LucideIcons.crosshair,
  // -- reveal ---------------------------------------------------------------
  'shutter': LucideIcons.rows,
  'horizontal_open': LucideIcons.columns,
  'circle_in': LucideIcons.circleDashed,
  'grid': LucideIcons.layoutGrid,
  'grid_collage': LucideIcons.layoutDashboard,
  'roulette': LucideIcons.loader,
  // -- continuous ------------------------------------------------------------
  'camera_pan': LucideIcons.moveHorizontal,
  'handheld': LucideIcons.hand,
  'super_shake': LucideIcons.vibrate,
};

IconData _iconForCategory(EffectCategory category) => switch (category) {
      EffectCategory.none => LucideIcons.ban,
      EffectCategory.grade => LucideIcons.palette,
      EffectCategory.retro => LucideIcons.radio,
      EffectCategory.distort => LucideIcons.waves,
      EffectCategory.light => LucideIcons.sun,
      EffectCategory.motion => LucideIcons.aperture,
      EffectCategory.intro => LucideIcons.play,
      EffectCategory.reveal => LucideIcons.eye,
      EffectCategory.motionLoop => LucideIcons.move,
    };

/// The glyph for [effect], falling back to its category's.
IconData effectIcon(VideoEffect effect) =>
    _kEffectIcons[effect.id] ?? _iconForCategory(effect.category);

class _EffectsPanelState extends ConsumerState<EffectsPanel>
    with SingleTickerProviderStateMixin {
  EffectCategory _category = kEffectPanelCategories.first;

  /// One clock for every tile — a ticker per tile would be a grid of tickers
  /// — reduced to the frame to show, told to the tiles only when it changes,
  /// so a tile repaints at the atlas's 15 fps rather than on every vsync.
  ///
  /// Made in [initState], not `late final`: nothing reads the controller
  /// until a scroll notification, and a lazily made clock never starts.
  late final AnimationController _clock;

  final ValueNotifier<int> _frameIndex = ValueNotifier<int>(0);


  void _onClockTick() {
    final frame = effectPreviewFrameAt(_clock.value);
    if (frame != _frameIndex.value) _frameIndex.value = frame;
  }

  @override
  void dispose() {
    _clock.dispose();
    _frameIndex.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: kEffectPreviewLoop)
      ..addListener(_onClockTick)
      ..repeat();
    // Opened on a bar, the sheet opens on that bar's shelf with its tile lit.
    final bar = ref.read(videoEditorProvider).selectedEffectBar;
    final selected = videoEffectById(bar?.effectId);
    if (selected != null) _category = selected.category;
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    final bar = editorState.selectedEffectBar;
    final selected = videoEffectById(bar?.effectId);
    final effects = effectsInCategory(_category);

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
              _handle(),
              _categoryRow(),
              const SizedBox(height: 10),
              if (bar != null)
                _intensityRow(
                  notifier: notifier,
                  intensity: editorState.effectBarEditIntensity,
                ),
              const SizedBox(height: 8),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  // Still while it scrolls — see [holdPreviewClockWhileScrolling].
                  onNotification: (notification) =>
                      mounted && holdPreviewClockWhileScrolling(notification, _clock),
                  child: GridView.builder(
                  key: ValueKey(_category),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  physics: const BouncingScrollPhysics(),
                  // Only what is visible holds a decoded atlas.
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: effects.length,
                  itemBuilder: (context, index) {
                    final effect = effects[index];
                    return EffectTile(
                      key: ValueKey(effect.id),
                      label: effect.label,
                      stage: EffectPreviewStage(
                        effectId: effect.id,
                        icon: effectIcon(effect),
                        isSelected: selected?.id == effect.id,
                        atlases: ref.watch(effectPreviewAtlasesProvider),
                        frameIndex: _frameIndex,
                        decode: ref.watch(effectAtlasDecoderProvider),
                      ),
                      isSelected: selected?.id == effect.id,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (ref.read(videoEditorProvider).selectedEffectBar ==
                            null) {
                          notifier.addEffectBar(effect.id);
                        } else {
                          notifier.setEffectBarEffect(effect.id);
                        }
                      },
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

  Widget _categoryRow() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kEffectPanelCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = kEffectPanelCategories[index];
          final isActive = category == _category;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _category = category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                effectCategoryLabel(category),
                style: TextStyle(
                  color: isActive
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
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

  /// The intensity slider, and the label naming what it is pointed at.
  ///
  /// When [keyframe] is non-null the slider reads and writes **that
  /// keyframe's** value; otherwise it reads and writes the parameter's base.
  /// A slider that silently edited something other than what it said would be
  /// worse than no feature at all — so the subject is stated on the row, not
  /// left to be inferred from whether a diamond happens to look highlighted on
  /// a timeline that may be scrolled out of view behind the sheet.
  Widget _intensityRow({
    required VideoEditorNotifier notifier,
    required double intensity,
  }) {
    final value = intensity.clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Intensity',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Row(
            children: [
              const Icon(
                LucideIcons.gauge,
                color: AppColors.textSecondary,
                size: 16,
              ),
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
                    // Normalised 0..1, never a pixel radius: the same clip is
                    // drawn into a ~400px preview and a 1080p export, and a
                    // pixel parameter would make those two different pictures.
                    value: value,
                    onChangeStart: (_) {
                      // **One undo entry for the whole drag**, and a pause
                      // first: on a keyframed bar every frame writes at the
                      // playhead, and a moving one would leave a trail of
                      // diamonds.
                      notifier.beginEffectBarIntensityEdit();
                    },
                    // **This slider has no idea keyframes exist**, and that is
                    // the point: the notifier writes the base on a bar with no
                    // diamonds and the keyframe under the playhead on one with
                    // some, so the sheet needs no keyframe control of its own.
                    onChanged: notifier.setEffectBarIntensityLive,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _handle() {
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

class EffectTile extends StatelessWidget {
  const EffectTile({
    super.key,
    required this.label,
    required this.stage,
    required this.isSelected,
    required this.onTap,
  });

  final String label;

  /// What plays above the label: an [EffectPreviewStage], which falls back to
  /// the effect's icon while there is nothing to play.
  final Widget stage;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.highlight : AppColors.surface,
            border: Border.all(
              color: isSelected ? AppColors.primaryStart : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
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
