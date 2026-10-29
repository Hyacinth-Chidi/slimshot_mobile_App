import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import 'ad_pacing.dart';
import 'ads_sdk.dart';
import 'rewarded_unlock.dart';
import 'work_ad.dart';

export 'ad_pacing.dart' show AdPlacement;
export 'rewarded_unlock.dart' show UnlockFailure, unlockFailureMessage;

class AdService {
  /// **Ads come back one placement at a time, each on its own switch** (the
  /// owner's call, 2026-10-28; every ad was off from 2026-10-03). Off, a
  /// placement waits on no ad and keeps nothing locked: its step goes ahead
  /// at once, its rewarded unlock is granted without one, and its views show
  /// no unlock badge.
  ///
  /// Video compression: an interstitial over a running compression
  /// ([kVideoCompressionAdRule]; one per four minutes at most, [AdPacing]);
  /// Best quality unlocked by a rewarded ad, its compressions getting no
  /// interstitial.
  static const bool videoCompressionAds = true;

  /// Privacy Strip: an interstitial on every strip, however small or fast
  /// ([kPrivacyStripAdRule]; one per six minutes at most).
  static const bool privacyStripAds = true;

  /// Photo compression (2026-10-29): an interstitial on every compression,
  /// however fast, timed as Privacy Strip's ([kPhotoCompressionAdRule]; one
  /// per six minutes at most); Best quality unlocked by a rewarded ad, its
  /// compressions getting no interstitial.
  static const bool photoCompressionAds = true;

  /// The editor's export (2026-10-29): an interstitial **after** it, before
  /// the finished video — never over it, which would share the hardware
  /// codecs it runs on — and only now and then (`showExportAd`: never a
  /// user's first export, never 4K, otherwise by chance; one per five
  /// minutes at most). 4K is unlocked by a rewarded ad.
  static const bool exportAds = true;

  static bool isOn(AdPlacement placement) => switch (placement) {
        AdPlacement.videoCompression => videoCompressionAds,
        AdPlacement.privacyStrip => privacyStripAds,
        AdPlacement.photoCompression => photoCompressionAds,
        AdPlacement.export => exportAds,
      };

  /// Rewarded ads that **earn credits**: their own switch, on (spec §3 E).
  /// A credit ad starts the SDK itself, after the consent step ([AdsSdk]),
  /// on the first Watch an ad. The reward is verified on the server (SSV),
  /// never granted by the app.
  static const bool creditAdsEnabled = true;

  /// How often an interstitial may show, across the app.
  static final AdPacing pacing = AdPacing();

  /// The placements whose ad shows over their job; export's comes after
  /// it ([afterWork]).
  static const Map<AdPlacement, WorkAdRule> _workAdRules = {
    AdPlacement.videoCompression: kVideoCompressionAdRule,
    AdPlacement.privacyStrip: kPrivacyStripAdRule,
    AdPlacement.photoCompression: kPhotoCompressionAdRule,
  };

  /// The placements with something a rewarded ad unlocks: Best quality, 4K.
  static const Set<AdPlacement> _rewardedUnlocks = {
    AdPlacement.videoCompression,
    AdPlacement.photoCompression,
    AdPlacement.export,
  };

  /// AdMob keeps a loaded ad showable for an hour.
  static const Duration adLifetime = Duration(minutes: 50);

  // Live Ad Unit IDs provided by TechFamz
  static String get _interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7001751702275942/1220151318';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// The rewarded unit that **earns credits** ("earn credits"): the one
  /// whose server-side verification calls the server. Not [rewardedAdUnitId]
  /// — that unit has no callback, so an ad from it could never pay.
  static const String creditAdUnitIdAndroid =
      'ca-app-pub-7001751702275942/2451324896';

