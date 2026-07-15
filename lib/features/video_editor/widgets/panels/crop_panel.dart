import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/video_editor_state.dart';

class CropPanel extends StatelessWidget {
  const CropPanel({
    super.key,
    required this.selectedRatio,
    required this.onRatioSelected,
  });

  final EditorCropRatio selectedRatio;
  final ValueChanged<EditorCropRatio> onRatioSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: EditorCropRatio.values.length,
      itemBuilder: (context, index) {
        final ratio = EditorCropRatio.values[index];
        final isSelected = selectedRatio == ratio;

        Widget ratioIcon;
        if (ratio == EditorCropRatio.custom) {
          ratioIcon = const Icon(LucideIcons.crop, color: Colors.white, size: 24);
        } else {
          final r = ratio.ratio!;
          double width = 24;
          double height = 24;
          if (r > 1) {
            height = 24 / r;
          } else if (r < 1) {
            width = 24 * r;
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
                  height: 32,
                  child: Center(child: ratioIcon),
                ),
                const SizedBox(height: 8),
                Text(
                  ratio.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 11,
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
