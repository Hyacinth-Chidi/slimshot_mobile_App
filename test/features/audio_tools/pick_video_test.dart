import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/features/audio_tools/pick_video.dart';

/// Extract's gallery pick: a path, nothing, or one line saying why not —
/// never an error nothing catches.
void main() {
  test('a picked video gives its path', () async {
    final path = await pickVideoPath(
      () async => XFile('/cache/v.mp4'),
      onError: (_) => fail('nothing went wrong'),
    );
    expect(path, '/cache/v.mp4');
  });

  test('nothing picked is null and says nothing', () async {
    String? said;
    final path = await pickVideoPath(() async => null, onError: (m) => said = m);
    expect(path, isNull);
    expect(said, isNull);
  });

  test('refused access says how to allow it', () async {
    String? said;
    final path = await pickVideoPath(
      () async => throw PlatformException(code: 'photo_access_denied'),
      onError: (m) => said = m,
    );
    expect(path, isNull);
    expect(said, kVideoAccessMessage);
  });

  test('any other failure says the videos could not be opened', () async {
    String? said;
    final path = await pickVideoPath(
      () async => throw Exception('picker crashed'),
      onError: (m) => said = m,
    );
    expect(path, isNull);
    expect(said, kVideoPickFailedMessage);
  });
}
