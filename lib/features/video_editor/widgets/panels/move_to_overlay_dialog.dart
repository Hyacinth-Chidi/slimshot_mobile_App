import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/clip_to_overlay.dart';
import 'caption_sheet_parts.dart';

/// Asks before a clip moves onto the overlay track and leaves something
/// behind — a filter, a speed curve, whatever an overlay cannot hold yet.
/// One line naming it, Cancel and Move; true only for Move. Never shown for a
/// clip that loses nothing: that one just moves.
Future<bool> confirmMoveToOverlay(BuildContext context, List<String> losses) async {
  final move = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              clipToOverlayLossLine(losses),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SheetActionButton(
                    key: const Key('move_to_overlay_cancel'),
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetActionButton(
                    key: const Key('move_to_overlay_confirm'),
                    label: 'Move',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return move ?? false;
}
