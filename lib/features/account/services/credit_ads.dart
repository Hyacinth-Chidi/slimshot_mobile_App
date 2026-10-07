import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// How a play went, and — when no ad showed — why, in AdMob's own words
/// where it gave any. Said in debug builds only (`adRewardMessage`).
class AdPlay {
  const AdPlay(this.playback, {this.failure});

  const AdPlay.notShown(String why)
      : playback = AdPlayback.notShown,
        failure = why;

  final AdPlayback playback;
  final String? failure;
}

/// One rewarded ad: loaded, given its server-side verification, shown.
/// Behind an interface so the flow is tested without a device.
abstract class RewardedAdPlayer {
  /// Gets an ad ready ahead of the tap: the consent step, the SDK, one ad
  /// loaded. Never throws; a failure is met again, and named, by [play].
  Future<void> prepare();

  /// Completes when the ad closes. [userId] and [customData] go into the
  /// ad's server-side verification **before** it shows.
  Future<AdPlay> play({required String userId, required String customData});
}

/// The `google_mobile_ads` rewarded ad. The one piece of the flow that
/// needs a device; everything around it is tested against a fake.
///
/// One ad is kept loaded ahead of the tap ([prepare], and again after every
/// play): loading only on the tap made the user wait out the consent check,
/// the SDK start and the load together, which a slow connection could not
/// finish inside [loadTimeout].
class PluginRewardedAdPlayer implements RewardedAdPlayer {
  PluginRewardedAdPlayer(this.adUnitId);

  final String adUnitId;

  /// How long a tap waits for an ad that is not loaded yet. A load that
  /// outlasts it is kept for the next tap, not thrown away.
  static const Duration loadTimeout = Duration(seconds: 15);

  static const Duration consentTimeout = Duration(seconds: 10);

  /// AdMob keeps a loaded rewarded ad showable for an hour.
  static const Duration adLifetime = Duration(minutes: 50);

  static const String _tag = 'SlimshotAds';

  /// The consent step, then the SDK: null once ads may be requested,
  /// otherwise why not. Cleared on a failure so the next ask tries again.
  static Future<String?>? _sdk;

  RewardedAd? _ad;
  DateTime? _adLoadedAt;
  Future<String?>? _loading;

  @override
  Future<void> prepare() async {
    try {
      if (await _startSdk() == null) unawaited(_load());
    } catch (e) {
      debugPrint('$_tag: prepare failed: $e');
    }
  }

  static Future<String?> _startSdk() => _sdk ??= _consentThenStart();

  /// Google's consent step (UMP), then the SDK — once per launch, and only
  /// when credit ads are on screen, so a user who never earns credits never
  /// starts the ads SDK. In the EEA, the UK and Switzerland ads need consent
  /// to serve; elsewhere Google answers that none is required.
  ///
  /// **The last answer is used first** (Google's own pattern): where an
  /// earlier check already allowed ads, the SDK starts at once and the check
  /// is refreshed alongside, so a weak connection does not hold every ad
  /// behind a network round trip. Only with no answer yet is it waited for.
  static Future<String?> _consentThenStart() async {
    try {
      final consent = ConsentInformation.instance;
      if (await consent.canRequestAds()) {
        unawaited(_checkConsent());
      } else {
        final failed = await _checkConsent();
        if (!await consent.canRequestAds()) {
          _sdk = null;
          return failed ?? 'consent not given';
        }
      }
      await MobileAds.instance.initialize();
      return null;
    } catch (e) {
      _sdk = null;
      return 'ads SDK: $e';
    }
  }

