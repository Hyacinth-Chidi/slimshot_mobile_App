import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_atlases.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_preview_layout.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// An effect tile's atlas is asked of the engine over the preview channel,
/// and the engine's three answers — bytes, null, busy — map onto the cache's
/// three results, so a busy engine is retried and a real failure is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  Object? Function()? answer;

  setUp(() {
    calls.clear();
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('slimshot_ai/native_timeline_preview'),
      (call) async {
        calls.add(call);
        return answer?.call();
      },
    );
  });

  final vignette = videoEffectById('vignette')!;

  test('bytes map to EffectPreviewAtlas', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    answer = () => bytes;
    final result = await NativeTimelinePreviewService()
        .renderEffectPreview(effectPreviewSampleBar(vignette));
    expect(result, isA<EffectPreviewAtlas>());
    expect((result as EffectPreviewAtlas).bytes, bytes);
  });

  test('null maps to EffectPreviewFailed', () async {
    answer = () => null;
    final result = await NativeTimelinePreviewService()
        .renderEffectPreview(effectPreviewSampleBar(vignette));
    expect(result, isA<EffectPreviewFailed>());
  });

  test('busy maps to EffectPreviewBusy', () async {
    answer = () => throw PlatformException(code: 'busy');
    final result = await NativeTimelinePreviewService()
        .renderEffectPreview(effectPreviewSampleBar(vignette));
    expect(result, isA<EffectPreviewBusy>());
  });

  test('another PlatformException maps to EffectPreviewFailed', () async {
    answer = () => throw PlatformException(code: 'error');
    final result = await NativeTimelinePreviewService()
        .renderEffectPreview(effectPreviewSampleBar(vignette));
    expect(result, isA<EffectPreviewFailed>());
  });

  test('MissingPluginException maps to EffectPreviewBusy', () async {
    answer = () => throw MissingPluginException();
    final result = await NativeTimelinePreviewService()
        .renderEffectPreview(effectPreviewSampleBar(vignette));
    expect(result, isA<EffectPreviewBusy>());
  });

  test('the request carries the sample bar and the atlas spec', () async {
    answer = () => Uint8List.fromList([1]);
    await NativeTimelinePreviewService()
        .renderEffectPreview(effectPreviewSampleBar(vignette));
    expect(calls.single.method, 'renderEffectPreview');
    expect(calls.single.arguments, {
      'effect': effectPreviewSampleBar(vignette).toJson(),
      'cellWidth': kEffectPreviewCellWidth,
      'cellHeight': kEffectPreviewCellHeight,
      'columns': kEffectPreviewColumns,
      'frames': kEffectPreviewFrames,
      'fps': kEffectPreviewFps,
    });
  });
}
