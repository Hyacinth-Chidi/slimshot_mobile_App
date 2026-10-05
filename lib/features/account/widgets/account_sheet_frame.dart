import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../video_editor/widgets/panels/caption_sheet_parts.dart'
    show SheetGrabHandle;

/// The widest an account sheet grows: on a tablet it is a card, not a band
/// across the screen.
const double kAccountSheetMaxWidth = 480;

const TextStyle kAccountInputStyle =
    TextStyle(color: AppColors.textPrimary, fontSize: 16);

/// The frame every account sheet shares: the surface, corners and grab
/// handle the editor's sheets have, capped at [kAccountSheetMaxWidth] and
/// lifted above the keyboard.
class AccountSheetFrame extends StatelessWidget {
  const AccountSheetFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAccountSheetMaxWidth),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + keyboard),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: SheetGrabHandle()),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet's one heading: why it opened.
class AccountSheetHeading extends StatelessWidget {
  const AccountSheetHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

/// One line under the field it is about. Never a dialog.
class AccountErrorLine extends StatelessWidget {
  const AccountErrorLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.error, fontSize: 13),
        ),
      );
}

/// The sheet's main action. A busy button shows a spinner and takes no tap.
class AccountPrimaryButton extends StatelessWidget {
  const AccountPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppColors.error : AppColors.primaryStart,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.surfaceLight,
            disabledForegroundColor: AppColors.textTertiary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      );
}

InputDecoration accountInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surface,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primaryStart),
      ),
    );
