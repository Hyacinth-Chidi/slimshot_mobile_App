import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

class SpeedPanel extends StatelessWidget {
  const SpeedPanel({
    super.key,
    required this.displaySpeed,
    required this.onChanged,
    this.emptyMessage,
  });

  final double displaySpeed;
  final ValueChanged<double> onChanged;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (emptyMessage != null) {
      return Center(
        child: Text(
          emptyMessage!,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.gauge, color: Colors.white54, size: 20),
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
                  value: displaySpeed,
                  min: 0.1,
                  max: 2.0,
                  onChanged: onChanged,
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 32,
              child: Text(
                '${displaySpeed.toStringAsFixed(1)}x',
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
