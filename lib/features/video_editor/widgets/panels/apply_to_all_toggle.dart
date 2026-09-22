import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// The "apply to all clips" switch that sits at the top of a tool sheet.
///
/// Shared by the filter and transition sheets so the control reads the same in
/// both: the same place, the same wording, the same affordance. [subtitle] says
/// what the *current* setting will do, because "apply to all" on its own does
/// not tell the user what happens when it is off.
class ApplyToAllToggle extends StatelessWidget {
  const ApplyToAllToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.subtitle,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String subtitle;

  /// False when the choice cannot apply — a single-clip project has nothing to
  /// apply "to all" of. Shown dimmed rather than hidden, so the control does
  /// not appear and disappear as clips are added.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Apply to all clips',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled
                  ? (next) {
                      HapticFeedback.selectionClick();
                      onChanged(next);
                    }
                  : null,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primaryStart,
              inactiveThumbColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}
