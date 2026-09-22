import 'package:flutter/material.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../models/video_editor_state.dart';

class CropPanel extends StatelessWidget {
  const CropPanel({
    super.key,
    required this.selectedRatio,
    required this.onRatioSelected,
  });

  final EditorCropRatio selectedRatio;
  final ValueChanged<EditorCropRatio> onRatioSelected;

  /// The height of a ratio tile, and so of the row.
  ///
  /// **The tile owns its height now.** The old fixed 160px panel stretched a
  /// horizontal list to the 80px left under its header, and the tiles were
  /// simply whatever fell out of that box. When the panel began sizing to its
  /// body the row was first pinned at 64, and the tiles came out squat —
  /// device-reported. This is the 80 they always had, decided here rather
  /// than by the box around them, with the glyph and label given room to fill
  /// it instead of floating in it.
  static const double kRowHeight = 80.0;

  /// The box the ratio glyph is drawn in, and the base edge a glyph's longer
  /// side is scaled to.
  static const double _kGlyphBox = 36.0;
  static const double _kGlyphEdge = 26.0;

  @override
  Widget build(BuildContext context) {
    // A horizontal list needs a height from somewhere, and the tool panel no
    // longer hands one down — it sizes to its body. This is the body's own.
    return SizedBox(
      height: kRowHeight,
      child: _buildRow(),
    );
  }

  Widget _buildRow() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: EditorCropRatio.values.length,
      itemBuilder: (context, index) {
        final ratio = EditorCropRatio.values[index];
        final isSelected = selectedRatio == ratio;

        Widget ratioIcon;
        if (ratio == EditorCropRatio.custom) {
          ratioIcon = const Icon(LucideIcons.crop,
              color: Colors.white, size: _kGlyphEdge);
        } else {
          final r = ratio.ratio!;
          double width = _kGlyphEdge;
          double height = _kGlyphEdge;
          if (r > 1) {
            height = _kGlyphEdge / r;
          } else if (r < 1) {
            width = _kGlyphEdge * r;
          }
          ratioIcon = Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1.5),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }

        return GestureDetector(
          onTap: () => onRatioSelected(ratio),
          child: Container(
            width: 64,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: _kGlyphBox,
                  child: Center(child: ratioIcon),
                ),
                const SizedBox(height: 8),
                Text(
                  ratio.label,
                  // One line, always: the chip is one row tall and a label
                  // that wrapped would push the row past its height.
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
