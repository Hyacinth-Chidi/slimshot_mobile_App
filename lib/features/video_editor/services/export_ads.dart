import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/ad_service.dart';

/// What plays between a finished export and its result, given whether
/// anyone is still waiting for it: [showExportAd] in the app, a stand-in in a
/// test.
typedef ExportAd = Future<void> Function(bool Function() wanted);

/// How many exports after installing the app end with no ad at all (the
/// owner's call, 2026-10-29): a new user's first exports are left alone.
const int kExportsWithoutAds = 3;

/// The share of exports after those that end with an interstitial — not
/// every export (the owner's call, 2026-10-29).
const double kExportAdChance = 0.5;

/// Whether a finished export ends with an interstitial: never one of a
/// user's first [kExportsWithoutAds], and after those by chance, [roll]
/// being a draw from 0 up to 1. Its resolution plays no part: no export
/// size is unlocked by an ad.
bool exportGetsInterstitial({
  required int exportsBefore,
  required double roll,
}) =>
    exportsBefore >= kExportsWithoutAds && roll < kExportAdChance;

/// How many exports have finished on this phone: what tells a user's first
/// exports from the rest. Kept in the app's preferences, so it outlasts a
/// launch and starts again from none after a fresh install.
class ExportHistory {
  ExportHistory._();

  static const String _key = 'exportsFinished';

  /// Counts one more finished export, answering how many finished before
  /// it.
  static Future<int> recordFinished() async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getInt(_key) ?? 0;
    await prefs.setInt(_key, before + 1);
    return before;
  }
}

final math.Random _random = math.Random();

/// The export's interstitial, between a finished export and its result, by
/// [exportGetsInterstitial] — and, as every interstitial, only one already
/// loaded and due ([AdService.afterWork]). Never throws: an ad must never
/// cost an export its result.
Future<void> showExportAd(bool Function() wanted) async {
  if (!AdService.isOn(AdPlacement.export)) return;
  try {
    final before = await ExportHistory.recordFinished();
    if (!exportGetsInterstitial(
      exportsBefore: before,
      roll: _random.nextDouble(),
    )) {
      return;
    }
    await AdService.afterWork(AdPlacement.export, wanted: wanted);
  } catch (e) {
    debugPrint('Export ad: $e');
  }
}
