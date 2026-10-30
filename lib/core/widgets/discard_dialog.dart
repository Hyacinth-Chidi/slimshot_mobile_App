import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/lucide_icons.dart';

/// The question asked before a result nobody saved or shared is thrown
/// away, naming what would be lost.
String discardQuestion({required bool isVideo, required int count}) {
  final kind = isVideo ? 'video' : 'photo';
  return count == 1 ? 'Discard this $kind?' : 'Discard these $count ${kind}s?';
}

/// Asks before leaving a result nobody saved or shared — the owner's call: a
/// long compression or export lost to one tap is painful. The question is
/// the whole of it, in the look of the drafts' Delete Draft? dialog. True
/// only for Discard; Cancel and a tap outside stay.
Future<bool> confirmDiscard(
  BuildContext context, {
  required bool isVideo,
  required int count,
}) =>
    _confirmDiscard(context, discardQuestion(isVideo: isVideo, count: count));

/// The question asked before leaving captions made from Home that no export
/// kept: the credits were spent on them.
const String kDiscardCaptionsQuestion = 'Discard these captions?';

/// [confirmDiscard] for captions nobody exported and kept. True only for
/// Discard.
Future<bool> confirmDiscardCaptions(BuildContext context) =>
    _confirmDiscard(context, kDiscardCaptionsQuestion);

Future<bool> _confirmDiscard(BuildContext context, String question) async {
  final discard = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.trash2,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              question,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: kInterfaceFontFamily,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    key: const Key('discard_cancel'),
                    label: 'Cancel',
                    color: AppColors.textSecondary,
                    fill: AppColors.surfaceLight.withValues(alpha: 0.5),
                    weight: FontWeight.w600,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogButton(
                    key: const Key('discard_confirm'),
                    label: 'Discard',
                    color: AppColors.error,
                    fill: AppColors.error.withValues(alpha: 0.2),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return discard ?? false;
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    super.key,
    required this.label,
    required this.color,
    required this.fill,
    required this.onPressed,
    this.weight = FontWeight.bold,
  });

  final String label;
  final Color color;
  final Color fill;
  final VoidCallback onPressed;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: fill,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontFamily: kInterfaceFontFamily,
            color: color,
            fontWeight: weight,
            fontSize: 14,
          ),
        ),
      );
}
