import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

class PlaceholderPanel extends StatelessWidget {
  const PlaceholderPanel({
    super.key,
    required this.toolName,
  });

  final String toolName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.hammer, color: AppColors.textTertiary, size: 24),
          const SizedBox(height: 8),
          Text(
            '$toolName controls coming soon',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
