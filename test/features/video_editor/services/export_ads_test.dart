import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/video_editor/services/export_ads.dart';

/// The export's interstitial (the owner's calls, 2026-10-29): never on a
/// user's first three exports after installing the app, then not on every
/// export — by chance, about half. Resolution plays no part: no export size
/// is unlocked by an ad any more.
void main() {
  test("a user's first three exports never end with an ad", () {
    expect(kExportsWithoutAds, 3);
    for (var before = 0; before < 3; before++) {
      expect(exportGetsInterstitial(exportsBefore: before, roll: 0), isFalse,
          reason: 'export ${before + 1}');
    }
  });

  test('from the fourth, an export ends with one by chance, about half', () {
    expect(kExportAdChance, 0.5);
    expect(exportGetsInterstitial(exportsBefore: 3, roll: 0.49), isTrue);
    expect(exportGetsInterstitial(exportsBefore: 3, roll: 0.5), isFalse);
    expect(exportGetsInterstitial(exportsBefore: 40, roll: 0.2), isTrue);
  });

  group('finished exports are counted on the phone', () {
    test('from none, each answering how many finished before it', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ExportHistory.recordFinished(), 0);
      expect(await ExportHistory.recordFinished(), 1);
      expect(await ExportHistory.recordFinished(), 2);
    });

    // In the app's preferences, so it lasts while the app is installed and
    // starts again from none after a fresh install.
    test('and the count lasts beyond a launch', () async {
      SharedPreferences.setMockInitialValues({'exportsFinished': 4});
      expect(await ExportHistory.recordFinished(), 4);
    });
  });
}
