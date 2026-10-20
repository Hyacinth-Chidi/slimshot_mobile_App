import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/audio_tools/audio_tools_service.dart';

/// The Dart half of Extract's native calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('slimshot_ai/audio_tools');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('no sound is null', () async {
    answer((_) async => {'hasSound': false});
    final sound = await AudioToolsService()
        .extract(videoPath: '/v.mp4', outputPath: '/d/a.m4a');
    expect(sound, isNull);
    expect(calls.single.method, 'extract');
    expect(calls.single.arguments, {'videoPath': '/v.mp4', 'outputPath': '/d/a.m4a'});
  });

  test('a sound comes back with its length in seconds', () async {
    answer((_) async => {
          'hasSound': true,
          'path': '/d/a.m4a',
          'durationMs': 1500,
          'remuxed': true,
        });
    final sound = await AudioToolsService()
        .extract(videoPath: '/v.mp4', outputPath: '/d/a.m4a');
    expect(sound!.path, '/d/a.m4a');
    expect(sound.durationSeconds, 1.5);
  });

  test('a channel error becomes AudioToolsException', () async {
    answer((_) async => throw PlatformException(
          code: 'extract_failed',
          message: 'This video could not be opened.',
        ));
    await expectLater(
      AudioToolsService().extract(videoPath: '/v.mp4', outputPath: '/d/a.m4a'),
      throwsA(isA<AudioToolsException>().having(
        (e) => e.message,
        'message',
        'This video could not be opened.',
      )),
    );
  });

  test('peaks are returned as doubles', () async {
    answer((_) async => [0, 0.5, 1]);
    final peaks = await AudioToolsService().peaks('/d/a.m4a', count: 3);
    expect(peaks, [0.0, 0.5, 1.0]);
    expect(calls.single.arguments, {'path': '/d/a.m4a', 'count': 3});
  });
}
