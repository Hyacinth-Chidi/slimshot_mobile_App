import 'compression_presets.dart';

/// Whether a video compression gets an interstitial over it. Not at Best
/// quality: that was unlocked with a rewarded ad, so its compression has had
/// its ad (the owner's call, 2026-10-28).
bool compressionGetsInterstitial(CompressionPreset? preset) =>
    !(preset?.isPro ?? false);
