import 'package:flutter/material.dart';

/// One tool in a toolbar: its glyph over its name, **the name whole**.
///
/// Every toolbar tool used to sit in a fixed 56px box with an ellipsis, so any
/// name past about eight letters at 10pt was cut — "Background" read as
/// "Backgro…", device-reported — and a tool the user cannot read is a tool
/// they will not find. The tile takes the width its label needs, with
/// [kMinWidth] as a floor so short names ("Zoom", "Text") keep the rhythm of
/// the row rather than crowding together. One line, no wrapping: the toolbar
/// is one row tall, and a second line would push its neighbours around.
///
/// Both toolbars — the root/clip menu and the audio context menu — draw their
/// tools through this, so a name fits in one exactly as it fits in the other.
class EditorToolTile extends StatelessWidget {
  const EditorToolTile({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// The least a tile is wide, so short names keep the row's spacing.
  static const double kMinWidth = 56;

  /// Breathing room either side of a label that is wider than the glyph.
  static const double kHorizontalPadding = 6;

  /// The gap to the next tile.
  static const double kGap = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: kMinWidth),
      padding: const EdgeInsets.symmetric(horizontal: kHorizontalPadding),
      margin: const EdgeInsets.only(right: kGap),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}
