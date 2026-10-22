import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// The Dart half of the caption audio pass, and the export's wait for fonts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('slimshot_ai/native_timeline_preview');
  const events = EventChannel('test/caption_audio_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Future<Object?> Function(MethodCall call)? answer;

  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 10,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );
  final state = VideoEditorState(
    assets: const [asset],
    segments: [
      VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5),
    ],
  );
  const rendered = {
    'outputPath': '/tmp/c.m4a',
    'durationSeconds': 4.5,
    'hasSound': true,
  };

  setUp(() {
    calls.clear();
    answer = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer?.call(call);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('asks for exactly the chosen sounds, into the given file', () async {
    answer = (_) async => rendered;
    final service = NativeTimelinePreviewService(playbackEventChannel: events);
    for (final source in CaptionSource.values) {
      calls.clear();
      await service.renderCaptionAudio(
        state,
        outputPath: '/tmp/c.m4a',
        source: source,
      );
      final call = calls.single;
      expect(call.method, 'renderCaptionAudio');
      final args = call.arguments as Map;
      expect(args['outputPath'], '/tmp/c.m4a');
      expect(args['include'], source.include);
      expect(args['timeline'], isA<Map>());
    }
  });

  test('reads what the pass produced', () async {
    answer = (_) async => rendered;
    final result = await NativeTimelinePreviewService(
      playbackEventChannel: events,
    ).renderCaptionAudio(
      state,
      outputPath: '/tmp/c.m4a',
      source: CaptionSource.video,
    );
    expect(result.outputPath, '/tmp/c.m4a');
    expect(result.durationSeconds, 4.5);
    expect(result.hasSound, isTrue);
  });

  test('a render stopped natively is CaptionAudioCancelled', () async {
    answer = (_) async =>
        throw PlatformException(code: 'caption_audio_cancelled');
    await expectLater(
      NativeTimelinePreviewService(playbackEventChannel: events)
          .renderCaptionAudio(
        state,
        outputPath: '/tmp/c.m4a',
        source: CaptionSource.video,
      ),
      throwsA(isA<CaptionAudioCancelled>()),
    );
  });

  test('progress events reach the caller; other events do not', () async {
    final seen = <double>[];
    final progressed = Completer<void>();
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          sink.success({'type': 'position', 'positionSeconds': 1.0});
          sink.success({'type': 'captionAudioProgress', 'progress': 0.5});
        },
      ),
    );
    answer = (_) async {
      await progressed.future;
      return rendered;
    };
    await NativeTimelinePreviewService(playbackEventChannel: events)
        .renderCaptionAudio(
      state,
      outputPath: '/tmp/c.m4a',
      source: CaptionSource.video,
      onProgress: (p) {
        seen.add(p);
        if (!progressed.isCompleted) progressed.complete();
      },
    );
    expect(seen, [0.5]);
  });

  test('Cancel reaches the engine', () async {
    await NativeTimelinePreviewService().cancelCaptionAudio();
    expect(calls.single.method, 'cancelCaptionAudio');
  });

  group('a font is never a reason an export fails', () {
    const exported = {
      'outputPath': '/tmp/o.mp4',
      'durationSeconds': 5.0,
      'frameCount': 150,
      'degradedTransitions': 0,
    };

    test('a registration that throws still exports', () async {
      answer = (_) async => exported;
      final warnings = <String>[];
      final result = await NativeTimelinePreviewService(
        registerFonts: (_) async => throw Exception('Failed to load font'),
      ).exportVideo(state, outputPath: '/tmp/o.mp4', onWarning: warnings.add);
      expect(result.outputPath, '/tmp/o.mp4');
      expect(calls.single.method, 'exportVideo');
      expect(warnings, isEmpty);
    });
  });
}
