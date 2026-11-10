import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/logic/background_blur.dart';
import 'package:slimshotai/features/video_editor/logic/project_draft.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// How blurred the "Blur" background is (the owner's ask, 2026-11-10: "the
/// blur is okay but it's so clear that it looks like a mirror, so a slider to
/// control how clear or blurry it will be").
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const asset = MediaAsset(
    id: 'v',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 5,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  VideoEditorNotifier notifier() => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      draftId: 'd1',
      assets: const [asset],
      segments: [VideoSegment(id: 'a', assetId: 'v', sourceStart: 0, sourceEnd: 5)],
      backgroundType: EditorBackgroundType.blur,
    );

  test('a project starts halfway along the slider', () {
    expect(kDefaultBackgroundBlurStrength, 0.5);
    expect(const VideoEditorState().backgroundBlurStrength, kDefaultBackgroundBlurStrength);
  });

  test('a drag is one undo step', () {
    final n = notifier();
    n.beginBackgroundBlurEdit();
    for (final value in [0.6, 0.7, 0.9]) {
      n.setBackgroundBlurStrength(value);
    }
    expect(n.state.backgroundBlurStrength, 0.9);
    n.undo();
    expect(n.state.backgroundBlurStrength, kDefaultBackgroundBlurStrength);
    expect(n.state.canUndo, isFalse);
  });

  test('a strength off the slider is held to its ends', () {
    final n = notifier();
    n.setBackgroundBlurStrength(-2);
    expect(n.state.backgroundBlurStrength, 0);
    n.setBackgroundBlurStrength(3);
    expect(n.state.backgroundBlurStrength, 1);
    n.setBackgroundBlurStrength(double.nan);
    expect(n.state.backgroundBlurStrength, kDefaultBackgroundBlurStrength);
  });

  test('the strength reaches the engine', () {
    final n = notifier()..setBackgroundBlurStrength(0.8);
    final canvas =
        const VideoEditorTimelineComposer().compose(n.state).toJson()['canvas'] as Map;
    expect(canvas['backgroundBlurStrength'], 0.8);
    // The old field, a value nothing read, is gone from the wire.
    expect(canvas.containsKey('backgroundBlurIntensity'), isFalse);

    final service = NativeTimelinePreviewService();
    final before = service.playbackSignature(n.state);
    n.setBackgroundBlurStrength(0.2);
    expect(service.playbackSignature(n.state), isNot(before));
  });

  group('the draft', () {
    test('a project at the default writes no strength', () {
      final json = draftProjectFrom(notifier().state)!.toJson();
      expect(json.containsKey('backgroundBlurStrength'), isFalse);
      expect(json.containsKey('backgroundBlurIntensity'), isFalse);
    });

    test('a chosen strength comes back', () async {
      final saved = draftProjectFrom(notifier().state.copyWith(backgroundBlurStrength: 0.85))!;
      final reopened = VideoEditorNotifier(VideoEditorService());
      await reopened.loadDraft(
        DraftProject.fromJson(saved.toJson()),
        rerenderMissingProxies: false,
      );
      expect(reopened.state.backgroundBlurStrength, 0.85);
    });

    test('a draft from before the slider opens at the default', () async {
      // It carried `backgroundBlurIntensity: 20`, a value from the old
      // export that nothing read and no control ever set.
      final json = draftProjectFrom(notifier().state)!.toJson()
        ..['backgroundBlurIntensity'] = 20.0;
      final reopened = VideoEditorNotifier(VideoEditorService());
      await reopened.loadDraft(DraftProject.fromJson(json), rerenderMissingProxies: false);
      expect(reopened.state.backgroundBlurStrength, kDefaultBackgroundBlurStrength);
    });

    test('a strength out of range is held to the slider on reading', () async {
      final json = draftProjectFrom(notifier().state)!.toJson()
        ..['backgroundBlurStrength'] = 4.0;
      final reopened = VideoEditorNotifier(VideoEditorService());
      await reopened.loadDraft(DraftProject.fromJson(json), rerenderMissingProxies: false);
      expect(reopened.state.backgroundBlurStrength, 1);
    });
  });
}
