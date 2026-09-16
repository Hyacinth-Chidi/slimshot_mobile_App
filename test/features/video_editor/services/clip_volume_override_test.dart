import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// The live volume channel: the slider is audible while it is dragged.
///
/// Device-reported as a gap: the clip volume slider wrote `previewVolume` in
/// state and the engine heard nothing until the ✓ committed it, so the user
/// set a level they could not hear. Shaped like `setClipTransform`: a
/// lightweight override the engine applies per tick and clears on the next
/// `setTimeline`, which carries the committed value.
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

  test('a dragged volume reaches the engine with the clip it belongs to',
      () async {
    await NativeTimelinePreviewService().setClipVolume(clipId: 'clip_a', volume: 0.35);
    final call = calls.single;
    expect(call.method, 'setClipVolume');
    expect(call.arguments, {'clipId': 'clip_a', 'volume': 0.35});
  });

  test('discarding the drag lifts the override rather than leaving it', () async {
    // ✕ clears the preview value in state without pushing a timeline, so the
    // engine would otherwise keep the dragged level until the next edit.
    await NativeTimelinePreviewService().clearClipVolume(clipId: 'clip_a');
    final call = calls.single;
    expect(call.method, 'clearClipVolume');
    expect(call.arguments, {'clipId': 'clip_a'});
  });
}
