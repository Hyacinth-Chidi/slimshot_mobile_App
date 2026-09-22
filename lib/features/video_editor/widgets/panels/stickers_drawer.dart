import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/emoji_catalog.dart';
import 'editor_sheet.dart';

/// The emoji picker.
///
/// **An emoji is inserted as a text overlay, not as an overlay kind of its
/// own.** It is a character, so it renders through the platform's colour emoji
/// face and inherits the whole text pipeline — the glyph atlas, per-character
/// animation, mask, chroma key, keyframes, and export parity that has already
/// been verified on a device. A second overlay kind would be a second
/// implementation of all of it.
///
/// The tab bar and search field this replaced were a mockup: three hardcoded
/// labels over a spinner that never resolved. GIFs and stickers need a content
/// provider and are not offered rather than promised.
///
/// **It stops at [kEditorSheetPreviewFraction], like a sheet about the
/// picture rather than like the audio library.** Choosing an emoji is a
/// choice *for a frame* — the user is looking at where it will land — and the
/// device-reported complaint that a tall sheet hides the very frame being
/// chosen for applies here exactly. A grid loses nothing to the cap: it
/// scrolls, where the audio library is a list to read down, so at 45% this
/// still shows several rows with the canvas in view above it.
class StickersDrawer extends StatefulWidget {
  const StickersDrawer({super.key, required this.onEmojiSelected});

  /// Called with the chosen emoji. The sheet closes first, so the canvas is
  /// visible when the overlay lands on it.
  final ValueChanged<String> onEmojiSelected;

  @override
  State<StickersDrawer> createState() => _StickersDrawerState();
}

class _StickersDrawerState extends State<StickersDrawer> {
  int _selectedGroup = 0;

  static const double _kEdge = 16;
  static const double _kTileExtent = 52;

  @override
  Widget build(BuildContext context) {
    final group = kEmojiGroups[_selectedGroup];
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
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    // The grab handle's white24 is the one white the theme
                    // guard allows here: every sheet in the app shares it and
                    // there is no token for it.
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _groupPills(),
              const SizedBox(height: 4),
              Expanded(child: _grid(group)),
            ],
          ),
        ),
      ),
    );
  }

  /// The groups, as pills — the row shape the effects and easing sheets use.
  /// Each pill shows its group's first emoji beside the name, so the row reads
  /// as pictures rather than as nine words.
  Widget _groupPills() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        itemCount: kEmojiGroups.length,
        itemBuilder: (context, index) {
          final group = kEmojiGroups[index];
          final isSelected = _selectedGroup == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedGroup = index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // Selected is primaryStart over border — the Background,
                  // Effects and easing grids' pattern, not a white underline.
                  color: isSelected ? AppColors.primaryStart : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryStart : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(group.icon, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      group.name,
                      style: TextStyle(
                        // White on purple, never dark.
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid(EmojiGroup group) {
    return GridView.builder(
      // Tighter vertically than horizontally: at 45% of the screen the grid
      // has roughly three rows to give, and symmetric padding would spend a
      // fifth of that on empty space above and below.
      padding: const EdgeInsets.fromLTRB(_kEdge, 4, _kEdge, _kEdge),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // A max extent rather than a fixed column count, so a tablet shows
        // more columns instead of stretching eight across the screen.
        maxCrossAxisExtent: _kTileExtent,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: group.emoji.length,
      itemBuilder: (context, index) {
        final emoji = group.emoji[index];
        return _EmojiTile(
          emoji: emoji,
          onTap: () {
            // Close first: the overlay lands on the canvas, and a sheet still
            // covering it would hide what the tap just did.
            Navigator.of(context).pop();
            widget.onEmojiSelected(emoji);
          },
        );
      },
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Center(
        child: Text(
          emoji,
          // No colour: an emoji carries its own, and setting one would tint a
          // monochrome glyph (✔️, ⚫) while leaving the rest alone.
          style: const TextStyle(fontSize: 28),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
