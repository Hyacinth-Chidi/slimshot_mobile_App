import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import 'account_service.dart';

/// How a rewarded ad ended.
enum AdPlayback {
  /// No ad could be loaded or shown.
  notShown,

  /// Shown, and closed before the reward was earned.
  closed,

  /// Shown, and watched to the reward.
  earned,
}

/// One rewarded ad: loaded, given its server-side verification, shown.
/// Behind an interface so the flow is tested without a device.
abstract class RewardedAdPlayer {
  /// Completes when the ad closes. [userId] and [customData] go into the
  /// ad's server-side verification **before** it shows.
  Future<AdPlayback> play({required String userId, required String customData});
}

/// The `google_mobile_ads` rewarded ad. The one piece of the flow that
/// needs a device; everything around it is tested against a fake.
class PluginRewardedAdPlayer implements RewardedAdPlayer {
  PluginRewardedAdPlayer(this.adUnitId);

  final String adUnitId;

  static const Duration loadTimeout = Duration(seconds: 15);

  @override
  Future<AdPlayback> play({
    required String userId,
    required String customData,
  }) async {
    final loaded = Completer<RewardedAd?>();
    final timer = Timer(loadTimeout, () {
      if (!loaded.isCompleted) loaded.complete(null);
    });
    unawaited(RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          // Landed after the timeout: nobody is waiting to show it.
          if (loaded.isCompleted) {
            ad.dispose();
            return;
          }
          loaded.complete(ad);
        },
        onAdFailedToLoad: (_) {
          if (!loaded.isCompleted) loaded.complete(null);
        },
      ),
    ));
    final ad = await loaded.future;
    timer.cancel();
    if (ad == null) return AdPlayback.notShown;

    await ad.setServerSideOptions(
      ServerSideVerificationOptions(userId: userId, customData: customData),
    );
    var earned = false;
    final closed = Completer<AdPlayback>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) {
          closed.complete(earned ? AdPlayback.earned : AdPlayback.closed);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(AdPlayback.notShown);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return closed.future;
  }
}

enum AdRewardOutcome {
  granted,
  capped,
  rejected,
  notEarned,
  pending,
  noAd,
  dailyCap,
}

/// How one ad went, and the balance the server answered with a grant.
class AdReward {
  const AdReward(this.outcome, {this.credits = 0, this.balance});

  final AdRewardOutcome outcome;
  final int credits;
  final int? balance;
}

/// One rewarded ad, end to end. **The app never adds credits itself**: AdMob
/// tells the server (SSV), and this only asks the server how it went.
class CreditAdService {
  CreditAdService({
    required AccountService account,
    required RewardedAdPlayer player,
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  })  : _account = account,
        _player = player,
        _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final AccountService _account;
  final RewardedAdPlayer _player;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  static const Duration pollEvery = Duration(seconds: 1);

  /// How long a watched ad's grant is waited for (contract §13).
  static const Duration pollFor = Duration(seconds: 30);

  /// An ad closed before its reward is asked about briefly — AdMob may still
  /// call the server — rather than for the full half minute.
  static const Duration pollAfterEarlyClose = Duration(seconds: 5);

  Future<AdReward> watch() async {
    final AdSession session;
    try {
      // A new session — a new nonce — for every ad.
      session = await _account.startAdSession();
    } on SlimshotApiException catch (e) {
      if (e.code == 'AD_DAILY_CAP_REACHED') {
        return const AdReward(AdRewardOutcome.dailyCap);
      }
      rethrow;
    }
    final playback = await _player.play(
      userId: session.ssvUserId,
      customData: session.nonce,
    );
    if (playback == AdPlayback.notShown) {
      return const AdReward(AdRewardOutcome.noAd);
    }
    final limit = playback == AdPlayback.earned ? pollFor : pollAfterEarlyClose;
    final began = _clock();
    while (_clock().difference(began) < limit) {
      await _delay(pollEvery);
      final AdSessionStatus status;
      try {
        status = await _account.adSession(session.nonce);
      } on SlimshotApiException catch (e) {
        if (e.code == SlimshotApiException.network) continue;
        rethrow;
      }
      switch (status.status) {
        case 'granted':
          return AdReward(
            AdRewardOutcome.granted,
            credits: status.credits,
            balance: status.balance,
          );
        case 'capped':
          return const AdReward(AdRewardOutcome.capped);
        case 'rejected':
          return const AdReward(AdRewardOutcome.rejected);
      }
    }
    return AdReward(
      playback == AdPlayback.earned
          ? AdRewardOutcome.pending
          : AdRewardOutcome.notEarned,
    );
  }
}

/// The one line a reward ends with.
String adRewardMessage(AdReward reward) => switch (reward.outcome) {
      AdRewardOutcome.granted => '+${reward.credits} credits',
      AdRewardOutcome.capped => "That's today's last reward",
      AdRewardOutcome.rejected => 'No reward this time',
      AdRewardOutcome.notEarned => 'Watch to the end to earn credits',
      AdRewardOutcome.pending => 'Your reward is on its way',
      AdRewardOutcome.noAd => 'No ad right now. Try again soon.',
      AdRewardOutcome.dailyCap => kBackTomorrow,
    };
