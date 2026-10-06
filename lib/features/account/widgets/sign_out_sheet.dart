import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'account_sheet_frame.dart';

/// The step before signing out (device-reported: one tap signed the user
/// straight out). Pops `true` to sign out; Cancel, a swipe or a tap outside
/// pops nothing and keeps the account.
///
/// Not a danger action — the credits stay with the account and signing in
/// again brings them back — so the button is the ordinary primary, not red.
class SignOutSheet extends StatelessWidget {
  const SignOutSheet({super.key, required this.username});

  /// Who is being signed out; null before the claim has set a name.
  final String? username;

  @override
  Widget build(BuildContext context) {
    final name = username;
    return AccountSheetFrame(
      children: [
        AccountSheetHeading(name == null ? 'Sign out?' : 'Sign out of $name?'),
        AccountPrimaryButton(
          key: const Key('sign_out_confirm'),
          label: 'Sign out',
          onPressed: () => Navigator.of(context).pop(true),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
