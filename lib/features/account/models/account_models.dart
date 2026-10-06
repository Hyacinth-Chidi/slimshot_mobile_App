import '../../../core/services/account_session.dart';
import '../../../core/services/slimshot_api.dart';

/// The signed-in user, as `/me` describes them.
class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.username,
    required this.referralCode,
    required this.creditBalance,
    required this.suspended,
    required this.needsClaim,
  });

  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        username: json['username'] as String?,
        referralCode: json['referralCode'] as String? ?? '',
        creditBalance: (json['creditBalance'] as num?)?.toInt() ?? 0,
        suspended: json['accountStatus'] == 'suspended',
        needsClaim: json['needsClaim'] as bool? ?? false,
      );

  final String id;
  final String email;

  /// Null until the claim step has chosen one.
  final String? username;

  /// The user's own code to share — not the username.
  final String referralCode;

  /// Whole credits; never below zero.
  final int creditBalance;

  /// A suspended account can sign in and look, but not spend or claim.
  final bool suspended;

  /// A new account that has not chosen a username and claimed yet.
  final bool needsClaim;

  Map<String, Object?> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'referralCode': referralCode,
        'creditBalance': creditBalance,
        'accountStatus': suspended ? 'suspended' : 'active',
        'needsClaim': needsClaim,
      };

  /// The same user with a balance a spend answered with.
  AccountUser withBalance(int balance) => AccountUser(
        id: id,
        email: email,
        username: username,
        referralCode: referralCode,
        creditBalance: balance,
        suspended: suspended,
        needsClaim: needsClaim,
      );
}

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw SlimshotApiException(SlimshotApiException.badResponse, 'No $what.');
}

/// What a successful sign-in answers: the session and the user.
class SignInResult {
  const SignInResult({required this.tokens, required this.user});

  factory SignInResult.fromJson(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No session.',
      );
    }
    return SignInResult(
      tokens: SessionTokens(accessToken: access, refreshToken: refresh),
      user: AccountUser.fromJson(_object(json['user'], 'user')),
    );
  }

  final SessionTokens tokens;
  final AccountUser user;
}

/// An emailed code is on its way.
class EmailCodeSent {
  const EmailCodeSent({required this.sentTo, required this.resendAfter});

  factory EmailCodeSent.fromJson(Map<String, dynamic> json) => EmailCodeSent(
        sentTo: json['sentTo'] as String? ?? '',
        resendAfter: Duration(
          seconds: (json['resendAfterSeconds'] as num?)?.toInt() ?? 60,
        ),
      );

  final String sentTo;

  /// How long before another code may be asked for.
  final Duration resendAfter;
}

/// Whether a username can be had, and if not, why.
class UsernameAvailability {
  const UsernameAvailability({required this.available, this.reason});

  factory UsernameAvailability.fromJson(Map<String, dynamic> json) =>
      UsernameAvailability(
        available: json['available'] == true,
        reason: json['reason'] as String?,
      );

  final bool available;

  /// `INVALID`, `RESERVED` or `TAKEN` when not available.
  final String? reason;
}

/// What the claim step granted, and why when it granted nothing.
class ClaimResult {
  const ClaimResult({
    required this.user,
    required this.bonusCredits,
    this.bonusReason,
    this.referralOutcome,
    this.referralCredits = 0,
  });

  factory ClaimResult.fromJson(Map<String, dynamic> json) {
    final bonus = json['bonus'] is Map
        ? Map<String, dynamic>.from(json['bonus'] as Map)
        : const <String, dynamic>{};
    final referral = json['referral'] is Map
        ? Map<String, dynamic>.from(json['referral'] as Map)
        : null;
    return ClaimResult(
      user: AccountUser.fromJson(_object(json['user'], 'user')),
      bonusCredits: bonus['granted'] == true
          ? (bonus['credits'] as num?)?.toInt() ?? 0
          : 0,
      bonusReason: bonus['reason'] as String?,
      referralOutcome: referral?['outcome'] as String?,
      referralCredits: (referral?['credits'] as num?)?.toInt() ?? 0,
    );
  }

  final AccountUser user;

  /// The signup bonus granted; 0 when it was not.
  final int bonusCredits;

  /// Why the bonus was not granted: `BONUS_ALREADY_CLAIMED` or
  /// `IP_LIMIT_REACHED`.
  final String? bonusReason;

  /// `rewarded`, `inviter_capped` or `invitee_ineligible`; null without a
  /// code.
  final String? referralOutcome;

  /// The invite credits this user got.
  final int referralCredits;

  int get creditsGranted => bonusCredits + referralCredits;
}

/// What a run will cost, asked of the server before anything is uploaded.
/// The app never works a price out itself: the owner can change the pricing
/// at any time (contract §11).
class CreditQuote {
  const CreditQuote({
    required this.credits,
    required this.balance,
    required this.enough,
  });

  factory CreditQuote.fromJson(Map<String, dynamic> json) {
    final credits = (json['credits'] as num?)?.toInt() ?? 0;
    final balance = (json['balance'] as num?)?.toInt() ?? 0;
    return CreditQuote(
      credits: credits,
      balance: balance,
      // Worked out, never assumed: a missing flag must not read as yes.
      enough: json['enough'] as bool? ?? balance >= credits,
    );
  }

  final int credits;
  final int balance;
  final bool enough;

  /// Nothing to confirm: the price step is skipped.
  bool get isFree => credits <= 0;
}
