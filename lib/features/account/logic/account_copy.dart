import '../../../core/services/slimshot_api.dart';
import '../models/account_models.dart';

/// Google's picker failed for a reason other than the user closing it. A
/// local code, never the server's.
const String kGoogleSignInFailed = 'GOOGLE_SIGN_IN_FAILED';

/// The username rule, in the words the field shows.
const String kUsernameRule = '3–20 letters, numbers or _';

/// The one line the user sees for an account [error] — no title, no code.
String accountErrorMessage(Object error) {
  if (error is! SlimshotApiException) return 'Something went wrong. Try again.';
  return switch (error.code) {
    SlimshotApiException.network =>
      'No connection. Check your internet and try again.',
    'GOOGLE_TOKEN_INVALID' || kGoogleSignInFailed =>
      "Google sign-in didn't work. Try again.",
    'GOOGLE_EMAIL_UNVERIFIED' || 'SIGN_IN_METHOD_UNAVAILABLE' =>
      'Use your email instead.',
    'ACCOUNT_LINK_CONFLICT' => 'This email uses a different Google account.',
    'EMAIL_DOMAIN_NOT_ALLOWED' => 'Use a regular email address.',
    'OTP_INVALID' => _wrongCode(error.detailInt('attemptsLeft')),
    'OTP_EXPIRED' || 'OTP_ATTEMPTS_EXCEEDED' => 'Code expired. Send a new one.',
    'OTP_RESEND_TOO_SOON' || 'RATE_LIMITED' =>
      _wait(error.detailInt('retryAfterSeconds')),
    'USERNAME_INVALID' => kUsernameRule,
    'USERNAME_TAKEN' => 'Taken',
    'REFERRAL_CODE_INVALID' => "That invite code doesn't work.",
    'ACCOUNT_SUSPENDED' => 'This account is suspended.',
    SlimshotApiException.signInRequired => 'Sign in again.',
    _ => 'Something went wrong. Try again.',
  };
}

String _wrongCode(int? left) => left == null
    ? 'Wrong code.'
    : 'Wrong code · $left ${left == 1 ? 'try' : 'tries'} left';

String _wait(int? seconds) => seconds == null
    ? 'Too many tries. Wait a moment.'
    : 'Try again in ${seconds}s.';

/// Why a name cannot be had, from the availability answer's reason.
String usernameReasonMessage(String? reason) => switch (reason) {
      'TAKEN' => 'Taken',
      'RESERVED' => 'Not available',
      _ => kUsernameRule,
    };

/// The lines under a claim's headline: where invite credits came from, or
/// honestly why there were no free credits.
List<String> claimResultLines(ClaimResult result) => [
      if (result.bonusCredits > 0 && result.referralCredits > 0)
        'Includes ${result.referralCredits} from your invite',
      if (result.bonusCredits == 0)
        switch (result.bonusReason) {
          'BONUS_ALREADY_CLAIMED' =>
            'This email or phone has already had its free credits.',
          'IP_LIMIT_REACHED' =>
            "Free credits aren't available on this network today.",
          _ => 'No free credits this time.',
        },
    ];

/// "1 credit", "6 credits".
String creditCount(int n) => n == 1 ? '1 credit' : '$n credits';

/// What a run needs when the balance does not cover it — the only price a
/// user is ever shown.
String shortfallLine(int needed, int balance) =>
    'Needs ${creditCount(needed)} · You have $balance';

/// A history line's kind, in plain words.
String creditHistoryLabel(String type) => switch (type) {
      'signup_bonus' => 'Welcome bonus',
      'referral_invitee' => 'Invite bonus',
      'referral_inviter' => 'A friend joined',
      'rewarded_ad' => 'Watched an ad',
      'feature_charge' => 'Auto captions',
      'feature_refund' => 'Refund',
      'admin_adjustment' => 'Adjustment',
      'account_deleted' => 'Account deleted',
      'purchase' => 'Purchase',
      _ => 'Credits',
    };

/// "+5", "−6" (a true minus sign).
String creditAmountLabel(int amount) =>
    amount >= 0 ? '+$amount' : '−${amount.abs()}';

String watchAdLabel(int credits) => 'Watch an ad · +$credits';

/// Before today's allowance is known: no number to promise.
const String kWatchAd = 'Watch an ad';

const String kLoadingAd = 'Loading ad…';

String adsLeftLabel(int remaining) => '$remaining left today';

const String kBackTomorrow = 'Back tomorrow';

/// What Invite a friend shares: the code and where to get the app.
String inviteMessage(String code) =>
    'Get free credits on SlimShot AI with my invite code $code\n'
    'https://play.google.com/store/apps/details?id=com.techfamz.slimshotai';
