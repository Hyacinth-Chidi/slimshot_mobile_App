import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static InterstitialAd? _interstitialAd;
  static bool _isAdReady = false;
  static bool _isLoading = false;

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

  /// Preloads an interstitial ad in the background. Call this when entering the result screen.
  static void loadInterstitialAd() {
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
}
