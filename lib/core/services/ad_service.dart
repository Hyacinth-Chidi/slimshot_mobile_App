import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  /// **The one switch for every ad in the app. Off for now** — set it to
  /// `true` to bring ads back; nothing else needs to change.
  ///
  /// Off, nothing waits on an ad and nothing an ad unlocked stays locked: an
  /// interstitial's save goes ahead at once, a rewarded ad's unlock is
  /// granted without one, the "Watch ad to unlock" labels hide, and the ads
  /// SDK is never started (`main.dart`). Without an ad there is no other way
  /// to reach a Pro preset or 4K export, so withholding them would lock those
  /// features away entirely.
  static const bool enabled = false;

  /// Rewarded ads that **earn credits**: their own switch, on (spec §3 E).
  /// `enabled` stays off, so interstitials and the Pro-unlock ads stay off;
  /// the SDK starts when either is on (`main.dart`). The reward itself is
  /// verified on the server (SSV), never granted by the app.
  static const bool creditAdsEnabled = true;

  // --- INTERSTITIAL ADS ---
  static InterstitialAd? _interstitialAd;
  static bool _isAdReady = false;
  static bool _isLoading = false;

  // --- REWARDED ADS ---
  static RewardedAd? _rewardedAd;
  static bool _isRewardedAdReady = false;
  static bool _isRewardedAdLoading = false;

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

  // Live Ad Unit IDs for Rewarded Ads
  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7001751702275942/3806842044';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // Still using test ID for iOS until provided
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  /// Preloads an interstitial ad in the background. Call this when entering the result screen.
  static void loadInterstitialAd() {
    if (!enabled) return;
    if (_isAdReady || _isLoading) return;
    _isLoading = true;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Ad loaded successfully');
          _interstitialAd = ad;
          _isAdReady = true;
          _isLoading = false;

          _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isAdReady = false;
              _interstitialAd = null;
              loadInterstitialAd(); // Preload next ad immediately
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Ad failed to show: $error');
              ad.dispose();
              _isAdReady = false;
              _interstitialAd = null;
              loadInterstitialAd(); // Retry loading
            },
          );
        },
        onAdFailedToLoad: (err) {
          debugPrint('Ad failed to load: ${err.message}');
          _isAdReady = false;
          _interstitialAd = null;
          _isLoading = false;
          
          // Retry after delay
          Future.delayed(const Duration(seconds: 10), loadInterstitialAd);
        },
      ),
    );
  }

  /// Shows the preloaded ad with a smart timeout loader.
  /// If the ad is ready, it shows instantly.
  /// If not, it displays a loading dialog for up to 3 seconds, waiting for the ad.
  /// Always executes [onAdDismissed] exactly once to guarantee the save flow.
  static Future<void> showInterstitialAd(
      BuildContext context, {required VoidCallback onAdDismissed}) async {
    if (!enabled) {
      onAdDismissed();
      return;
    }

    // Helper to setup callbacks and show ad
    void showAdNow() {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _isAdReady = false;
          _interstitialAd = null;
          onAdDismissed(); // Trigger the save action when ad closes
          loadInterstitialAd(); // Preload next ad in background
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('Ad failed to show: $error');
          ad.dispose();
          _isAdReady = false;
          _interstitialAd = null;
          onAdDismissed(); // Fallback if ad fails to show
          loadInterstitialAd(); // Preload next ad in background
        },
      );
      _interstitialAd!.show();
    }

    if (_isAdReady && _interstitialAd != null) {
      // Ad is already loaded! Show it instantly.
      showAdNow();
      return;
    }

    // Ad is not ready. Show a smart loading dialog.
    debugPrint('Ad not ready yet. Showing smart loader...');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.9), // Slate 900
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)), // Slate 700
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF8B5CF6)), // Violet 500
                SizedBox(height: 16),
                Text(
                  'Preparing...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Poll for up to 3 seconds (30 checks * 100ms)
    bool adLoadedDuringWait = false;
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isAdReady && _interstitialAd != null) {
        adLoadedDuringWait = true;
        break;
      }
    }

    // Dismiss the loading dialog
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (adLoadedDuringWait) {
      debugPrint('Ad loaded during wait! Showing ad now.');
      showAdNow();
    } else {
      debugPrint('Ad timed out after 3 seconds. Proceeding to save.');
      onAdDismissed(); // Proceed immediately
    }
  }

  // ==========================================
  // REWARDED ADS IMPLEMENTATION
  // ==========================================

  /// Preloads a rewarded ad in the background.
  static void loadRewardedAd() {
    if (!enabled) return;
    if (_isRewardedAdReady || _isRewardedAdLoading) return;
    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('Rewarded Ad loaded successfully');
          _rewardedAd = ad;
          _isRewardedAdReady = true;
          _isRewardedAdLoading = false;

          _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isRewardedAdReady = false;
              _rewardedAd = null;
              loadRewardedAd(); // Preload next ad immediately
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Rewarded Ad failed to show: $error');
              ad.dispose();
              _isRewardedAdReady = false;
              _rewardedAd = null;
              loadRewardedAd(); // Retry loading
            },
          );
        },
        onAdFailedToLoad: (err) {
          debugPrint('Rewarded Ad failed to load: ${err.message}');
          _isRewardedAdReady = false;
          _rewardedAd = null;
          _isRewardedAdLoading = false;
          
          // Retry after delay
          Future.delayed(const Duration(seconds: 10), loadRewardedAd);
        },
      ),
    );
  }

  /// Shows the preloaded rewarded ad.
  /// If ad is not ready or fails, invokes [onFailed].
  /// If the user fully watches the ad, invokes [onRewardEarned].
  static Future<void> showRewardedAd(
      BuildContext context, {
      required VoidCallback onRewardEarned,
      required VoidCallback onFailed,
  }) async {
    if (!enabled) {
      onRewardEarned();
      return;
    }

    if (!_isRewardedAdReady || _rewardedAd == null) {
      debugPrint('Rewarded Ad is not ready.');
      onFailed();
      return;
    }

    bool rewardEarned = false;

    // We must reset the callback before showing it to handle the specific reward action for this call
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _isRewardedAdReady = false;
        _rewardedAd = null;
        loadRewardedAd(); // Preload next ad in background
        if (!rewardEarned) {
           debugPrint('Rewarded Ad dismissed without earning reward.');
           onFailed();
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('Rewarded Ad failed to show: $error');
        ad.dispose();
        _isRewardedAdReady = false;
        _rewardedAd = null;
        loadRewardedAd(); // Preload next ad in background
        onFailed();
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      debugPrint('User earned reward: ${reward.amount} ${reward.type}');
      rewardEarned = true;
      onRewardEarned();
    });
  }
}
