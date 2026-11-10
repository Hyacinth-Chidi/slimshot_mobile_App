import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/preview_event_toast.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// What the editor says when the preview engine reports a problem.
///
/// Device-reported (2026-11-10): the engine's own words reached the toast —
/// a player's error name, an exception class, a file's full path. The toast
/// says what happened in plain words; the engine's words go to the log.
void main() {
  NativeTimelinePreviewEvent event(Map<String, Object?> map) =>
      NativeTimelinePreviewEvent.fromPlatformEvent(map);

  test('a missing file is said plainly, without its path', () {
    final toast = previewEventToast(event({
      'type': 'error',
      'code': 'missing_file',
      'message': 'Source video does not exist: /data/user/0/com.x/cache/a.mp4',
    }));
    expect(toast, "A clip's file is missing from this phone.");
  });

  test("a video the phone can't play is said plainly", () {
    final toast = previewEventToast(event({
      'type': 'error',
      'code': 'playback_failed',
      'message': 'MediaCodecVideoRenderer error, index=0, format=Format(…)',
    }));
    expect(toast, "This video can't play on this phone.");
  });

  test('any other engine failure is one plain line, never its message', () {
    for (final code in ['timeline_failed', 'render_failed', null, 'new_kind']) {
      final toast = previewEventToast(event({
        'type': 'error',
        'code': ?code,
        'message': 'Native preview timeline failed: NullPointerException',
      }));
      expect(toast, "The preview couldn't load.", reason: '$code');
    }
  });

  test('a preview-only fallback is logged, not toasted', () {
    // The owner's rule: a toast only when the exported file differs. A
    // transition shown as a dissolve, an overlay heard silent, a blur the GPU
    // refused — all of these are the preview's, and the export says its own.
    final toast = previewEventToast(event({
      'type': 'warning',
      'message': 'Transition lane unavailable on this device: ERROR_CODE_DECODER_INIT_FAILED',
    }));
    expect(toast, isNull);
  });

  test('ordinary events are not toasted', () {
    for (final type in ['position', 'paused', 'completed', 'textReady', 'preparing']) {
      expect(previewEventToast(event({'type': type})), isNull, reason: type);
    }
  });

  test('the error code is read from the event', () {
    expect(event({'type': 'error', 'code': 'missing_file'}).code, 'missing_file');
    expect(event({'type': 'error'}).code, isNull);
  });
}
