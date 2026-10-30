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

  test('a shortfall reads as the spec writes it, singular included', () {
    expect(shortfallLine(6, 2), 'Needs 6 credits · You have 2');
    expect(shortfallLine(1, 0), 'Needs 1 credit · You have 0');
  });

  test('history reads in plain words', () {
    expect(creditHistoryLabel('signup_bonus'), 'Welcome bonus');
    expect(creditHistoryLabel('referral_invitee'), 'Invite bonus');
    expect(creditHistoryLabel('referral_inviter'), 'A friend joined');
    expect(creditHistoryLabel('rewarded_ad'), 'Watched an ad');
    expect(creditHistoryLabel('feature_charge'), 'Auto captions');
    expect(creditHistoryLabel('feature_refund'), 'Refund');
    expect(creditHistoryLabel('admin_adjustment'), 'Adjustment');
    // Daily, weekly or monthly: the line does not say which.
    expect(creditHistoryLabel('daily_reward'), 'Claimed credits');
    expect(creditHistoryLabel('something_new'), 'Credits');
    expect(creditAmountLabel(5), '+5');
    expect(creditAmountLabel(-6), '−6');
  });

  // The owner sets how often in the dashboard: 1, 7 or 30 days.
  test('a credit claim is named for how often it comes', () {
    expect(claimCreditsLabel(5, 1), 'Claim daily credits · +5');
    expect(claimCreditsLabel(20, 7), 'Claim weekly credits · +20');
    expect(claimCreditsLabel(50, 30), 'Claim monthly credits · +50');
    expect(claimCreditsLabel(5, 3), 'Claim credits · +5');
  });

  // A clock under two days — a daily claim's whole wait — and days and
  // hours past that.
  test('the wait for the next claim', () {
    expect(nextClaimLabel(const Duration(hours: 24)), 'Next in 24:00:00');
    expect(
      nextClaimLabel(const Duration(hours: 13, minutes: 4, seconds: 9)),
      'Next in 13:04:09',
    );
    expect(nextClaimLabel(const Duration(seconds: 5)), 'Next in 0:00:05');
    expect(
      nextClaimLabel(const Duration(hours: 47, minutes: 59, seconds: 59)),
      'Next in 47:59:59',
    );
    expect(nextClaimLabel(const Duration(days: 6, hours: 4, minutes: 30)),
        'Next in 6d 4h');
    expect(nextClaimLabel(const Duration(days: 29)), 'Next in 29d 0h');
  });

  test('earning reads as the spec writes it', () {
    expect(watchAdLabel(5), 'Watch an ad · +5');
    expect(adsLeftLabel(7), '7 left today');
    expect(adsLeftLabel(1), '1 left today');
    expect(kBackTomorrow, 'Back tomorrow');
    final invite = inviteMessage('AB3DEF7K');
    expect(invite, contains('AB3DEF7K'));
    expect(invite,
        contains('https://play.google.com/store/apps/details?id=com.techfamz.slimshotai'));
  });
}
