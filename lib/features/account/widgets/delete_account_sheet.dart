import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';

/// The step before deleting an account: what is lost, then a destructive
/// button. The server erases the email, username and Google link and
/// forfeits the credits.
class DeleteAccountSheet extends ConsumerStatefulWidget {
  const DeleteAccountSheet({super.key});

  @override
  ConsumerState<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<DeleteAccountSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider.notifier).deleteAccount();
      if (!mounted) return;
      ToastUtils.show(context, 'Account deleted');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountSheetFrame(
      children: [
        const Text(
          "Your credits will be lost. This can't be undone.",
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 20),
        AccountPrimaryButton(
          key: const Key('delete_account_confirm'),
          label: 'Delete account',
          danger: true,
          busy: _busy,
          onPressed: _delete,
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
