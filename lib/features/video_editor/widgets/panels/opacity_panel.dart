import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

class OpacityPanel extends StatelessWidget {
  const OpacityPanel({
    super.key,
    required this.opacity,
    required this.onChanged,
  });

  final double opacity;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(
              opacity == 0 ? LucideIcons.eyeOff : LucideIcons.contrast,
              color: Colors.white54,
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
                  color: Colors.white,
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
