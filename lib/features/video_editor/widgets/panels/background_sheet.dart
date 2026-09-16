import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/video_editor_state.dart';
import '../../providers/video_editor_notifier.dart';

/// The solid colours offered for the letterbox background. Black first: it is
/// the default every project starts on, and the tile that reads as current for
/// a draft written before the picker existed.
const List<Color> kBackgroundPresets = [
  Colors.black,
  Colors.white,
  Color(0xFF1E1E1E),
  Color(0xFF2C3E50),
  Color(0xFFE74C3C),
  Color(0xFF3498DB),
  Color(0xFF2ECC71),
  Color(0xFFF1C40F),
  Color(0xFFE67E22),
  Color(0xFF9B59B6),
  Color(0xFFE91E63),
  Color(0xFF00BCD4),
  Color(0xFF607D8B),
  Color(0xFF795548),
];

/// One edge inset for the sheet, matching every other sheet's.
const double _kEdge = 16;

/// The gap between tiles, in both directions.
const double _kTileGap = 10;

/// The letterbox background picker: a sheet of square colour tiles.
///
/// **A sheet, not a panel.** A background is a choice *about* the picture with
/// no canvas or timeline gesture attached — the rule that already puts the
/// curve, filters and effects in sheets — so it opens over a clear canvas like
/// they do and the user watches the bars change as they tap.
///
/// **The "Solid Color" switch is gone.** It toggled between a `black` type and
/// a `color` type, but black is a colour: it is the first tile, and picking any
/// tile is the whole interaction. The `black` type survives in the model for
/// drafts already written and shows here as the black tile being current.
///
/// **Tiles, not circles**, the width of the crop panel's ratio tiles and square
/// because a colour needs no label — one tile language across the editor's
/// pickers. Every tap applies live and is one undo step; the ✓ only dismisses.
class BackgroundSheet extends ConsumerWidget {
  const BackgroundSheet({super.key});

  /// The side of a tile: the crop panel's tile width, so the two pickers match.
  static const double kTileSize = 64.0;

  /// The key of a colour's tile, for tests and for anything that needs to
  /// find one.
  static Key tileKey(Color colour) =>
      Key('background_tile_${colour.toARGB32().toRadixString(16)}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    // The old `black` type is the black tile; anything else is its colour.
    final current = state.backgroundType == EditorBackgroundType.color
        ? state.backgroundColor.toARGB32()
        : Colors.black.toARGB32();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kEdge),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Background',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  GestureDetector(
                    key: const Key('background_done'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        LucideIcons.check,
                        color: AppColors.primaryStart,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, _kEdge),
              child: Wrap(
                spacing: _kTileGap,
                runSpacing: _kTileGap,
                children: [
                  for (final colour in kBackgroundPresets)
                    _ColourTile(
                      key: tileKey(colour),
                      colour: colour,
                      selected: colour.toARGB32() == current,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setBackground(colour);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The grab handle, drawn exactly as every other sheet in the app draws it.
  Widget _handle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ColourTile extends StatelessWidget {
  const _ColourTile({
    super.key,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The tile *is* the colour, so selection is the accent border plus a
    // check — and the check has to be legible on the tile's own colour, so it
    // is dark on light tiles and light on dark ones.
    final checkColour =
        colour.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: BackgroundSheet.kTileSize,
        height: BackgroundSheet.kTileSize,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryStart : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(LucideIcons.check, color: checkColour, size: 22)
            : null,
      ),
    );
  }
}
