import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/logic/account_copy.dart';
import 'package:slimshotai/features/account/models/account_models.dart';

import '../../../support/fake_server.dart';

void main() {
  test('every account error has its one line', () {
    const expected = {
      SlimshotApiException.network:
          'No connection. Check your internet and try again.',
      'GOOGLE_TOKEN_INVALID': "Google sign-in didn't work. Try again.",
      kGoogleSignInFailed: "Google sign-in didn't work. Try again.",
      'GOOGLE_EMAIL_UNVERIFIED': 'Use your email instead.',
      'SIGN_IN_METHOD_UNAVAILABLE': 'Use your email instead.',
      'ACCOUNT_LINK_CONFLICT': 'This email uses a different Google account.',
      'EMAIL_DOMAIN_NOT_ALLOWED': 'Use a regular email address.',
      'OTP_EXPIRED': 'Code expired. Send a new one.',
      'OTP_ATTEMPTS_EXCEEDED': 'Code expired. Send a new one.',
      'USERNAME_INVALID': kUsernameRule,
      'USERNAME_TAKEN': 'Taken',
      'REFERRAL_CODE_INVALID': "That invite code doesn't work.",
      'ACCOUNT_SUSPENDED': 'This account is suspended.',
      SlimshotApiException.signInRequired: 'Sign in again.',
      'SOMETHING_NEW': 'Something went wrong. Try again.',
    };
    expected.forEach((code, line) {
      expect(accountErrorMessage(SlimshotApiException(code)), line, reason: code);
    });
    expect(accountErrorMessage(StateError('?')), 'Something went wrong. Try again.');
  });

  test('a wrong code says how many tries are left', () {
    String line(int? left) => accountErrorMessage(SlimshotApiException(
          'OTP_INVALID',
          '',
          left == null ? const {} : {'attemptsLeft': left},
        ));
    expect(line(3), 'Wrong code · 3 tries left');
    expect(line(1), 'Wrong code · 1 try left');
    expect(line(null), 'Wrong code.');
  });

  test('waiting says for how long', () {
    String line(String code, int? wait) => accountErrorMessage(
          SlimshotApiException(
            code,
            '',
            wait == null ? const {} : {'retryAfterSeconds': wait},
          ),
        );
    expect(line('OTP_RESEND_TOO_SOON', 42), 'Try again in 42s.');
    expect(line('RATE_LIMITED', 30), 'Try again in 30s.');
    expect(line('RATE_LIMITED', null), 'Too many tries. Wait a moment.');
  });

  test('why a name cannot be had', () {
    expect(usernameReasonMessage('TAKEN'), 'Taken');
    expect(usernameReasonMessage('RESERVED'), 'Not available');
    expect(usernameReasonMessage('INVALID'), kUsernameRule);
    expect(usernameReasonMessage(null), kUsernameRule);
  });

  ClaimResult claimed({
    int bonus = 0,
    String? reason,
    String? outcome,
    int referral = 0,
  }) =>
      ClaimResult(
        user: AccountUser.fromJson(userJson()),
        bonusCredits: bonus,
        bonusReason: reason,
        referralOutcome: outcome,
        referralCredits: referral,
      );

  test('a claim explains itself in at most one line', () {
    expect(claimResultLines(claimed(bonus: 100)), isEmpty);
    expect(
      claimResultLines(claimed(bonus: 100, outcome: 'rewarded', referral: 20)),
      ['Includes 20 from your invite'],
    );
    expect(
      claimResultLines(claimed(reason: 'BONUS_ALREADY_CLAIMED')),
      ['This email or phone has already had its free credits.'],
    );
    expect(
      claimResultLines(claimed(reason: 'IP_LIMIT_REACHED')),
      ["Free credits aren't available on this network today."],
    );
    expect(claimResultLines(claimed()), ['No free credits this time.']);
  });
}
