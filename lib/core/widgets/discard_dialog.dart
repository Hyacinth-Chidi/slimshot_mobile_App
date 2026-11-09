import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

/// The question asked before a result nobody saved or shared is thrown
/// away, naming what would be lost.
String discardQuestion({required bool isVideo, required int count}) {
  final kind = isVideo ? 'video' : 'photo';
  return count == 1 ? 'Discard this $kind?' : 'Discard these $count ${kind}s?';
}

/// Asks before leaving a result nobody saved or shared — the owner's call: a
/// long compression or export lost to one tap is painful. The question is
/// the whole of it. True only for Discard; Cancel and a tap outside stay.
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

/// The question asked before a shot is deleted from the phone's gallery.
String deleteQuestion({required bool isVideo}) => isVideo ? 'Delete this video?' : 'Delete this photo?';

/// Asks before deleting a camera shot: it goes from the gallery too, for
/// good. The discard dialog with the word that says so. True only for Delete.
Future<bool> confirmDelete(BuildContext context, {required bool isVideo}) =>
    _confirmDiscard(context, deleteQuestion(isVideo: isVideo), action: 'Delete');

/// What leaving a new project in the editor answered.
enum DraftChoice { save, discard }

/// The question asked on leaving a project that was not in Recent Edits
/// when the editor opened (the owner's call, 2026-11-09).
const String kSaveDraftQuestion = 'Save as draft?';

/// "Save as draft?": Save keeps the project, Don't save throws it away, and
/// a tap outside or Back answers nothing — the editor stays.
Future<DraftChoice?> askSaveDraft(BuildContext context) => _ask<DraftChoice>(
      context,
      kSaveDraftQuestion,
      left: const _Answer(
        key: Key('save_draft_discard'),
        label: "Don't save",
        value: DraftChoice.discard,
        style: _AnswerStyle.risky,
      ),
      right: const _Answer(
        key: Key('save_draft_save'),
        label: 'Save',
        value: DraftChoice.save,
        style: _AnswerStyle.chosen,
      ),
    );

Future<bool> _confirmDiscard(BuildContext context, String question, {String action = 'Discard'}) async =>
    await _ask<bool>(
      context,
      question,
      left: const _Answer(
        key: Key('discard_cancel'),
        label: 'Cancel',
        value: false,
        style: _AnswerStyle.quiet,
      ),
      right: _Answer(
        key: const Key('discard_confirm'),
        label: action,
        value: true,
        style: _AnswerStyle.risky,
      ),
    ) ??
    false;

/// The surface every question here draws on.
const Key kQuestionDialogKey = ValueKey('question_dialog');

/// The space on every side of a question and its buttons — the same all
/// round (the owner's pick of three mockups, 2026-11-09). The dialog was
/// narrow, 24 over a large icon and 16 under the buttons, and read tall and
/// bottom-heavy for one short line.
const double kQuestionDialogPadding = 20;

/// How far the dialog stands off the screen's sides: 296 wide on a 360dp
/// phone.
const double _kSideInset = 32;

/// No wider than this on a tablet, so the two buttons stay a pair.
const double _kMaxWidth = 340;

enum _AnswerStyle { quiet, risky, chosen }

class _Answer<T> {
  const _Answer({required this.key, required this.label, required this.value, required this.style});

  final Key key;
  final String label;
  final T value;
  final _AnswerStyle style;
}

/// The question and two answers, nothing else: no icon — the buttons'
/// colours already say which answer is the risky one.
Future<T?> _ask<T>(
  BuildContext context,
  String question, {
  required _Answer<T> left,
  required _Answer<T> right,
}) =>
    showDialog<T>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: _kSideInset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: Padding(
            key: kQuestionDialogKey,
            padding: const EdgeInsets.all(kQuestionDialogPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  question,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: kInterfaceFontFamily,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _DialogButton(answer: left)),
                    const SizedBox(width: 12),
                    Expanded(child: _DialogButton(answer: right)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

class _DialogButton<T> extends StatelessWidget {
  _DialogButton({required this.answer}) : super(key: answer.key);

  final _Answer<T> answer;

  @override
  Widget build(BuildContext context) {
    final (color, fill, weight) = switch (answer.style) {
      _AnswerStyle.quiet => (
          AppColors.textSecondary,
          AppColors.surfaceLight.withValues(alpha: 0.5),
          FontWeight.w600,
        ),
      _AnswerStyle.risky => (AppColors.error, AppColors.error.withValues(alpha: 0.2), FontWeight.bold),
      // White on purple, never dark.
      _AnswerStyle.chosen => (Colors.white, AppColors.primaryStart, FontWeight.bold),
    };
    return TextButton(
      onPressed: () => Navigator.of(context).pop(answer.value),
      style: TextButton.styleFrom(
        backgroundColor: fill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          answer.label,
          maxLines: 1,
          style: TextStyle(
            fontFamily: kInterfaceFontFamily,
            color: color,
            fontWeight: weight,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
