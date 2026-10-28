import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A draft keeps the edit's own length — what the home screen widget shows —
/// beside `durationSeconds`, which is only the first imported file's.
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

  DraftProject draft({double? editedSeconds}) => DraftProject(
        id: 'd1',
        sourceVideoPath: '/v.mp4',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        durationSeconds: 30,
        editedSeconds: editedSeconds,
        assets: [asset.toJson()],
        segments: [
          VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)
              .toJson(),
        ],
        textOverlays: const [],
        imageOverlays: const [],
        videoOverlays: const [],
        audioTracks: const [],
        selectedRatioName: 'ratio9x16',
        customCropRect: const [0, 0, 1, 1],
        videoScale: 1,
        videoPanX: 0,
        videoPanY: 0,
        filterIntensity: 1,
        backgroundType: 'black',
        backgroundColorValue: 0xFF000000,
        backgroundBlurIntensity: 20,
        isMuted: false,
      );

  test('the edit length survives a round trip', () {
    expect(
      DraftProject.fromJson(draft(editedSeconds: 42.5).toJson()).editedSeconds,
      42.5,
    );
  });

  test('a draft without a length writes no key and loads without one', () {
    expect(draft().toJson().containsKey('editedSeconds'), isFalse);
    expect(DraftProject.fromJson(draft().toJson()).editedSeconds, isNull);
  });

  test("saving stores the project's own length, music past the clips included",
      () async {
    SharedPreferences.setMockInitialValues({});
    final n = VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        draftId: 'd1',
        assets: const [asset],
        segments: [
          VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5),
        ],
        audioTracks: const [
          AudioTrackModel(
            id: 'm',
            filePath: '/m.mp3',
            sourceDuration: 5,
            sourceStart: 0,
            sourceEnd: 5,
            timelineStart: 3,
          ),
        ],
      );
    await n.saveDraft();
    expect(
      (await DraftService.getDraftById('d1'))!.editedSeconds,
      closeTo(8.0, 1e-9),
    );
  });
}
