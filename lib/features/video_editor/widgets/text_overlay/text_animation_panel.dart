import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/text_animation_catalog.dart';
import '../../models/text_overlay_model.dart';
import 'text_animation_tile.dart';

/// The text editor sheet's Animation tab.
///
/// **It lists the catalog, never a list of its own.** The tab used to hold a
/// hardcoded seven names, which is how the engine came to play thirty
/// animations while the user could pick from seven — the device tester's
/// report was simply "the new animations, I'm not seeing them". Everything
/// offered here comes from [selectableTextAnimations], so a catalog entry
/// reaches the UI without an edit in this file, and an entry whose rendering
/// does not exist yet (`isSelectable: false`) cannot be offered by accident.
///
/// The slot, not the id alone, decides what is selected: a legacy `'fade'`
/// means `fade_in` in the In tab and `fade_out` in the Out tab, so the
/// highlight goes through [textAnimationSlotValue] rather than comparing the
/// stored string. Selecting writes the **catalog id**.
class TextAnimationPanel extends StatefulWidget {
  const TextAnimationPanel({
    super.key,
    required this.overlay,
    required this.onSelect,
    required this.onSpeedChangeStart,
    required this.onSpeedChanged,
  });

  /// The overlay being edited, as it currently stands. Both the selection
  /// highlight and the tiles' own preview text read from it, so the panel
  /// always previews the user's own styling.
  final TextOverlayModel overlay;

  /// A tile was tapped: write [id] (a catalog id, or null for None) into
  /// [category]'s slot. Fired **once per tap** — the caller turns it into one
  /// undo entry.
  final void Function(TextAnimationCategory category, String? id) onSelect;

  /// The speed slider was grabbed. The caller takes its undo snapshot here, so
  /// the whole drag is one step rather than one per frame.
  final VoidCallback onSpeedChangeStart;

  /// A frame of the speed drag: a multiplier for [category]'s slot, **not**
  /// a duration in seconds.
  final void Function(TextAnimationCategory category, double speed)
      onSpeedChanged;

  @override
  State<TextAnimationPanel> createState() => _TextAnimationPanelState();
}

class _TextAnimationPanelState extends State<TextAnimationPanel>
    with SingleTickerProviderStateMixin {
  /// One loop of every visible tile's preview.
  ///
  /// Slow enough that a staggered animation reads as a stagger rather than a
  /// flicker, quick enough that a user comparing two tiles does not wait.
  static const Duration _kTileLoop = Duration(milliseconds: 1800);

  TextAnimationCategory _category = TextAnimationCategory.inAnim;

  /// **One clock for every tile**, rather than a `Ticker` per tile: the tab
  /// shows over a dozen previews at once and a ticker each would be a dozen
  /// competing for the same frames. `TextAnimationTile` reads it as a
  /// `ValueListenable<double>` phase, which an `AnimationController` is.
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: _kTileLoop)..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  /// The speed field [_category] drives.
  ///
  /// In and out share one value deliberately: the renderer resolves both
  /// windows from a single speed, because the proportional compression that
  /// fits them into a short overlay is one rule that must not exist twice
  /// across the Dart/Kotlin boundary.
  double get _speed => switch (_category) {
        TextAnimationCategory.inAnim => widget.overlay.animationInDuration,
        TextAnimationCategory.outAnim => widget.overlay.animationOutDuration,
        TextAnimationCategory.loop => widget.overlay.loopSpeed,
      };

  /// The catalog id currently selected in [_category], resolved by slot.
  String? get _selectedId =>
      textAnimationSlotValue(widget.overlay, _category);

  @override
  Widget build(BuildContext context) {
    final animations = selectableTextAnimations(_category);
    final selected = _selectedId;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _categoryButton('In', TextAnimationCategory.inAnim),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _categoryButton('Out', TextAnimationCategory.outAnim),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _categoryButton('Loop', TextAnimationCategory.loop),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Nothing to speed up when the slot is empty, and a slider that moves
        // a value nothing reads is worse than no slider.
        if (selected != null) _speedRow(),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            // Keyed by category so each tab gets its own scroll position and
            // opens at the top. Without it the grid is one widget reused
            // across the three lists, and switching to a shorter category
            // inherits the taller one's offset — the tab opens part-way down,
            // with None scrolled off.
            key: ValueKey(_category),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.85,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            // The leading None tile clears the slot, so every category has a
            // way back to no animation.
            itemCount: animations.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _noneTile(isSelected: selected == null);
              }
              final animation = animations[index - 1];
              return TextAnimationTile(
                key: ValueKey('${_category.name}-${animation.id}'),
                animation: animation,
                overlay: widget.overlay,
                isSelected: selected == animation.id,
                onTap: () => widget.onSelect(_category, animation.id),
                // Only the visible category's tiles are built at all, so
                // switching tabs cannot leave twenty animations running.
                clock: _clock,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _speedRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(LucideIcons.gauge, color: AppColors.textSecondary, size: 16),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppColors.primaryStart,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                trackHeight: 2,
                overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
              ),
              // **Speed, not seconds.** The field behind it changed meaning
              // when the catalog took over timing: how long an animation runs
              // now depends on which animation it is and how many characters
              // there are, and this multiplier divides that. A slider reading
              // "0.8s" over a model holding a speed is the bug this replaces.
              child: Slider(
                value: _speed.clamp(
                  kMinTextAnimationSpeed,
                  kMaxTextAnimationSpeed,
                ),
                min: kMinTextAnimationSpeed,
                max: kMaxTextAnimationSpeed,
                // One undo entry for the whole drag: the snapshot is taken
                // here, and every frame after it writes live.
                onChangeStart: (_) => widget.onSpeedChangeStart(),
                onChanged: (value) => widget.onSpeedChanged(_category, value),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${_speed.toStringAsFixed(1)}×',
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

  Widget _noneTile({required bool isSelected}) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'None',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(_category, null),
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
              const Expanded(
                child: Center(
                  child: Icon(
                    LucideIcons.ban,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  'None',
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

  Widget _categoryButton(String label, TextAnimationCategory category) {
    final isActive = _category == category;
    return GestureDetector(
      onTap: () => setState(() => _category = category),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
