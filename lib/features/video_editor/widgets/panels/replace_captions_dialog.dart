import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'caption_sheet_parts.dart';

/// Asks before a new caption set replaces the project's current one — hand
/// fixes to the old set go with it. True only for Replace.
Future<bool> confirmReplaceCaptions(BuildContext context) async {
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Replace captions?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SheetActionButton(
                    key: const Key('replace_captions_cancel'),
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetActionButton(
                    key: const Key('replace_captions_confirm'),
                    label: 'Replace',
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
  return replace ?? false;
}
