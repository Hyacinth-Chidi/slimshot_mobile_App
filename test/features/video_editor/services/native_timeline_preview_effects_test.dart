import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/services/effect_bars_sync.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// Effect bars reach the preview on their own light channel, re-sent only
/// when the bars change — never on a position event — and during gestures,
/// so a dragged bar moves on the canvas while the finger is down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('slimshot_ai/native_timeline_preview'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  const bars = [
    EffectBarModel(id: 'b', effectId: 'blur', start: 1, end: 4),
    EffectBarModel(id: 'v', effectId: 'vignette', start: 0, end: 2, laneIndex: 1),
  ];
  const state = VideoEditorState(effectBars: bars);

  test('the payload is the composer\'s bars', () {
    final payload = NativeTimelinePreviewService().effectPayload(state);
    expect(payload, [
      for (final e in const VideoEditorTimelineComposer().composeEffects(state))
        e.toJson(),
    ]);
  });

  test('it is sent as setEffects', () async {
    final service = NativeTimelinePreviewService();
    await service.sendEffectPayload(service.effectPayload(state));
    expect(calls.single.method, 'setEffects');
    expect((calls.single.arguments as Map)['effects'], hasLength(2));
  });

  group('only a change of bars is sent', () {
    late EffectBarsSync sync;
    List<Map<String, dynamic>> compose(VideoEditorState s) =>
        NativeTimelinePreviewService().effectPayload(s);

    setUp(() => sync = EffectBarsSync());

    test('the first bars go out', () {
      expect(sync.payloadFor(state, compose), isNotNull);
    });

    test('a position event does not re-send', () {
      sync.payloadFor(state, compose);
      final moved = state.copyWith(currentPlaybackPosition: 3);
      expect(sync.payloadFor(moved, compose), isNull);
    });

    test('an equal list rebuilt by an edit elsewhere does not re-send', () {
      sync.payloadFor(state, compose);
      final rebuilt = state.copyWith(effectBars: [...bars]);
      expect(sync.payloadFor(rebuilt, compose), isNull);
    });

    test('a bar dragged re-sends, frame by frame', () {
      sync.payloadFor(state, compose);
      final dragged = state.copyWith(effectBars: [
        bars.first.copyWith(start: 1.5, end: 4.5),
        bars.last,
      ]);
      expect(sync.payloadFor(dragged, compose), isNotNull);
      final further = state.copyWith(effectBars: [
        bars.first.copyWith(start: 2, end: 5),
        bars.last,
      ]);
      expect(sync.payloadFor(further, compose), isNotNull);
    });

    test('after a failed send it sends again', () {
      sync.payloadFor(state, compose);
      sync.reset();
      expect(sync.payloadFor(state, compose), isNotNull);
    });
  });

  test('the screen sends bars wherever it sends overlays, gestures included', () {
    final screen = File('lib/screens/video_editor_screen.dart').readAsStringSync();
    final overlays = 'await _syncNativeOverlays('.allMatches(screen).length +
        'unawaited(_syncNativeOverlays('.allMatches(screen).length;
    final effects = 'await _syncNativeEffects('.allMatches(screen).length +
        'unawaited(_syncNativeEffects('.allMatches(screen).length;
    expect(effects, overlays);
  });
}