  /// Asks Google whether a consent form is needed and shows it if so.
  /// Null when the check answered; otherwise why it did not.
  static Future<String?> _checkConsent() async {
    try {
      final updated = Completer<String?>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!updated.isCompleted) updated.complete(null);
        },
        (error) {
          if (!updated.isCompleted) {
            updated.complete(
                'consent check failed (${error.errorCode}: ${error.message})');
          }
        },
      );
      final failed = await updated.future.timeout(
        consentTimeout,
        onTimeout: () => 'consent check timed out',
      );
      if (failed != null) {
        debugPrint('$_tag: $failed');
        return failed;
      }
      final dismissed = Completer<void>();
      unawaited(ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!dismissed.isCompleted) dismissed.complete();
      }));
      await dismissed.future;
      return null;
    } catch (e) {
      debugPrint('$_tag: consent check: $e');
      return 'consent check: $e';
    }
  }

  bool get _hasFreshAd {
    final loadedAt = _adLoadedAt;
    return _ad != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) <= adLifetime;
  }

  /// The loaded ad if it is still showable, taken out of the cache.
  RewardedAd? _take() {
    final ad = _ad;
    final fresh = _hasFreshAd;
    _ad = null;
    _adLoadedAt = null;
    if (ad == null) return null;
    if (!fresh) {
      unawaited(ad.dispose());
      return null;
    }
    return ad;
  }

  /// One load at a time; the ad lands in the cache whenever it arrives.
  /// Completes with why it failed, or null when an ad is ready.
  Future<String?> _load() {
    if (_hasFreshAd) return Future.value(null);
    return _loading ??= _loadOnce().whenComplete(() => _loading = null);
  }

  Future<String?> _loadOnce() {
    final done = Completer<String?>();
    void finish(String? why) {
      if (why != null) debugPrint('$_tag: load failed: $why');
      if (!done.isCompleted) done.complete(why);
    }

    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          final previous = _ad;
          if (previous != null) unawaited(previous.dispose());
          _ad = ad;
          _adLoadedAt = DateTime.now();
          finish(null);
        },
        onAdFailedToLoad: (error) =>
            finish('AdMob ${error.code}: ${error.message}'),
      ),
    ).catchError((Object e) => finish('load: $e'));
    return done.future;
  }

  @override
  Future<AdPlay> play({
    required String userId,
    required String customData,
  }) async {
    try {
      final blocked = await _startSdk();
      if (blocked != null) return AdPlay.notShown(blocked);
      var ad = _take();
      if (ad == null) {
        final failed = await _load().timeout(
          loadTimeout,
          onTimeout: () => 'no ad within ${loadTimeout.inSeconds}s',
        );
        ad = _take();
        if (ad == null) return AdPlay.notShown(failed ?? 'no ad loaded');
      }

      await ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: userId, customData: customData),
      );
      var earned = false;
      final closed = Completer<AdPlay>();
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          unawaited(ad.dispose());
          if (!closed.isCompleted) {
            closed.complete(
                AdPlay(earned ? AdPlayback.earned : AdPlayback.closed));
          }
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          unawaited(ad.dispose());
          if (!closed.isCompleted) {
            closed.complete(AdPlay.notShown('could not show: ${error.message}'));
          }
        },
      );
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
      final result = await closed.future;
      unawaited(_load()); // The next one, ready before it is asked for.
      return result;
    } catch (e) {
      debugPrint('$_tag: play failed: $e');
      return AdPlay.notShown('$e');
    }
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

/// How one ad went, the balance the server answered with a grant, and —
/// when no ad showed — why.
class AdReward {
  const AdReward(this.outcome, {this.credits = 0, this.balance, this.failure});

  final AdRewardOutcome outcome;
  final int credits;
  final int? balance;
  final String? failure;
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

  /// [onPlayed] hears the ad close (or fail to show): the wait for an ad is
  /// over and the wait for the server's answer begins.
  Future<AdReward> watch({void Function()? onPlayed}) async {
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
    final play = await _player.play(
      userId: session.ssvUserId,
      customData: session.nonce,
    );
    final playback = play.playback;
    onPlayed?.call();
    if (playback == AdPlayback.notShown) {
      return AdReward(AdRewardOutcome.noAd, failure: play.failure);
    }
    final limit = playback == AdPlayback.earned ? pollFor : pollAfterEarlyClose;
    final began = _clock();
    while (_clock().difference(began) < limit) {
      await _delay(pollEvery);
      final AdSessionStatus status;
      try {
        status = await _account.adSession(session.nonce);
      } on SlimshotApiException catch (e) {
        // An idempotent read, after the user sat through an ad: a dropped
        // request, a proxy page or a server hiccup is ridden out within the
        // window. Only a session or a sign-in that is gone ends it.
        if (e.code == 'NOT_FOUND' ||
            e.code == SlimshotApiException.signInRequired) {
          rethrow;
        }
        continue;
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

/// The one line a reward ends with. [withReason] (debug builds) adds why
/// no ad showed, so a device report names the cause rather than "no ad".
String adRewardMessage(AdReward reward, {bool withReason = false}) {
  final line = _adRewardLine(reward);
  final why = reward.failure;
  return withReason && why != null ? '$line ($why)' : line;
}

String _adRewardLine(AdReward reward) => switch (reward.outcome) {
      AdRewardOutcome.granted => '+${reward.credits} credits',
      AdRewardOutcome.capped => "That's today's last reward",
      AdRewardOutcome.rejected => 'No reward this time',
      AdRewardOutcome.notEarned => 'Watch to the end to earn credits',
      AdRewardOutcome.pending => 'Your reward is on its way',
      AdRewardOutcome.noAd => 'No ad right now. Try again soon.',
      AdRewardOutcome.dailyCap => kBackTomorrow,
    };
