import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// The grab handle, drawn as every other sheet draws it.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// A full-height sheet button: purple when it is the action, quiet otherwise.
class SheetActionButton extends StatelessWidget {
  const SheetActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryStart : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of colour swatches; the current one is ringed in the
/// accent, the rest in the border colour — which is also what keeps a black
/// swatch visible on the sheet.
class CaptionColorRow extends StatelessWidget {
  const CaptionColorRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.keyFor,
    required this.onSelected,
  });

  final List<Color> colors;
  final Color selected;
  final Key Function(int index) keyFor;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (var i = 0; i < colors.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                key: keyFor(i),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(colors[i]);
                },
                child: Container(
                  width: 36,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colors[i] == selected
                          ? AppColors.primaryStart
                          : AppColors.border,
                      width: colors[i] == selected ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A horizontal row of choice pills: the filled capsule is the current one.
class CaptionPillRow<T> extends StatelessWidget {
  const CaptionPillRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.keyFor,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final Key Function(T value) keyFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                key: keyFor(value),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onSelected(value);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppColors.primaryStart
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    label(value),
                    style: TextStyle(
                      color: value == selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
