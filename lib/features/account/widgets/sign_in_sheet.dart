import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';
import 'account_sheet_frame.dart';

final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Signing in: Google, or an email and the code sent to it. The first
/// sign-in makes the account; there are no passwords.
///
/// One sheet, two steps — the email, then the code. Pops `true` once the
/// session is saved; closed any other way it pops nothing.
class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key, required this.reason});

  /// Why the sheet opened — "Sign in to use Auto captions" — its one heading.
  final String reason;

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  /// Where the code went; null on the email step.
  String? _sentTo;
  String? _error;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return AccountSheetFrame(
      children: [
        AccountSheetHeading(widget.reason),
        ...(sentTo == null ? _emailStep() : _codeStep(sentTo)),
      ],
    );
  }

  List<Widget> _emailStep() {
    final google = ref.watch(googleIdTokensProvider);
    return [
      if (google.isAvailable) ...[
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _busy ? null : _google,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            // Google's own four-colour G, as its sign-in branding asks for
            // beside "Continue with Google". An asset, not an icon font:
            // Lucide carries no brand marks, and the G is four colours.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset('assets/google_g.svg', width: 20, height: 20),
                const SizedBox(width: 12),
                // Scales down rather than overflows or cuts off: a narrow
                // phone with large text still reads the whole label.
                const Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Continue with Google',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Expanded(child: Divider(color: Colors.white10)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              ),
              Expanded(child: Divider(color: Colors.white10)),
            ],
          ),
        ),
      ],
      TextField(
        key: const Key('sign_in_email'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        autocorrect: false,
        textInputAction: TextInputAction.done,
        style: kAccountInputStyle,
        decoration: accountInputDecoration('Email'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_looksLikeEmail) _sendCode();
        },
      ),
      if (_error != null) AccountErrorLine(_error!),
      const SizedBox(height: 16),
      // Off until the field holds an email address: a button that only says
      // what is missing after it is pressed is a step the user did not need.
      AccountPrimaryButton(
        label: 'Continue',
        busy: _busy,
        onPressed: _looksLikeEmail ? _sendCode : null,
      ),
    ];
  }

  bool get _looksLikeEmail => _emailShape.hasMatch(_email.text.trim());

  List<Widget> _codeStep(String sentTo) => [
        Text(
          'Code sent to $sentTo',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('sign_in_code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: kAccountInputStyle.copyWith(fontSize: 22, letterSpacing: 8),
          decoration: accountInputDecoration('6-digit code'),
          onChanged: (value) {
            setState(() {});
            if (value.length == 6) _verify();
          },
        ),
        if (_error != null) AccountErrorLine(_error!),
        const SizedBox(height: 16),
        AccountPrimaryButton(
          label: 'Continue',
          busy: _busy,
          onPressed: _code.text.length == 6 ? _verify : null,
        ),
        // Wraps rather than overflows: with large text the two do not fit on
        // one line of a phone.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy ? null : _useAnotherEmail,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Use another email'),
            ),
            TextButton(
              key: const Key('sign_in_resend'),
              onPressed: _resendIn > 0 || _busy ? null : _sendCode,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: Text(
                _resendIn > 0 ? 'Send again in ${_resendIn}s' : 'Send a new code',
              ),
            ),
          ],
        ),
      ];

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await ref.read(googleIdTokensProvider).requestIdToken();
      if (idToken == null) return; // closed the picker
      final result =
          await ref.read(accountServiceProvider).signInWithGoogle(idToken);
      await _finish(result);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = (_sentTo ?? _email.text).trim();
    if (!_emailShape.hasMatch(email)) {
      setState(() => _error = 'Enter your email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sent = await ref.read(accountServiceProvider).startEmail(email);
      if (!mounted) return;
      setState(() {
        _sentTo = sent.sentTo.isEmpty ? email : sent.sentTo;
        _code.clear();
      });
      _countDown(sent.resendAfter.inSeconds);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final sentTo = _sentTo;
    if (_busy || sentTo == null || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(accountServiceProvider).verifyEmail(sentTo, _code.text);
      await _finish(result);
    } catch (e) {
      _code.clear();
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(SignInResult result) async {
    await ref.read(accountProvider.notifier).completeSignIn(result);
    if (mounted) Navigator.of(context).pop(true);
  }

  void _useAnotherEmail() {
    _ticker?.cancel();
    setState(() {
      _sentTo = null;
      _error = null;
      _resendIn = 0;
    });
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() => _error = accountErrorMessage(error));
    if (error is SlimshotApiException && error.code == 'OTP_RESEND_TOO_SOON') {
      final wait = error.detailInt('retryAfterSeconds');
      if (wait != null) _countDown(wait);
    }
  }

  void _countDown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }
}
