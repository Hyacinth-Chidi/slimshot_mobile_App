import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/video_editor/services/export_ads.dart';

/// The export's interstitial (the owner's call, 2026-10-29): not on every
/// export — by chance, about half — never a user's first export, and never
/// a 4K one, whose ad was the unlock.
void main() {
  test("a user's first export never ends with an ad", () {
    expect(exportGetsInterstitial(exportsBefore: 0, is4K: false, roll: 0),
        isFalse);
  });

  test('a 4K export never does: its ad was the unlock', () {
    expect(exportGetsInterstitial(exportsBefore: 3, is4K: true, roll: 0),
        isFalse);
  });

  test('after the first, an export ends with one by chance, about half',
      () {
    expect(kExportAdChance, 0.5);
    expect(exportGetsInterstitial(exportsBefore: 1, is4K: false, roll: 0.49),
        isTrue);
    expect(exportGetsInterstitial(exportsBefore: 1, is4K: false, roll: 0.5),
        isFalse);
  });

  group('finished exports are counted on the phone', () {
    test('from none, each answering how many finished before it', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ExportHistory.recordFinished(), 0);
      expect(await ExportHistory.recordFinished(), 1);
      expect(await ExportHistory.recordFinished(), 2);
    });

    test('and the count lasts beyond a launch', () async {
      SharedPreferences.setMockInitialValues({'exportsFinished': 4});
      expect(await ExportHistory.recordFinished(), 4);
    });
  });
}
