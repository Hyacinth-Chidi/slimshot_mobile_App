import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Captions made from Home keep no draft and nothing in Recent Edits — the
/// owner's call — until ✎ makes them an ordinary editor project.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );

  test('a project that keeps no draft writes none, and writes once it does',
      () async {
    SharedPreferences.setMockInitialValues({});
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        draftId: 'd1',
        assets: const [asset],
        segments: [
          VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5),
        ],
      );

    n.setSavesDraft(false);
    await n.saveDraft();
    expect(await DraftService.getDraftById('d1'), isNull);

    n.setSavesDraft(true);
    await n.saveDraft();
    expect(await DraftService.getDraftById('d1'), isNotNull);
  });
}
