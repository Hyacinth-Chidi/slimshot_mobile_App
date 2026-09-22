import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';

/// The "apply to all clips" switch that sits at the top of a tool sheet.
///
/// Shared by the filter, transition and adjust sheets so the control reads the
/// same in all three: the same place, the same wording, the same affordance.
/// [subtitle] says what the *current* setting will do, because "apply to all"
/// on its own does not tell the user what happens when it is off.
///
/// **A label and a check, not a Material `Switch`.** The switch plus two
/// stacked lines came to about 70px at the top of a sheet capped at 45% of the
/// screen — a lot of a small surface spent on a control the user glances at
/// once and then ignores. A mark is also what the rest of this app uses to say
/// "this one is chosen": the background tiles, the effect grid and the easing
/// cells all draw `primaryStart` over `highlight`, and the check inside them is
/// white, never dark, because dark on purple is unreadable.
///
/// The **whole row** is the target. A 20px box at the end of a line is a
/// smaller thing to hit than the sentence that describes it.
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

  static const double _boxEdge = 22;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onChanged(!value);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      'Apply to all clips',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // On one line with the label rather than stacked under it:
                    // it is a qualifier, and stacking it was half the height.
                    Flexible(
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _check(),
            ],
          ),
        ),
      ),
    );
  }

  /// The chosen-state mark every tile grid in this app already uses:
  /// `primaryStart` over `highlight` when on, the resting border when off.
  Widget _check() {
    return Container(
      width: _boxEdge,
      height: _boxEdge,
      decoration: BoxDecoration(
        color: value ? AppColors.primaryStart : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: value ? AppColors.primaryStart : AppColors.border,
          width: 1.5,
        ),
      ),
      // White on the purple fill, never a dark glyph: dark on purple does not
      // read.
      child: value
          ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}
