import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class AudioPanel extends StatelessWidget {
  const AudioPanel({
    super.key,
    required this.isMuted,
    required this.onChanged,
  });

  final bool isMuted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SwitchListTile.adaptive(
        value: isMuted,
        onChanged: onChanged,
        activeTrackColor: AppColors.primaryStart,
        title: const Text(
          'Mute Audio',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text(
          'Remove audio track completely',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
