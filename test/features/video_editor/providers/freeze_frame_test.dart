import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/color/color_adjustments.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Freeze frame: the frame under the playhead becomes a 3-second still, cut
/// in where the playhead is.
///
/// Built from parts that already exist — a split, a photo clip, a frame
/// decoded by the same extractor the filmstrip uses — so the still plays,
/// exports and thumbnails like any imported photo. What is pinned here is the
/// arithmetic those parts are joined with: which frame, where it lands, what
/// it wears, and that it undoes as one step.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('freeze_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A frame provider that answers a fixed byte string and records what was
  /// asked for.
  final asked = <(String, int, int, int)>[];
  Future<Uint8List?> frames(String path, int ms, int w, int h) async {
    asked.add((path, ms, w, h));
    return Uint8List.fromList([9, 9, 9]);
  }

  setUp(asked.clear);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
      {required double position, List<MediaAsset> assets = const [asset]}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        draftId: 'd1',
        assets: assets,
        segments: segments,
        currentPlaybackPosition: position,
      );
  }

  Future<void> freeze(VideoEditorNotifier n) =>
      n.freezeFrameAtPlayhead(frameProvider: frames, destinationDir: tmp);

  VideoSegment clip(String id, {double start = 0, double end = 10}) =>
      VideoSegment(id: id, assetId: 'a', sourceStart: start, sourceEnd: end);

  group('mid-clip', () {
    test('cuts the clip and holds the frame between the halves', () async {
      final n = notifierWith([clip('a')], position: 4.0);
      await freeze(n);

      final s = n.state.segments;
      expect(s, hasLength(3));
      expect(s[0].sourceEnd, closeTo(4.0, 1e-9));
      expect(s[2].sourceStart, closeTo(4.0, 1e-9));

      final still = s[1];
      expect(still.duration, kDefaultPhotoDurationSeconds);
      final frameAsset = n.state.assetFor(still)!;
      expect(frameAsset.isImage, isTrue);
      expect(File(frameAsset.path).readAsBytesSync(), [9, 9, 9]);
      expect(frameAsset.path, contains('freeze_d1_'));
      // The still is what the user now has in hand.
      expect(n.state.selectedSegmentId, still.id);
    });

    test('asks for the source frame that was on screen, at source size', () async {
      // Trimmed to start at 2s and sped 2×: at 4s of timeline the clip is at
      // 2 + 4·2 = 10s of source.
      final n = notifierWith([clip('a', start: 2, end: 30).copyWith(speed: 2.0)],
          position: 4.0);
      await freeze(n);
      expect(asked.single.$1, '/v.mp4');
      expect(asked.single.$2, 10000);
      expect(asked.single.$3, 1920);
      expect(asked.single.$4, 1080);
    });

    test('caps the decode at 1920 on the long side', () async {
      const fourK = MediaAsset(
        id: 'a',
        path: '/4k.mp4',
        type: MediaAssetType.video,
        durationSeconds: 60,
        width: 3840,
        height: 2160,
        hasAudio: true,
      );
      final n = notifierWith([clip('a')], position: 4.0, assets: const [fourK]);
      await freeze(n);
      expect(asked.single.$3, 1920);
      expect(asked.single.$4, 1080);
    });

    test('the still wears the clip\'s state at that instant, flat', () async {
      final n = notifierWith(
        [
          clip('a').copyWith(
            canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
              Keyframe(progress: 0.0, value: 1.0),
              Keyframe(progress: 1.0, value: 3.0),
            ]),
            flipHorizontal: true,
            adjustments: const ColorAdjustments(temperature: 0.5),
            filterId: 'warm',
          ),
        ],
        position: 5.0, // half way: the scale keyframes read 2.0 here
      );
      await freeze(n);
      final still = n.state.segments[1];
      expect(still.canvasScale.baseValue, closeTo(2.0, 1e-9));
      expect(still.canvasScale.keyframes, isEmpty);
      expect(still.flipHorizontal, isTrue);
      expect(still.adjustments, const ColorAdjustments(temperature: 0.5));
      expect(still.filterId, 'warm');
    });

    test('is one undo step, cut and still together', () async {
      final n = notifierWith([clip('a')], position: 4.0);
      final assetsBefore = n.state.assets.length;
      await freeze(n);
      n.undo();
      expect(n.state.segments, hasLength(1));
      expect(n.state.segments.single.sourceEnd, 10.0);
      expect(n.state.assets, hasLength(assetsBefore));
    });
  });

  group('near an edge', () {
    test('too close to the start, the still goes before the clip, uncut',
        () async {
      final n = notifierWith([clip('a')], position: kMinClipDurationSeconds / 2);
      await freeze(n);
      final s = n.state.segments;
      expect(s, hasLength(2));
      expect(n.state.assetFor(s[0])!.isImage, isTrue);
      expect(s[1].id, 'a');
      expect(s[1].sourceStart, 0.0);
    });

    test('too close to the end, the still goes after the clip, uncut',
        () async {
      final n = notifierWith([clip('a')], position: 10.0 - kMinClipDurationSeconds / 2);
      await freeze(n);
      final s = n.state.segments;
      expect(s, hasLength(2));
      expect(s[0].id, 'a');
      expect(n.state.assetFor(s[1])!.isImage, isTrue);
    });
  });

  group('refusals, with the message the user sees', () {
    test('a photo has no frame to freeze', () async {
      const photo = MediaAsset(
        id: 'p',
        path: '/p.jpg',
        type: MediaAssetType.image,
        durationSeconds: 0,
        width: 1000,
        height: 1000,
        hasAudio: false,
      );
      final n = notifierWith(
        [VideoSegment(id: 's', assetId: 'p', sourceStart: 0, sourceEnd: 3)],
        position: 1.0,
        assets: const [photo],
      );
      expect(freeze(n), throwsA(isA<Exception>()));
    });

    test('no frame back means nothing changed', () async {
      final n = notifierWith([clip('a')], position: 4.0);
      await expectLater(
        n.freezeFrameAtPlayhead(
          frameProvider: (_, __, ___, ____) async => null,
          destinationDir: tmp,
        ),
        throwsA(isA<Exception>()),
      );
      expect(n.state.segments, hasLength(1));
      expect(n.state.canUndo, isFalse);
    });
  });

  test('the blade still cuts the way it always did', () {
    // The cut moved into a helper the freeze shares; the split's own behaviour
    // is pinned elsewhere, and this is the smoke check that the move kept it.
    final n = notifierWith([clip('a')], position: 4.0);
    n.splitAtPosition(4.0);
    expect(n.state.segments, hasLength(2));
    expect(n.state.selectedSegmentId, n.state.segments[1].id);
  });
}
