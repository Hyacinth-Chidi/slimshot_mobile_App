import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/animatable_double.dart';
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
                    // Whether the keyframe row is already open, so the control
                    // reads as a toggle rather than a button that stops
                    // responding once tapped.
                    keyframesOpen:
                        editorState.keyframeEditorSegmentId == segment.id,
                    // **One slider, two subjects, and the label says which.**
                    //
                    // With a diamond selected it edits *that keyframe's*
                    // value; with nothing selected it edits the parameter's
                    // base. A second slider would be the obvious alternative
                    // and is worse: two controls for one quantity, one of them
                    // inert most of the time, and nothing on screen explaining
                    // which the picture is currently following.
                    //
                    // **Never the value at the playhead.** An envelope shapes
                    // the base across the clip, so a slider tracking the
                    // resolved value would wander while playing and would write
                    // back whatever the curve happened to be at when the user
                    // grabbed it — quietly flattening the animation into one
                    // frame of itself.
                    keyframe: editorState.selectedKeyframe,
                    intensity: segment.effectIntensity.baseValue,
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
    required bool keyframesOpen,
    required Keyframe? keyframe,
  }) {
    final editingKeyframe = keyframe != null;
    final value = (editingKeyframe ? keyframe.value : intensity)
        .clamp(0.0, 1.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              editingKeyframe
                  // Named by where it sits, because that is how the user
                  // picked it out on the row.
                  ? 'Keyframe at ${(keyframe.progress * 100).round()}%'
                  : 'Intensity',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: editingKeyframe
                    ? AppColors.primaryStart
                    : AppColors.textSecondary,
              ),
            ),
          ),
          Row(
            children: [
              Icon(
                editingKeyframe ? LucideIcons.diamond : LucideIcons.gauge,
                color: editingKeyframe
                    ? AppColors.primaryStart
                    : AppColors.textSecondary,
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
                      // **One undo entry for the whole drag**, whichever
                      // subject it is pointed at. The snapshot is taken here
                      // and every frame after writes live; going through a
                      // snapshotting setter per frame makes undo walk the drag
                      // back a pixel at a time.
                      notifier.saveStateForUndo();
                    },
                    onChanged: (next) {
                      if (editingKeyframe) {
                        // Addressed by the keyframe's **progress**, which is
                        // also how the selection is stored — so a keyframe
                        // added or removed elsewhere on the row cannot
                        // renumber this drag onto a different diamond.
                        notifier.setEffectIntensityKeyframeValue(
                          keyframe.progress,
                          next,
                          takeUndoSnapshot: false,
                        );
                        return;
                      }
                      notifier.setClipEffect(
                        // The effect is unchanged — only its strength moves —
                        // so the id is re-sent rather than cleared and
                        // reapplied.
                        ref.read(videoEditorProvider).selectedSegment?.effectId,
                        intensity: next,
                        takeUndoSnapshot: false,
                      );
                    },
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
              const SizedBox(width: 8),
              KeyframeToggleButton(
                isOpen: keyframesOpen,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.toggleKeyframeEditor();
                },
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

/// The opt-in control for keyframing this clip's effect intensity.
///
/// **A user who never taps this never sees a diamond.** That is the whole
/// design of the two audiences the effects system serves: someone who wants a
/// good-looking clip taps an effect and leaves — the catalog's own envelope
/// already makes it feel designed — while someone who wants a glitch that
/// builds to a beat opts in here. A keyframe row that appeared on its own,
/// under every clip that happened to carry an effect, would break the casual
/// path for everyone to serve the few.
///
/// It is shown only beside the intensity slider, which itself only exists once
/// an effect is applied, so there is never a keyframe control over a value
/// nothing reads.
///
/// A widget of its own rather than a private builder so a test can read
/// [isOpen] off it instead of inferring the toggle's state from its pixels —
/// the same route [EffectTile] takes, for the same reason.
class KeyframeToggleButton extends StatelessWidget {
  const KeyframeToggleButton({
    super.key,
    required this.isOpen,
    required this.onTap,
  });

  /// Whether the row is already showing. The control is a toggle, not a
  /// one-way door: a button that stopped responding after the first tap would
  /// leave the row with no way back to a clean timeline.
  final bool isOpen;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isOpen,
      label: 'Keyframe',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isOpen ? AppColors.highlight : AppColors.surface,
            border: Border.all(
              color: isOpen ? AppColors.primaryStart : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.diamond,
                size: 13,
                color:
                    isOpen ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                'Keyframe',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isOpen ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isOpen ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
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
