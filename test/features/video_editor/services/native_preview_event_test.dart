import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// What the engine's events carry for the drawn playhead.
void main() {
  test('a position says whether the picture is moving', () {
    final moving = NativeTimelinePreviewEvent.fromPlatformEvent(
      {'type': 'position', 'positionSeconds': 1.5, 'advancing': true},
    );
    expect(moving.positionSeconds, 1.5);
    expect(moving.advancing, isTrue);

    final stalled = NativeTimelinePreviewEvent.fromPlatformEvent(
      {'type': 'position', 'positionSeconds': 1.5, 'advancing': false},
    );
    expect(stalled.advancing, isFalse);
  });

  test('a position that does not say is not moving', () {
    // Holding still between reports is the old behaviour, and safe; running
    // on is not.
    final silent = NativeTimelinePreviewEvent.fromPlatformEvent(
      {'type': 'position', 'positionSeconds': 1.5},
    );
    expect(silent.advancing, isFalse);
  });

  test('a pause says where the engine stopped', () {
    final paused = NativeTimelinePreviewEvent.fromPlatformEvent(
      {'type': 'paused', 'isReady': true, 'positionSeconds': 4.25},
    );
    expect(paused.type, 'paused');
    expect(paused.positionSeconds, 4.25);
  });
}
