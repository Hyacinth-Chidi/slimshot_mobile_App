import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/sound_library/data/catalog_models.dart';

void main() {
  group('formatSoundDuration', () {
    test('a short sound reads in tenths of a second', () {
      expect(formatSoundDuration(400), '0.4s');
      expect(formatSoundDuration(4000), '4.0s');
      expect(formatSoundDuration(9940), '9.9s');
    });

    test('a value that rounds to ten seconds takes the long form', () {
      expect(formatSoundDuration(9960), '0:10');
    });

    test('a longer sound reads as minutes and seconds', () {
      expect(formatSoundDuration(12000), '0:12');
      expect(formatSoundDuration(65000), '1:05');
    });

    test('an unknown length shows nothing', () {
      expect(formatSoundDuration(0), isNull);
      expect(formatSoundDuration(-5), isNull);
    });
  });

  test('a sound survives its own json', () {
    const sound = CatalogSound(
      id: 'a',
      title: 'Whoosh',
      durationMs: 800,
      categorySlug: 'transitions',
      categoryName: 'Transitions',
      coverUrl: 'https://cdn.test/c.png',
    );
    final back = CatalogSound.tryParse(sound.toJson())!;
    expect(back.id, 'a');
    expect(back.title, 'Whoosh');
    expect(back.durationMs, 800);
    expect(back.categorySlug, 'transitions');
    expect(back.categoryName, 'Transitions');
    expect(back.coverUrl, 'https://cdn.test/c.png');
  });
}
