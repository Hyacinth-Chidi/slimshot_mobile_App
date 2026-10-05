import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';
import 'username_field.dart';

/// A new account's first step: choose a username, optionally enter a
/// friend's invite code, and claim the free credits. The amount is the
/// server's, so the sheet names it only once it has been granted.
///
/// Pops `true` when claimed. Closed before that, the account stays signed in
/// and unclaimed, and the next paid action asks again.
class ClaimSheet extends ConsumerStatefulWidget {
  const ClaimSheet({super.key});

  @override
  ConsumerState<ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<ClaimSheet> {
  final _username = TextEditingController();
  final _invite = TextEditingController();
  bool _available = false;
  bool _showInvite = false;
  bool _busy = false;
  String? _error;
  String? _inviteError;
  ClaimResult? _result;

  @override
  void dispose() {
    _username.dispose();
    _invite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AccountSheetFrame(
      children: result == null ? _form() : _claimed(result),
    );
  }

  List<Widget> _form() => [
        const AccountSheetHeading('Choose a username to claim your free credits'),
        UsernameField(
          controller: _username,
          onAvailability: (ok) => setState(() => _available = ok),
        ),
        const SizedBox(height: 12),
        if (_showInvite) ...[
          TextField(
            key: const Key('claim_invite'),
            controller: _invite,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: kAccountInputStyle,
            decoration: accountInputDecoration('Invite code'),
            onChanged: (_) {
              if (_inviteError != null) setState(() => _inviteError = null);
            },
          ),
          if (_inviteError != null) AccountErrorLine(_inviteError!),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showInvite = true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Have an invite code?'),
            ),
          ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 16),
        AccountPrimaryButton(
          label: 'Claim',
          busy: _busy,
          onPressed: _available ? _claim : null,
        ),
      ];

  List<Widget> _claimed(ClaimResult result) => [
        const SizedBox(height: 8),
        Text(
          result.creditsGranted > 0
              ? '+${result.creditsGranted} credits'
              : "You're all set",
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        for (final line in claimResultLines(result))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        const SizedBox(height: 24),
        AccountPrimaryButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ];

  Future<void> _claim() async {
    setState(() {
      _busy = true;
      _error = null;
      _inviteError = null;
    });
    final invite = _invite.text.replaceAll(' ', '');
    try {
      final result = await ref.read(accountProvider.notifier).claim(
            username: _username.text,
            referralCode: invite.isEmpty ? null : invite,
          );
      if (mounted) setState(() => _result = result);
    } on SlimshotApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ALREADY_CLAIMED') {
        await ref.read(accountProvider.notifier).refresh();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        if (e.code == 'REFERRAL_CODE_INVALID') {
          _inviteError = accountErrorMessage(e);
        } else {
          _error = accountErrorMessage(e);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
