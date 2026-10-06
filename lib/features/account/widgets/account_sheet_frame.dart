import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/colour_field_backdrop.dart';
import '../../video_editor/widgets/panels/caption_sheet_parts.dart'
    show SheetGrabHandle;

/// The widest an account sheet grows: on a tablet it is a card, not a band
/// across the screen.
const double kAccountSheetMaxWidth = 480;

const TextStyle kAccountInputStyle =
    TextStyle(color: AppColors.textPrimary, fontSize: 16);

/// The frame every account sheet shares: corners and grab handle, capped at
/// [kAccountSheetMaxWidth] and lifted above the keyboard, on the home
/// screen's near-black and soft purple light.
///
/// The light, not glass: a glass sheet (a purple-and-white fill with a lit
/// edge) was built and rejected on the device. This is the backdrop the user
/// approved for home, so a sheet reads as part of the screens it opens over.
class AccountSheetFrame extends StatelessWidget {
  const AccountSheetFrame({super.key, required this.children});

  final List<Widget> children;

  static const _corners = BorderRadius.vertical(top: Radius.circular(24));

  /// The home screen's light composed for a sheet: shorter than a screen, so
  /// the glows sit closer in — purple high on the right, deep purple low on
  /// the left, a whisper of white where the first falls off.
  static const List<BackdropGlow> glows = [
    // Wide enough to light the sheet's whole top: over a near-black screen
    // that light is what shows where the sheet begins.
    BackdropGlow(
      color: AppColors.primaryStart,
      opacity: 0.26,
      centre: Offset(0.80, 0.0),
      width: 1.8,
      height: 0.9,
    ),
    BackdropGlow(
      color: AppColors.textPrimary,
      opacity: 0.04,
      centre: Offset(0.65, 0.0),
      width: 0.7,
      height: 0.35,
    ),
    BackdropGlow(
      color: AppColors.primaryEnd,
      opacity: 0.20,
      centre: Offset(0.0, 1.0),
      width: 1.1,
      height: 0.7,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAccountSheetMaxWidth),
        child: ClipRRect(
          borderRadius: _corners,
          child: ColoredBox(
            color: AppColors.background,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColourFieldBackdrop(glows: glows),
                ),
                SafeArea(
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
              ],
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
