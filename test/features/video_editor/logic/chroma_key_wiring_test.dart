import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/chroma/chroma_key.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A chroma key reaches the engine the way the mask does: on the clip, through
/// the composer, as two vec4s.
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

  const key = ChromaKey(
    enabled: true,
    keyR: 0,
    keyG: 1,
    keyB: 0,
    similarity: 0.45,
    smoothness: 0.2,
    spill: 0.6,
  );

  VideoSegment clip(String id, {ChromaKey chroma = ChromaKey.none}) =>
      VideoSegment(
        id: id,
        assetId: 'a',
        sourceStart: 0,
        sourceEnd: 5,
        chromaKey: chroma,
      );

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
          {String? selected}) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          assets: const [asset],
          segments: segments,
          selectedSegmentId: selected,
          isClipSelected: selected != null,
        );

  test('the segment carries the key and writes it only when on', () {
    expect(clip('a').chromaKey, ChromaKey.none);
    expect(clip('a').toJson().containsKey('chromaKey'), isFalse);

    final keyed = clip('a', chroma: key);
    expect(keyed.toJson()['chromaKey'], key.toJson());
    expect(VideoSegment.fromJson(keyed.toJson()).chromaKey, key);
  });

  test('the composed clip carries it onto the wire', () {
    final timeline = const VideoEditorTimelineComposer().compose(
      VideoEditorState(assets: const [asset], segments: [clip('a', chroma: key)]),
    );
    final wire = timeline.videoClips.single;
    expect(wire.chromaKey, key);
    expect(wire.toJson()['chromaKey'], key.toJson());
  });

  test('an unkeyed clip sends no chroma field at all', () {
    final timeline = const VideoEditorTimelineComposer().compose(
      VideoEditorState(assets: const [asset], segments: [clip('a')]),
    );
    expect(timeline.videoClips.single.toJson().containsKey('chromaKey'), isFalse);
  });

  test('two differently keyed clips are not merged into one media item', () {
    final timeline = const VideoEditorTimelineComposer().compose(
      VideoEditorState(
        assets: const [asset],
        segments: [
          clip('a', chroma: key),
          VideoSegment(id: 'b', assetId: 'a', sourceStart: 5, sourceEnd: 10),
        ],
      ),
    );
    expect(timeline.playbackClips.length, 2);
  });

  test('setClipChromaKey writes the selected clip, undoably', () {
    final n = notifierWith([clip('a'), clip('b')], selected: 'a');
    n.setClipChromaKey(key);
    expect(n.state.segments[0].chromaKey, key);
    expect(n.state.segments[1].chromaKey, ChromaKey.none);
    n.undo();
    expect(n.state.segments[0].chromaKey, ChromaKey.none);
  });

  test('a live write takes no undo step of its own', () {
    final n = notifierWith([clip('a')], selected: 'a');
    n.beginClipChromaKey();
    n.setClipChromaKey(key, live: true);
    n.setClipChromaKey(key.copyWith(similarity: 0.6), live: true);
    expect(n.state.segments.single.chromaKey.similarity, 0.6);
    n.undo();
    expect(n.state.segments.single.chromaKey, ChromaKey.none);
  });

  test('a split carries the key to both halves', () {
    final n = notifierWith(
      [VideoSegment(id: 'a', assetId: 'a', sourceStart: 0, sourceEnd: 10, chromaKey: key)],
      selected: 'a',
    );
    n.splitAtPosition(5);
    expect(n.state.segments, hasLength(2));
    expect(n.state.segments[0].chromaKey, key);
    expect(n.state.segments[1].chromaKey, key);
  });
}
