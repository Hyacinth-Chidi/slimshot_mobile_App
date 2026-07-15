import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/video_editor_state.dart';
import '../../providers/video_editor_notifier.dart';

class BackgroundPanel extends ConsumerWidget {
  final VoidCallback onClose;

  const BackgroundPanel({super.key, required this.onClose});

  static const List<Color> _backgroundColors = [
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final isColor = state.backgroundType == EditorBackgroundType.color;

    return Column(
      children: [
        Row(
          children: [
            const Text(
              'Solid Color',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const Spacer(),
            SizedBox(
              height: 28,
              child: Switch(
                value: isColor,
                activeTrackColor: AppColors.primaryStart,
                onChanged: (value) {
                  notifier.setBackgroundType(
                    value ? EditorBackgroundType.color : EditorBackgroundType.black,
                  );
                },
              ),
            ),
          ],
        ),
        if (isColor) ...[
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _backgroundColors.map((color) {
                  final isSelected =
                      state.backgroundColor.toARGB32() == color.toARGB32();
                  return GestureDetector(
                    onTap: () => notifier.setBackgroundColor(color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryStart
                              : Colors.white24,
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
