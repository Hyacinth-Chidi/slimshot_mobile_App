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
    this.ads = const AdAllowance.none(),
  });

  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        username: json['username'] as String?,
        referralCode: json['referralCode'] as String? ?? '',
        creditBalance: (json['creditBalance'] as num?)?.toInt() ?? 0,
        suspended: json['accountStatus'] == 'suspended',
        needsClaim: json['needsClaim'] as bool? ?? false,
        ads: AdAllowance.fromJson(json['ads']),
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

  /// Today's rewarded ads (`/me.ads`).
  final AdAllowance ads;

  Map<String, Object?> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'referralCode': referralCode,
        'creditBalance': creditBalance,
        'accountStatus': suspended ? 'suspended' : 'active',
        'needsClaim': needsClaim,
        // Unknown stays unknown when cached, never "0 left".
        if (ads.known) 'ads': ads.toJson(),
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
        ads: ads,
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
    final credits = json['credits'];
    final balance = json['balance'];
    // A price missing is refused, never read as 0: free would skip the
    // price step while the server still charged.
    if (credits is! num || balance is! num) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No price.',
      );
    }
    return CreditQuote(
      credits: credits.toInt(),
      balance: balance.toInt(),
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

/// Today's rewarded ads, as `/me.ads` describes them. Resets at 00:00 UTC.
class AdAllowance {
  const AdAllowance({
    required this.rewardCredits,
    required this.dailyCap,
    required this.remainingToday,
  }) : known = true;

  /// Not known yet: a profile without `ads` — one cached by a build from
  /// before rewarded ads, until `/me` answers. Not "none left": read that
  /// way it showed Back tomorrow to someone with every ad still to watch.
  const AdAllowance.none()
      : rewardCredits = 0,
        dailyCap = 0,
        remainingToday = 0,
        known = false;

  factory AdAllowance.fromJson(Object? json) {
    if (json is! Map) return const AdAllowance.none();
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AdAllowance(
      rewardCredits: read('rewardCredits'),
      dailyCap: read('dailyCap'),
      remainingToday: read('remainingToday'),
    );
  }

  final int rewardCredits;
  final int dailyCap;
  final int remainingToday;
  final bool known;

  Map<String, Object?> toJson() => {
        'rewardCredits': rewardCredits,
        'dailyCap': dailyCap,
        'remainingToday': remainingToday,
      };
}

/// One rewarded ad's session: what its server-side verification carries.
class AdSession {
  const AdSession({
    required this.nonce,
    required this.ssvUserId,
    required this.rewardCredits,
    required this.adsRemainingToday,
  });

  factory AdSession.fromJson(Map<String, dynamic> json) {
    final nonce = json['nonce'];
    final ssvUserId = json['ssvUserId'];
    if (nonce is! String || ssvUserId is! String) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No ad session.',
      );
    }
    return AdSession(
      nonce: nonce,
      ssvUserId: ssvUserId,
      rewardCredits: (json['rewardCredits'] as num?)?.toInt() ?? 0,
      adsRemainingToday: (json['adsRemainingToday'] as num?)?.toInt() ?? 0,
    );
  }

  final String nonce;
  final String ssvUserId;
  final int rewardCredits;
  final int adsRemainingToday;
}

/// How an ad's reward went: `pending`, `granted`, `capped` or `rejected`.
class AdSessionStatus {
  const AdSessionStatus({
    required this.status,
    this.credits = 0,
    this.balance,
  });

  factory AdSessionStatus.fromJson(Map<String, dynamic> json) =>
      AdSessionStatus(
        status: json['status'] as String? ?? 'pending',
        credits: (json['credits'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt(),
      );

  final String status;
  final int credits;

  /// The balance after a grant; absent until then.
  final int? balance;
}

/// One line of the credit history.
class CreditEntry {
  const CreditEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
  });

  factory CreditEntry.fromJson(Map<String, dynamic> json) => CreditEntry(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final DateTime createdAt;
}

/// A page of history, newest first; [nextCursor] null at the end.
class CreditHistoryPage {
  const CreditHistoryPage({required this.items, this.nextCursor});

  factory CreditHistoryPage.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    return CreditHistoryPage(
      items: items is List
          ? [
              for (final item in items)
                if (item is Map)
                  CreditEntry.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<CreditEntry> items;
  final String? nextCursor;
}
