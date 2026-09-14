import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/effects/effect_catalog.dart';
import '../../providers/video_editor_notifier.dart';

/// The clip's Effects sheet: a category row, a grid of effect tiles, and one
/// intensity slider.
///
/// **It lists the catalog, never a list of its own.** The text animation tab
/// shipped with a hardcoded seven names while the engine played thirty, and the
/// device tester's report was simply "the new animations, I'm not seeing them".
/// Everything offered here comes from [effectsInCategory], so adding a catalog
/// entry reaches the UI with no edit in this file — and a test counts the
/// grid's `itemCount` against the catalog so the wiring cannot rot quietly.
///
/// **Tiles are a label and an icon, not a preview.** A text animation tile can
/// paint itself with the same painter the canvas uses; an effect tile cannot —
/// each one would need a full GL render of the clip through its shader, and a
/// shelf of them would need a dozen at once. The canvas behind the sheet is the
/// preview instead: a tap applies the effect immediately and the user sees the
/// real thing on their own footage, which is a truer preview than any tile.
class EffectsPanel extends ConsumerStatefulWidget {
  const EffectsPanel({super.key});

  @override
  ConsumerState<EffectsPanel> createState() => _EffectsPanelState();
}

/// The categories the panel actually shelves, in enum order.
///
/// [EffectCategory.none] is skipped on purpose: it names the *absence* of an
/// effect and holds no catalog entries, so a tab for it would be an empty
/// shelf. The absence is reachable from every category through the leading
/// None tile instead.
final List<EffectCategory> kEffectPanelCategories = EffectCategory.values
    .where((c) => c != EffectCategory.none)
    .toList(growable: false);

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
};

IconData _iconForCategory(EffectCategory category) => switch (category) {
      EffectCategory.none => LucideIcons.ban,
      EffectCategory.grade => LucideIcons.palette,
      EffectCategory.retro => LucideIcons.radio,
      EffectCategory.distort => LucideIcons.waves,
      EffectCategory.light => LucideIcons.sun,
      EffectCategory.motion => LucideIcons.aperture,
      EffectCategory.intro => LucideIcons.play,
    };

/// The glyph for [effect], falling back to its category's.
IconData effectIcon(VideoEffect effect) =>
    _kEffectIcons[effect.id] ?? _iconForCategory(effect.category);

class _EffectsPanelState extends ConsumerState<EffectsPanel> {
  EffectCategory _category = kEffectPanelCategories.first;

  @override
  void initState() {
    super.initState();
    // Open on the shelf the clip's own effect lives on, so reopening the sheet
    // shows what is applied rather than making the user hunt for it.
    final selected = ref.read(videoEditorProvider).selectedSegment?.effect;
    if (selected != null) _category = selected.category;
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    final segment = editorState.selectedSegment;
    // Resolved through the catalog, never by reading the stored string: an id
    // from a newer build or a bad migration must show as "no effect", not
    // highlight nothing while the slider pretends to retune something.
    final selected = segment?.effect;
    final effects = effectsInCategory(_category);

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
              _handle(),
              if (segment == null)
                const Expanded(
                  child: Center(
                    child: Text(
                      'Select a clip to add an effect.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else ...[
                _categoryRow(),
                const SizedBox(height: 10),
                // Nothing to retune while no effect is applied, and a slider
                // over a value nothing reads is worse than no slider.
                if (selected != null)
                  _intensityRow(
                    notifier: notifier,
                    intensity: segment.effectIntensity,
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: GridView.builder(
                    // Keyed by category so each shelf opens at the top rather
                    // than inheriting a taller shelf's scroll offset, which
                    // would scroll None off the moment a short category opens.
                    key: ValueKey(_category),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    // +1 for the leading None tile, so every shelf has a way
                    // back to an unaffected clip.
                    itemCount: effects.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return EffectTile(
                          label: 'None',
                          icon: LucideIcons.ban,
                          isSelected: selected == null,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            // Cleared through the notifier's null, which maps
                            // to `clearEffectId` — `effectId: null` alone is
                            // ignored by `copyWith` by convention and would
                            // leave the effect in place.
                            notifier.setClipEffect(null);
                          },
                        );
                      }
                      final effect = effects[index - 1];
                      return EffectTile(
                        key: ValueKey(effect.id),
                        label: effect.label,
                        icon: effectIcon(effect),
                        isSelected: selected?.id == effect.id,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          // One tap is the whole interaction: the catalog's
                          // own default intensity is applied, so the effect is
                          // visibly itself before the slider is ever touched.
                          notifier.setClipEffect(effect.id);
                        },
                      );
                    },
                  ),
                ),
              ],
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

  Widget _intensityRow({
    required VideoEditorNotifier notifier,
    required double intensity,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
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
                // drawn into a ~400px preview and a 1080p export, and a pixel
                // parameter would make those two different pictures.
                value: intensity.clamp(0.0, 1.0),
                onChangeStart: (_) {
                  // **One undo entry for the whole drag.** The snapshot is
                  // taken here and every frame after it writes live; going
                  // through the snapshotting setter per frame makes undo walk
                  // the drag back a pixel at a time.
                  notifier.saveStateForUndo();
                },
                onChanged: (value) => notifier.setClipEffect(
                  // The effect is unchanged — only its strength moves — so the
                  // id is re-sent rather than cleared and reapplied.
                  ref.read(videoEditorProvider).selectedSegment?.effectId,
                  intensity: value,
                  takeUndoSnapshot: false,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(intensity.clamp(0.0, 1.0) * 100).round()}%',
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

/// One shelf entry: a glyph and a label, selected or not.
///
/// A widget of its own rather than a private builder so a test can read
/// [isSelected] off the tile instead of inferring selection from its pixels —
/// the same route `TextAnimationTile` takes, for the same reason.
class EffectTile extends StatelessWidget {
  const EffectTile({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
                child: Center(
                  child: Icon(
                    icon,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    size: 22,
                  ),
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
