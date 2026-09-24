import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A reopened draft whose rendered files are gone says so and stops pointing
/// at them, rather than handing the engine paths to nothing.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  DraftProject draftWith(
    List<VideoSegment> segments, {
    List<Map<String, dynamic>> textOverlays = const [],
  }) =>
      DraftProject(
        id: 'd1',
        sourceVideoPath: '/v.mp4',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        durationSeconds: 30,
        assets: [asset.toJson()],
        segments: [for (final s in segments) s.toJson()],
        textOverlays: textOverlays,
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

  test('a draft with stacked overlays opens with them on separate lanes',
      () async {
    // Duplicates used to land exactly on top of their original, and drafts
    // saved then still hold the stack. Opening one separates it.
    final text = TextOverlayModel(
      id: 't',
      text: 'hi',
      startTime: const Duration(seconds: 1),
      endTime: const Duration(seconds: 4),
    );
    final draft = draftWith(
      [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)],
      textOverlays: [text.toJson(), text.copyWith(id: 't2').toJson()],
    );
    final n = VideoEditorNotifier(VideoEditorService());
    await n.loadDraft(draft, rerenderMissingProxies: false);

    final lanes = n.state.textOverlays.map((t) => t.laneIndex).toList();
    expect(lanes, [0, 1]);
  });

  test('a missing playback proxy is dropped and the user is told once', () async {
    final n = VideoEditorNotifier(VideoEditorService());
    await n.loadDraft(
      draftWith([
        VideoSegment(
          id: 'a',
          assetId: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          overrideVideoPath: '/definitely/not/here.mp4',
        ),
      ]),
      rerenderMissingProxies: false,
    );

    expect(n.state.segments.single.overrideVideoPath, isNull);
    final notice = n.takeLoadNotice();
    expect(notice, isNotNull);
    expect(notice, contains('cached'));
    // Taken once.
    expect(n.takeLoadNotice(), isNull);
  });

  test('a reversed clip keeps its reversal and loses only the dead proxy',
      () async {
    final n = VideoEditorNotifier(VideoEditorService());
    await n.loadDraft(
      draftWith([
        VideoSegment(
          id: 'a',
          assetId: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          isReversed: true,
          overrideVideoPath: '/gone.mp4',
        ),
      ]),
      rerenderMissingProxies: false,
    );
    final s = n.state.segments.single;
    expect(s.isReversed, isTrue);
    expect(s.overrideVideoPath, isNull);
    expect(n.takeLoadNotice(), isNotNull);
  });

  test('a draft whose files are all present says nothing', () async {
    final n = VideoEditorNotifier(VideoEditorService());
    await n.loadDraft(
      draftWith([VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 5)]),
      rerenderMissingProxies: false,
    );
    expect(n.takeLoadNotice(), isNull);
  });
}
