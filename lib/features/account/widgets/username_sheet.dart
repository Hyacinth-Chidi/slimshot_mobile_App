import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';
import 'username_field.dart';

/// Changing the username, under the claim step's rules. No heading: the
/// row the user tapped already said "Username".
class UsernameSheet extends ConsumerStatefulWidget {
  const UsernameSheet({super.key, required this.current});

  final String current;

  @override
  ConsumerState<UsernameSheet> createState() => _UsernameSheetState();
}

class _UsernameSheetState extends ConsumerState<UsernameSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.current);
  bool _available = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountProvider.notifier).changeUsername(_name.text);
      if (!mounted) return;
      ToastUtils.show(context, 'Username changed');
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
        UsernameField(
          controller: _name,
          current: widget.current,
          onAvailability: (ok) => setState(() => _available = ok),
        ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 16),
        AccountPrimaryButton(
          label: 'Save',
          busy: _busy,
          onPressed: _available ? _save : null,
        ),
      ],
    );
  }
}