  static String get creditAdUnitId {
    if (Platform.isAndroid) return creditAdUnitIdAndroid;
    if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // test ID until provided
    }
    throw UnsupportedError('Unsupported platform');
  }

  // Live Ad Unit IDs for Rewarded Ads (Pro unlocks)
  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7001751702275942/3806842044';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // Still using test ID for iOS until provided
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Gets [placement]'s ads ready ahead of its moment: Google's consent
  /// step and the SDK (once a launch, [AdsSdk]), then an interstitial loaded
  /// — and, where something is unlocked by one, a rewarded ad. Called when
  /// its screen opens. Never throws; nothing waits on it.
  static Future<void> prepare(AdPlacement placement) async {
    if (!isOn(placement)) return;
    if (await AdsSdk.start() != null) return;
    loadInterstitialAd();
    if (_rewardedUnlocks.contains(placement)) loadRewardedAd();
  }

  /// [placement]'s interstitial after its job, before what follows it
  /// ([adAfterWork]): completes once it has closed, or at once when none
  /// shows. Off, nothing.
  static Future<void> afterWork(
    AdPlacement placement, {
    bool Function()? wanted,
  }) {
    if (!isOn(placement)) return Future.value();
    return adAfterWork(
      placement: placement,
      pacing: pacing,
      presenter: const _PluginInterstitial(),
      wanted: wanted ?? () => true,
    );
  }

  /// [placement]'s interstitial over [work], a job already running
  /// ([adOverWork]): completes once the job has ended and any ad has
  /// closed. Off, it is the job alone. [wanted] says whether the job still
  /// counts when its ad is due: still on screen, not cancelled, not failed.
  static Future<void> overWork(
    AdPlacement placement, {
    required Future<void> work,
    required double Function() progress,
    bool Function()? wanted,
  }) {
    final rule = _workAdRules[placement];
    if (!isOn(placement) || rule == null) return work;
    return adOverWork(
      placement: placement,
      rule: rule,
      work: work,
      progress: progress,
      wanted: wanted ?? () => true,
      pacing: pacing,
      presenter: const _PluginInterstitial(),
    );
  }

  // --- INTERSTITIAL ADS ---
  static InterstitialAd? _interstitialAd;
  static DateTime? _interstitialLoadedAt;
  static bool _isLoading = false;

  /// Loads one interstitial in the background, unless one is loaded or on
  /// its way — and never before the consent step has started the SDK
  /// ([AdsSdk.started]). A failed load is not retried on a timer: the next
  /// screen that shows ads, or the next ad asked for, tries again.
  static void loadInterstitialAd() {
    if (!AdsSdk.started || _interstitialAd != null || _isLoading) return;
    _isLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialLoadedAt = DateTime.now();
          _isLoading = false;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Interstitial failed to load: ${err.message}');
          _isLoading = false;
        },
      ),
    );
  }

  /// Whether a loaded interstitial is fresh enough to show. One too old is
  /// dropped and another asked for; none at all is asked for too, ready for
  /// next time.
  static bool _interstitialReady() {
    final ad = _interstitialAd;
    final loadedAt = _interstitialLoadedAt;
    if (ad != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) <= adLifetime) {
      return true;
    }
    if (ad != null) {
      unawaited(ad.dispose());
      _interstitialAd = null;
      _interstitialLoadedAt = null;
    }
    loadInterstitialAd();
    return false;
  }

  /// Shows the loaded interstitial. Completes when it closes, or at once
  /// when it could not show; the next one is loaded either way.
  static Future<void> _showInterstitial() {
    final ad = _interstitialAd;
    if (ad == null) return Future.value();
    _interstitialAd = null;
    _interstitialLoadedAt = null;
    final closed = Completer<void>();
    void done(InterstitialAd shown) {
      unawaited(shown.dispose());
      if (!closed.isCompleted) closed.complete();
      loadInterstitialAd();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: done,
      onAdFailedToShowFullScreenContent: (shown, error) {
        debugPrint('Interstitial failed to show: $error');
        done(shown);
      },
    );
    ad.show();
    return closed.future;
  }

  // --- REWARDED ADS ---
  static RewardedAd? _rewardedAd;
  static DateTime? _rewardedLoadedAt;

  /// The load on its way: completes with null once it has loaded, otherwise
  /// why not.
  static Completer<UnlockFailure?>? _rewardedLoad;

  /// AdMob's `ERROR_CODE_NETWORK_ERROR`: the one failure that is the
  /// connection's.
  static const int _networkError = 2;

  /// How long an unlock waits for its ad on the way — the consent step, the
  /// SDK and the load — before saying none came.
  static const Duration unlockWait = Duration(seconds: 15);

  /// Loads one rewarded ad (the unlocks) in the background, unless one is
  /// loaded or on its way — never before the consent step has started the
  /// SDK. A failed load waits for the next ask.
  static void loadRewardedAd() {
    if (!AdsSdk.started || _rewardedAd != null || _rewardedLoad != null) {
      return;
    }
    final load = _rewardedLoad = Completer<UnlockFailure?>();
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedLoadedAt = DateTime.now();
          _rewardedLoad = null;
          load.complete(null);
        },
        onAdFailedToLoad: (err) {
          debugPrint('Rewarded ad failed to load: ${err.code} ${err.message}');
          _rewardedLoad = null;
          load.complete(err.code == _networkError
              ? UnlockFailure.offline
              : UnlockFailure.noAd);
        },
      ),
    );
  }

  /// Whether a loaded rewarded ad is fresh enough to show; one too old is
  /// dropped.
  static bool _rewardedReady() {
    final ad = _rewardedAd;
    final loadedAt = _rewardedLoadedAt;
    if (ad != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) <= adLifetime) {
      return true;
    }
    if (ad != null) {
      unawaited(ad.dispose());
      _rewardedAd = null;
      _rewardedLoadedAt = null;
    }
    return false;
  }

  /// Shows a rewarded ad for an unlock: [onRewardEarned] if the user watches
  /// it to the reward, otherwise [onFailed] with why — closed early, no
  /// network, or no ad to be had. Off for [placement], the unlock is granted
  /// without one.
  ///
  /// **An ad still on its way is waited for** ([unlockWait]), with "Loading
  /// ad…" on screen; a tap outside or Back stops waiting, quietly. Before,
  /// a tap a moment after the screen opened — the ad still loading — gave up
  /// at once and blamed the connection (device-reported).
  ///
  /// The user chose to watch it — rewarded ads must be opted into — and no
  /// interstitial follows it within [AdPacing.minApart].
  static Future<void> showRewardedAd(
    BuildContext context, {
    required AdPlacement placement,
    required VoidCallback onRewardEarned,
    required void Function(UnlockFailure failure) onFailed,
  }) async {
    if (!isOn(placement)) {
      onRewardEarned();
      return;
    }
    if (!_rewardedReady()) {
      final (stopped, failure) = await _waitForRewarded(context);
      if (stopped) return;
      if (failure != null) {
        onFailed(failure);
        return;
      }
    }
    final ad = _rewardedAd;
    if (ad == null) {
      onFailed(UnlockFailure.noAd);
      return;
    }
    _rewardedAd = null;
    _rewardedLoadedAt = null;

    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shown) {
        unawaited(shown.dispose());
        pacing.otherAdShown();
        loadRewardedAd();
        if (!earned) onFailed(UnlockFailure.closedEarly);
      },
      onAdFailedToShowFullScreenContent: (shown, error) {
        debugPrint('Rewarded ad failed to show: $error');
        unawaited(shown.dispose());
        loadRewardedAd();
        onFailed(UnlockFailure.noAd);
      },
    );
    ad.show(onUserEarnedReward: (_, _) {
      earned = true;
      onRewardEarned();
    });
  }

  /// Waits for a rewarded ad with "Loading ad…" on screen. Answers whether
  /// the user stopped waiting (a tap outside, Back) and, if not, why no ad
  /// came — null when one is ready.
  static Future<(bool, UnlockFailure?)> _waitForRewarded(
      BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var open = true;
    final dialog = showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _LoadingAd(),
    ).whenComplete(() => open = false);
    final failure = await awaitRewardedAd(
      start: AdsSdk.start,
      ready: _rewardedReady,
      load: () {
        loadRewardedAd();
        return _rewardedLoad?.future ??
            Future.value(_rewardedReady() ? null : UnlockFailure.noAd);
      },
      within: unlockWait,
    );
    if (!open) return (true, null);
    navigator.pop();
    await dialog;
    return (false, failure);
  }
}

/// "Loading ad…": an unlock waiting for its rewarded ad.
class _LoadingAd extends StatelessWidget {
  const _LoadingAd();

  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryStart,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading ad…',
                  style: TextStyle(
                    fontFamily: kInterfaceFontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// The ads plugin's interstitial, behind [InterstitialPresenter].
class _PluginInterstitial implements InterstitialPresenter {
  const _PluginInterstitial();

  @override
  bool get ready => AdService._interstitialReady();

  @override
  Future<void> show() => AdService._showInterstitial();
}
