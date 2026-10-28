import 'package:shared_preferences/shared_preferences.dart';

/// Clears what removed features left in preferences, so it does not sit on
/// the phone for good: the compression history's list (removed 2026-10-28 —
/// its entries pointed at temporary files the app's own cleanup had already
/// deleted, so most of them could no longer be saved or shown).
Future<void> forgetRemovedFeatures(SharedPreferences prefs) async {
  await prefs.remove('optimization_history');
}
