import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/privacy/logic/photo_metadata.dart';

void main() {
  group('PhotoMetadata.fromMap', () {
    test('reads what the native reader sends', () {
      final m = PhotoMetadata.fromMap({
        'latitude': 6.5244,
        'longitude': 3.3792,
        'make': 'INFINIX',
        'model': 'Infinix X6833',
        'dateTaken': '2026:10:07 14:02:33',
        'artist': 'Ada',
      });
      expect((m.hasLocation, m.hasCamera, m.hasTaken, m.hasAuthor),
          (true, true, true, true));
      expect(m.camera, 'Infinix X6833');
      expect(m.taken, DateTime(2026, 10, 7, 14, 2, 33));
      expect(m.isEmpty, isFalse);
    });

    test('nothing, blanks and junk read as nothing found', () {
      expect(PhotoMetadata.fromMap(const {}).isEmpty, isTrue);
      final m = PhotoMetadata.fromMap({
        'latitude': 'x',
        'make': '  ',
        'dateTaken': '0000:00:00 00:00:00',
        'artist': '',
      });
      expect(m.isEmpty, isTrue);
    });

    test('a location of exactly 0,0 is what an empty GPS block reads as', () {
      expect(
          PhotoMetadata.fromMap({'latitude': 0.0, 'longitude': 0.0}).hasLocation,
          isFalse);
    });
  });

  test('the camera name does not repeat its brand', () {
    expect(cameraName('Google', 'Pixel 8'), 'Google Pixel 8');
    expect(cameraName('INFINIX', 'Infinix X6833'), 'Infinix X6833');
    expect(cameraName(null, 'iPhone 15'), 'iPhone 15');
    expect(cameraName('Canon', null), 'Canon');
    expect(cameraName(' ', ''), isNull);
  });

  test('coordinates read with their hemispheres', () {
    expect(formatCoordinates(6.5244, 3.3712), '6.52° N, 3.37° E');
    expect(formatCoordinates(-33.8688, -151.2093), '33.87° S, 151.21° W');
  });

  test('a date reads the way a person says it', () {
    expect(formatTaken(DateTime(2026, 10, 7, 14, 2)), '7 Oct 2026, 14:02');
    expect(formatTaken(DateTime(2025, 1, 31, 9, 5)), '31 Jan 2025, 09:05');
  });

  test('several photos read as a count', () {
    expect(foundInLabel(3, 5), 'In 3 of 5');
  });

  group('MetadataSummary', () {
    const located = PhotoMetadata(latitude: 1, longitude: 2, camera: 'X');
    const plain = PhotoMetadata(camera: 'X');

    test('counts each kind across the photos, unread ones included', () {
      final s = MetadataSummary.of([located, plain, null, located]);
      expect((s.location, s.camera, s.taken, s.author, s.total), (2, 3, 0, 0, 4));
      expect(s.isEmpty, isFalse);
    });

    test('nothing personal anywhere', () {
      expect(MetadataSummary.of(const [PhotoMetadata(), null]).isEmpty, isTrue);
    });
  });
}
