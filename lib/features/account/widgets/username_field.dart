import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../logic/account_copy.dart';
import '../logic/username_rules.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';

/// A username field that asks the server whether a name is free once typing
/// pauses: one question per pause, and an answer for text the user has since
/// typed over is dropped — a late "available" must never bless a different
/// name.
class UsernameField extends ConsumerStatefulWidget {
  const UsernameField({
    super.key,
    required this.controller,
    required this.onAvailability,
    this.current,
  });

  final TextEditingController controller;

  /// Whether the text now in the field can be taken.
  final ValueChanged<bool> onAvailability;

  /// The user's own name (Settings): nothing to check, nothing to save.
  final String? current;

  @override
  ConsumerState<UsernameField> createState() => _UsernameFieldState();
}

class _UsernameFieldState extends ConsumerState<UsernameField> {
  Timer? _debounce;
  bool _checking = false;
  bool _ok = false;
  String? _message;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    widget.onAvailability(false);
    setState(() {
      _ok = false;
      _checking = false;
      _message = null;
    });
    if (text.isEmpty || text == widget.current) return;
    if (!isValidUsername(text)) {
      setState(() => _message = kUsernameRule);
      return;
    }
    setState(() => _checking = true);
    _debounce = Timer(kUsernameCheckDelay, () => _check(text));
  }

  Future<void> _check(String name) async {
    try {
      final answer =
          await ref.read(accountServiceProvider).usernameAvailability(name);
      if (!mounted || widget.controller.text != name) return;
      setState(() {
        _checking = false;
        _ok = answer.available;
        _message = answer.available ? null : usernameReasonMessage(answer.reason);
      });
      widget.onAvailability(answer.available);
    } catch (e) {
      if (!mounted || widget.controller.text != name) return;
      setState(() {
        _checking = false;
        _message = accountErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('username_field'),
          controller: widget.controller,
          autofocus: true,
          autocorrect: false,
          inputFormatters: usernameInputFormatters,
          style: kAccountInputStyle,
          onChanged: _changed,
          decoration: accountInputDecoration('Username').copyWith(
            prefixText: '@',
            prefixStyle: const TextStyle(color: AppColors.textTertiary),
            suffixIcon: _checking
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                : _ok
                    ? const Icon(
                        LucideIcons.check,
                        key: Key('username_ok'),
                        color: AppColors.success,
                      )
                    : null,
          ),
        ),
        if (_message != null) AccountErrorLine(_message!),
      ],
    );
  }
}
