import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_pacing.dart';
import 'ads_sdk.dart';
import 'work_ad.dart';

export 'ad_pacing.dart' show AdPlacement;

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

  /// Photo compression's Best quality unlock: off until talked through.
  static const bool photoCompressionAds = false;

  /// The editor's export — its interstitials and its 4K unlock: off, the
  /// next to be talked through.
  static const bool exportAds = false;

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

  static const Map<AdPlacement, WorkAdRule> _workAdRules = {
    AdPlacement.videoCompression: kVideoCompressionAdRule,
    AdPlacement.privacyStrip: kPrivacyStripAdRule,
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
  /// — and for video compression the rewarded ad that unlocks Best quality.
  /// Called when its screen opens. Never throws; nothing waits on it.
  static Future<void> prepare(AdPlacement placement) async {
    if (!isOn(placement)) return;
    if (await AdsSdk.start() != null) return;
    if (_workAdRules.containsKey(placement)) loadInterstitialAd();
    if (placement == AdPlacement.videoCompression) loadRewardedAd();
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

  /// An interstitial before [onAdDismissed] — the editor's export, off for
  /// now. Shows a loaded ad if there is one and never waits for one to
  /// load; [onAdDismissed] runs exactly once either way.
  static Future<void> showInterstitialAd(
    BuildContext context, {
    required AdPlacement placement,
    required VoidCallback onAdDismissed,
  }) async {
    if (isOn(placement) && _interstitialReady()) {
      await _showInterstitial();
    }
    onAdDismissed();
  }

  // --- REWARDED ADS ---
  static RewardedAd? _rewardedAd;
  static DateTime? _rewardedLoadedAt;
  static bool _isRewardedAdLoading = false;

  /// Loads one rewarded ad (the Pro unlocks) in the background, unless one
  /// is loaded or on its way. A failed load waits for the next ask.
  static void loadRewardedAd() {
    if (!AdsSdk.started || _rewardedAd != null || _isRewardedAdLoading) {
      return;
    }
    _isRewardedAdLoading = true;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedLoadedAt = DateTime.now();
          _isRewardedAdLoading = false;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Rewarded ad failed to load: ${err.message}');
          _isRewardedAdLoading = false;
        },
      ),
    );
  }

  /// Shows the loaded rewarded ad: [onRewardEarned] if the user watches it
  /// to the reward, otherwise [onFailed] — and [onFailed] at once when none
  /// is loaded. Off for [placement], the unlock is granted without an ad.
  ///
  /// The user chose to watch it — rewarded ads must be opted into — and no
  /// interstitial follows it within [AdPacing.minApart].
  static Future<void> showRewardedAd(
    BuildContext context, {
    required AdPlacement placement,
    required VoidCallback onRewardEarned,
    required VoidCallback onFailed,
  }) async {
    if (!isOn(placement)) {
      onRewardEarned();
      return;
    }
    final ad = _rewardedAd;
    final loadedAt = _rewardedLoadedAt;
    _rewardedAd = null;
    _rewardedLoadedAt = null;
    if (ad == null ||
        loadedAt == null ||
        DateTime.now().difference(loadedAt) > adLifetime) {
      if (ad != null) unawaited(ad.dispose());
      loadRewardedAd();
      onFailed();
      return;
    }

    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shown) {
        unawaited(shown.dispose());
        pacing.otherAdShown();
        loadRewardedAd();
        if (!earned) onFailed();
      },
      onAdFailedToShowFullScreenContent: (shown, error) {
        debugPrint('Rewarded ad failed to show: $error');
        unawaited(shown.dispose());
        loadRewardedAd();
        onFailed();
      },
    );
    ad.show(onUserEarnedReward: (_, _) {
      earned = true;
      onRewardEarned();
    });
  }
}

/// The ads plugin's interstitial, behind [InterstitialPresenter].
class _PluginInterstitial implements InterstitialPresenter {
  const _PluginInterstitial();

  @override
  bool get ready => AdService._interstitialReady();

  @override
  Future<void> show() => AdService._showInterstitial();
}
