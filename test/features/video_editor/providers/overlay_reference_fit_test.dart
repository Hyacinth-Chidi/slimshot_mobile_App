import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A REACT project's overlay is placed on a fixed 9:16 frame before any
/// editor exists; the editor converts it to its own canvas once.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 10,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );

  VideoEditorNotifier notifierWith(List<VideoOverlayModel> overlays) => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      draftId: 'd1',
      assets: const [asset],
      segments: [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 10)],
      videoOverlays: overlays,
    );

  test('a reaction\'s overlay is converted to the canvas, and no undo step is taken', () {
    final n = notifierWith([
      VideoOverlayModel(id: 'react', videoPath: '/r.mp4', position: const Offset(0, -160), scale: 2,
          referenceCanvasSize: const Size(360, 640)),
      VideoOverlayModel(id: 'mine', videoPath: '/m.mp4', position: const Offset(10, 10)),
    ]);

    n.fitOverlaysToCanvas(const Size(180, 320));

    final react = n.state.videoOverlays.firstWhere((o) => o.id == 'react');
    expect(react.position, const Offset(0, -80));
    expect(react.scale, 1);
    expect(react.referenceCanvasSize, isNull);
    final mine = n.state.videoOverlays.firstWhere((o) => o.id == 'mine');
    expect(mine.position, const Offset(10, 10), reason: 'placed in this editor: already its canvas\'s');
    expect(n.state.canUndo, isFalse);
  });

  test('with nothing to convert the project is untouched', () {
    final n = notifierWith([VideoOverlayModel(id: 'mine', videoPath: '/m.mp4')]);
    final before = n.state;
    n.fitOverlaysToCanvas(const Size(180, 320));
    expect(identical(n.state, before), isTrue);
  });
}
