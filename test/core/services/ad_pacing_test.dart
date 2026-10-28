import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/ad_pacing.dart';

/// How often an interstitial may show: the owner's gaps, one per placement
/// (video compression every four minutes at most, Privacy Strip every six),
/// and never two ads within a minute of each other whatever showed them.
void main() {
  late DateTime now;
  AdPacing pacing() => AdPacing(clock: () => now);

  setUp(() => now = DateTime(2026, 10, 28, 12));

  void wait(Duration d) => now = now.add(d);

  test('the first ad of a placement is due', () {
    final p = pacing();
    expect(p.isDue(AdPlacement.videoCompression), isTrue);
    expect(p.isDue(AdPlacement.privacyStrip), isTrue);
  });

  test('after a compression ad, none for four minutes', () {
    final p = pacing()..shown(AdPlacement.videoCompression);
    wait(const Duration(minutes: 3, seconds: 59));
    expect(p.isDue(AdPlacement.videoCompression), isFalse);
    wait(const Duration(seconds: 1));
    expect(p.isDue(AdPlacement.videoCompression), isTrue);
  });

  test('after a Privacy Strip ad, none for six minutes', () {
    final p = pacing()..shown(AdPlacement.privacyStrip);
    wait(const Duration(minutes: 5, seconds: 59));
    expect(p.isDue(AdPlacement.privacyStrip), isFalse);
    wait(const Duration(seconds: 1));
    expect(p.isDue(AdPlacement.privacyStrip), isTrue);
  });

  test('each placement keeps its own gap, but no ad comes within a minute '
      'of another', () {
    final p = pacing()..shown(AdPlacement.videoCompression);
    wait(const Duration(seconds: 59));
    expect(p.isDue(AdPlacement.privacyStrip), isFalse);
    wait(const Duration(seconds: 1));
    expect(p.isDue(AdPlacement.privacyStrip), isTrue);
    expect(p.isDue(AdPlacement.videoCompression), isFalse);
  });

  test('a rewarded ad holds the interstitials for a minute too', () {
    final p = pacing()..otherAdShown();
    wait(const Duration(seconds: 59));
    expect(p.isDue(AdPlacement.videoCompression), isFalse);
    wait(const Duration(seconds: 1));
    expect(p.isDue(AdPlacement.videoCompression), isTrue);
  });
}
