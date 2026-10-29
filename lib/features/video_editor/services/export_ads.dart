import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/ad_service.dart';

/// What plays between a finished export and its result, given the export's
/// height and whether anyone is still waiting for it: [showExportAd] in the
/// app, a stand-in in a test.
typedef ExportAd = Future<void> Function(
    int targetHeight, bool Function() wanted);

/// The share of exports that end with an interstitial — not every export
/// (the owner's call, 2026-10-29).
const double kExportAdChance = 0.5;

/// Whether a finished export ends with an interstitial: never a user's
/// first export, never a 4K one — its ad was the unlock — and otherwise by
/// chance, [roll] being a draw from 0 up to 1.
bool exportGetsInterstitial({
  required int exportsBefore,
  required bool is4K,
  required double roll,
}) =>
    exportsBefore > 0 && !is4K && roll < kExportAdChance;

/// How many exports have finished on this phone: what tells a user's first
/// export from the rest. Kept in preferences, so it outlasts a launch.
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
Future<void> showExportAd(int targetHeight, bool Function() wanted) async {
  if (!AdService.isOn(AdPlacement.export)) return;
  try {
    final before = await ExportHistory.recordFinished();
    if (!exportGetsInterstitial(
      exportsBefore: before,
      is4K: targetHeight >= 2160,
      roll: _random.nextDouble(),
    )) {
      return;
    }
    await AdService.afterWork(AdPlacement.export, wanted: wanted);
  } catch (e) {
    debugPrint('Export ad: $e');
  }
}
