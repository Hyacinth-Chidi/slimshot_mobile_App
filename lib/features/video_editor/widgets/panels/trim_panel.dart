import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

class TrimPanel extends StatelessWidget {
  const TrimPanel({
    super.key,
    required this.trimLabel,
    required this.segmentCount,
    required this.onSplit,
  });

  final String trimLabel;
  final int segmentCount;
  final VoidCallback onSplit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Trim $trimLabel - $segmentCount segment${segmentCount == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onSplit,
          icon: const Icon(LucideIcons.scissors, size: 16),
          label: const Text('Split'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.primaryStart),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}
