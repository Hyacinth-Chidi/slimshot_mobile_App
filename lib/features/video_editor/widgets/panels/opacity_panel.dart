import 'package:flutter/material.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

class OpacityPanel extends StatelessWidget {
  const OpacityPanel({
    super.key,
    required this.opacity,
    required this.onChanged,
    this.onChangeStart,
  });

  final double opacity;
  final ValueChanged<double> onChanged;

  /// Fired once when a drag begins, so a caller writing live can take one undo
  /// snapshot per drag — the shape the transform rulers have.
  final VoidCallback? onChangeStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(
              opacity == 0 ? LucideIcons.eyeOff : LucideIcons.contrast,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SliderTheme(
                data: const SliderThemeData(
                  activeTrackColor: AppColors.primaryStart,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: Colors.white,
                  trackHeight: 4,
                ),
                child: Slider(
                  value: opacity,
                  min: 0.0,
                  max: 1.0,
                  onChangeStart:
                      onChangeStart == null ? null : (_) => onChangeStart!(),
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 38,
              child: Text(
                '${(opacity * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
