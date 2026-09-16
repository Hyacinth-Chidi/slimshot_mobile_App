import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

/// One tap copies the selected clip's setting onto every other clip.
///
/// **A copy, not a mode.** Filters and transitions offer `ApplyToAllToggle`
/// because their edits are single choices that can sensibly write everywhere
/// live. A placement is a ruler drag, and a live all-clips mode would write a
/// keyframe into every clip at the same *relative* instant on each frame of
/// it — which nobody means. So for Transform, the clip crop and Effects the
/// user sets one clip up and then copies it, as one undo step.
///
/// Disabled, dimmed and inert, with fewer than two clips: there is nothing to
/// copy to. Shown rather than hidden, so it does not appear and disappear as
/// clips are added.
class ApplyToAllButton extends StatelessWidget {
  const ApplyToAllButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colour = enabled ? AppColors.textPrimary : AppColors.textTertiary.withValues(alpha: 0.5);
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onPressed();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? AppColors.border : AppColors.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.copyCheck, size: 14, color: colour),
            const SizedBox(width: 6),
            Text(
              'Apply to all',
              style: TextStyle(
                color: colour,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
