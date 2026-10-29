/// Where in the app an ad may show. Ads come back one placement at a time,
/// each on its own switch (`AdService.isOn`).
enum AdPlacement {
  /// An interstitial over a running video compression; Best quality is
  /// unlocked by a rewarded ad instead.
  videoCompression,

  /// An interstitial over a running photo compression, a second in however
  /// fast; Best quality is unlocked by a rewarded ad instead.
  photoCompression,

  /// The editor's export: now and then an interstitial after it, before the
  /// finished video, never on a user's first three exports.
  export,
}

/// How often an interstitial may show: at most one per placement's [gaps]
/// (the owner's numbers), and never two ads within [minApart] of each other,
/// whichever placements showed them — Google disallows an interstitial
/// straight after another, and a rewarded ad counts ([otherAdShown]).
///
/// Kept for the session only: a restart is a break of its own.
class AdPacing {
  AdPacing({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  static const Map<AdPlacement, Duration> gaps = {
    AdPlacement.videoCompression: Duration(minutes: 4),
    AdPlacement.photoCompression: Duration(minutes: 6),
    AdPlacement.export: Duration(minutes: 5),
  };

  static const Duration minApart = Duration(minutes: 1);

  final Map<AdPlacement, DateTime> _lastShown = {};
  DateTime? _lastAny;

  /// Whether [placement]'s interstitial may show now.
  bool isDue(AdPlacement placement) {
    final now = _now();
    final any = _lastAny;
    if (any != null && now.difference(any) < minApart) return false;
    final last = _lastShown[placement];
    final gap = gaps[placement] ?? Duration.zero;
    return last == null || now.difference(last) >= gap;
  }

  /// [placement]'s interstitial has just shown.
  void shown(AdPlacement placement) {
    final now = _now();
    _lastShown[placement] = now;
    _lastAny = now;
  }

  /// Another full-screen ad has just shown (a rewarded unlock): no
  /// interstitial follows it within [minApart].
  void otherAdShown() => _lastAny = _now();
}
