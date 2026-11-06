import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';

const _portraitCamera = MediaAsset(
  id: 'cam',
  path: '/camera/VID_1.mp4',
  type: MediaAssetType.video,
  durationSeconds: 12,
  width: 1080,
  height: 1920,
  hasAudio: true,
);

MediaAsset _video({double width = 1920, double height = 1080, double seconds = 60}) => MediaAsset(
      id: 'video',
      path: '/picked/clip.mp4',
      type: MediaAssetType.video,
      durationSeconds: seconds,
      width: width,
      height: height,
      hasAudio: true,
    );

ReactionTake _take({
  ReactionLayout layout = ReactionLayout.topBottom,
  ReactionWindow window = ReactionWindow.initial,
  MediaAsset? video,
  List<ReactionPiece>? pieces,
  bool videoSoundInCamera = true,
  int? removedAtMs,
}) =>
    ReactionTake(
      id: 't1',
      layout: layout,
      window: window,
      camera: _portraitCamera,
      video: video ?? _video(),
      pieces: pieces ?? const [ReactionPiece(startMs: 0, endMs: 12000, offsetMs: 0)],
      videoSoundInCamera: videoSoundInCamera,
      removedAtMs: removedAtMs,
    );

/// Where a composed clip lands on the canvas, in canvas fractions — the
/// engine's own arithmetic (`LaneFit.of` times the pinch scale, about the
/// centre moved by the pan).
Rect _clipOnCanvas(EditorTimelineVideoClip clip, {double canvasAspect = 9 / 16}) {
  final content = clip.sourceWidth / clip.sourceHeight * clip.contentRect.width / clip.contentRect.height;
  final fit = content > canvasAspect ? Size(1, canvasAspect / content) : Size(content / canvasAspect, 1);
  final scale = clip.canvasScale.baseValue;
  return Rect.fromCenter(
    center: Offset(0.5 + clip.canvasOffsetX.baseValue, 0.5 + clip.canvasOffsetY.baseValue),
    width: fit.width * scale,
    height: fit.height * scale,
  );
}

/// What an overlay shows on the canvas, in canvas fractions: its quad —
/// `OverlayRenderer.writeCorners`' contain fit in the box, times the scale —
/// cut down by a rectangle mask.
Rect _overlayOnCanvas(EditorTimelineOverlay overlay, double contentAspect) {
  final fitW = contentAspect >= 1 ? 1.0 : contentAspect;
  final fitH = contentAspect >= 1 ? 1 / contentAspect : 1.0;
  var width = overlay.boxWidth * fitW * overlay.scale.baseValue;
  var height = overlay.boxHeight * fitH * overlay.scale.baseValue;
  var centerX = overlay.centerX.baseValue;
  var centerY = overlay.centerY.baseValue;
  final mask = overlay.mask;
  if (!mask.isNone) {
    expect(mask.shape, ClipMaskShape.rectangle);
    centerX += (mask.centerX - 0.5) * width;
    centerY += (mask.centerY - 0.5) * height;
    width *= mask.width;
    height *= mask.height;
  }
  return Rect.fromCenter(center: Offset(centerX, centerY), width: width, height: height);
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, moreOrLessEquals(expected.left, epsilon: 1e-6), reason: 'left of $actual');
  expect(actual.top, moreOrLessEquals(expected.top, epsilon: 1e-6), reason: 'top of $actual');
  expect(actual.width, moreOrLessEquals(expected.width, epsilon: 1e-6), reason: 'width of $actual');
  expect(actual.height, moreOrLessEquals(expected.height, epsilon: 1e-6), reason: 'height of $actual');
}

EditorTimeline _compose(ReactionTake take) =>
    const VideoEditorTimelineComposer().compose(reactionProject(take), previewCanvasSize: kReactionFrame);

void main() {
  group('places', () {
    test('top / bottom: the video above, you below, each half the frame', () {
      final places = reactionPlaces(layout: ReactionLayout.topBottom, window: ReactionWindow.initial, videoAspect: 16 / 9);
      _expectRect(places.video, const Rect.fromLTWH(0, 0, 1, 0.5));
      _expectRect(places.camera, const Rect.fromLTWH(0, 0.5, 1, 0.5));
    });

    test('side by side: the video left, you right, each the full height', () {
      final places = reactionPlaces(layout: ReactionLayout.sideBySide, window: ReactionWindow.initial, videoAspect: 16 / 9);
      _expectRect(places.video, const Rect.fromLTWH(0, 0, 0.5, 1));
      _expectRect(places.camera, const Rect.fromLTWH(0.5, 0, 0.5, 1));
    });

    test('float: you fill the frame, the video in its window in its own shape', () {
      const window = ReactionWindow(centerX: 0.3, centerY: 0.2, width: 0.4);
      final places = reactionPlaces(layout: ReactionLayout.float, window: window, videoAspect: 16 / 9);
      _expectRect(places.camera, const Rect.fromLTWH(0, 0, 1, 1));
      // 0.4 of a 360-wide frame is 144px; a 16:9 picture that wide is 81px
      // tall, of 640.
      _expectRect(places.video, Rect.fromCenter(center: const Offset(0.3, 0.2), width: 0.4, height: 81 / 640));
    });
  });

  group('the float window', () {
    test('stays inside the frame however far it is dragged', () {
      const window = ReactionWindow(centerX: -2, centerY: 5, width: 0.4);
      final fitted = window.fittedFor(16 / 9);
      expect(fitted.centerX, moreOrLessEquals(0.2));
      expect(fitted.centerY, moreOrLessEquals(1 - 81 / 640 / 2));
    });

    test('is never smaller than the least nor taller than the frame', () {
      expect(const ReactionWindow(centerX: 0.5, centerY: 0.5, width: 0.01).fittedFor(16 / 9).width,
          kMinReactionWindowWidth);
      // A 9:16 video's window reaches the frame's full height at full width;
      // a taller video stops where its height does.
      expect(const ReactionWindow(centerX: 0.5, centerY: 0.5, width: 3).fittedFor(9 / 16).width, 1);
      final tall = const ReactionWindow(centerX: 0.5, centerY: 0.5, width: 3).fittedFor(9 / 21);
      expect(tall.width * (360 / 640) / (9 / 21), moreOrLessEquals(1));
    });

    test('survives a round trip, and an unreadable one is the first', () {
      const window = ReactionWindow(centerX: 0.6, centerY: 0.7, width: 0.35);
      expect(ReactionWindow.fromJson(window.toJson()), window);
      expect(ReactionWindow.fromJson('junk'), ReactionWindow.initial);
    });
  });

  group('cover crop', () {
    test('a portrait picture in a wide half keeps its middle band', () {
      _expectRect(coverCrop(contentAspect: 9 / 16, regionAspect: 9 / 8), const Rect.fromLTWH(0, 0.25, 1, 0.5));
    });

    test('a wide picture in a wide half loses its sides', () {
      final crop = coverCrop(contentAspect: 16 / 9, regionAspect: 9 / 8);
      expect(crop.width, moreOrLessEquals((9 / 8) / (16 / 9)));
      expect(crop.center.dx, moreOrLessEquals(0.5));
      expect(crop.height, 1);
    });

    test('a picture already the region\'s shape is whole', () {
      expect(coverCrop(contentAspect: 9 / 16, regionAspect: 9 / 16), const Rect.fromLTWH(0, 0, 1, 1));
    });
  });

  group('the project', () {
    for (final layout in [ReactionLayout.topBottom, ReactionLayout.sideBySide]) {
      for (final video in [_video(), _video(width: 1080, height: 1920), _video(width: 1080, height: 1080)]) {
        test('${layout.name}: each picture fills exactly its half (video ${video.width}x${video.height})', () {
          final take = _take(layout: layout, video: video);
          final places = reactionPlaces(layout: layout, window: take.window, videoAspect: video.aspectRatio);
          final timeline = _compose(take);
          _expectRect(_clipOnCanvas(timeline.videoClips.single), places.camera);
          _expectRect(_overlayOnCanvas(timeline.overlays.single, video.aspectRatio), places.video);
        });
      }
    }

    test('float: you fill the frame and the video is its window, uncut', () {
      const window = ReactionWindow(centerX: 0.7, centerY: 0.25, width: 0.45);
      final take = _take(layout: ReactionLayout.float, window: window);
      final timeline = _compose(take);
      _expectRect(_clipOnCanvas(timeline.videoClips.single), const Rect.fromLTWH(0, 0, 1, 1));
      final overlay = timeline.overlays.single;
      expect(overlay.mask.isNone, isTrue);
      _expectRect(
        _overlayOnCanvas(overlay, 16 / 9),
        reactionPlaces(layout: ReactionLayout.float, window: window, videoAspect: 16 / 9).video,
      );
    });

    test('your take is the main clip, the video an overlay placed for the reaction frame', () {
      final state = reactionProject(_take());
      expect(state.assets.single.path, _portraitCamera.path);
      expect(state.segments.single.assetId, _portraitCamera.id);
      expect(state.videoOverlays.single.videoPath, '/picked/clip.mp4');
      expect(state.videoOverlays.single.referenceCanvasSize, kReactionFrame);
      expect(state.draftId, 'react_t1');
      expect(state.durationSeconds, 12);
    });

    test('the video plays alongside you for the whole take', () {
      final state = reactionProject(_take(pieces: const [ReactionPiece(startMs: 0, endMs: 12000, offsetMs: 4000)]));
      final overlay = state.videoOverlays.single;
      expect(overlay.timelineStart, Duration.zero);
      expect(overlay.timelineEnd, const Duration(seconds: 12));
      expect(overlay.sourceStart, 4);
      expect(overlay.sourceEnd, 16);
    });

    test('a video that started late trims your take to start with it', () {
      // Recording time 0 was the video's -0.15s: it had not started yet.
      final state = reactionProject(_take(pieces: const [ReactionPiece(startMs: 0, endMs: 12000, offsetMs: -150)]));
      final clip = state.segments.single;
      expect(clip.sourceStart, moreOrLessEquals(0.15));
      final overlay = state.videoOverlays.single;
      expect(overlay.timelineStart, Duration.zero);
      expect(overlay.sourceStart, 0);
      expect(overlay.timelineEnd.inMilliseconds, 11850);
    });

    test('a pause that moved the video against you becomes a second piece', () {
      final state = reactionProject(_take(pieces: const [
        ReactionPiece(startMs: 0, endMs: 5000, offsetMs: 0),
        ReactionPiece(startMs: 5000, endMs: 12000, offsetMs: 300),
      ]));
      final pieces = state.videoOverlays;
      expect(pieces, hasLength(2));
      expect(pieces[0].timelineEnd, const Duration(seconds: 5));
      expect(pieces[0].sourceEnd, 5);
      expect(pieces[1].timelineStart, const Duration(seconds: 5));
      expect(pieces[1].sourceStart, moreOrLessEquals(5.3));
      expect(pieces.map((p) => p.laneIndex).toSet(), {0}, reason: 'one lane: one video');
      expect(pieces.map((p) => p.id).toSet(), hasLength(2));
    });

    test('the take ends where the video does', () {
      // The take stops a moment after the video's last frame; that moment
      // would be a half of nothing.
      final state = reactionProject(_take(
        video: _video(seconds: 10),
        pieces: const [ReactionPiece(startMs: 0, endMs: 12000, offsetMs: 0)],
      ));
      expect(state.videoOverlays.single.sourceEnd, 10);
      expect(state.videoOverlays.single.timelineEnd, const Duration(seconds: 10));
      expect(state.segments.single.sourceEnd, 10);
    });

    test('the video\'s sound is kept clean only where the microphone did not hear it', () {
      expect(reactionProject(_take(videoSoundInCamera: true)).videoOverlays.single.isMuted, isTrue);
      expect(reactionProject(_take(videoSoundInCamera: false)).videoOverlays.single.isMuted, isFalse);
    });

    test('a photo reacted to is a photo overlay filling its place for the whole take', () {
      const photo = MediaAsset(
        id: 'photo',
        path: '/picked/meme.jpg',
        type: MediaAssetType.image,
        durationSeconds: 0,
        width: 1080,
        height: 1350,
        hasAudio: false,
      );
      for (final layout in ReactionLayout.values) {
        final take = _take(
          layout: layout,
          video: photo,
          pieces: const [ReactionPiece(startMs: 0, endMs: 12000, offsetMs: -150)],
        );
        final state = reactionProject(take);
        expect(state.videoOverlays, isEmpty);
        final overlay = state.imageOverlays.single;
        expect(overlay.imagePath, '/picked/meme.jpg');
        expect(overlay.startTime, Duration.zero);
        expect(overlay.endTime, const Duration(seconds: 12), reason: 'a photo has no end of its own');
        expect(overlay.referenceCanvasSize, kReactionFrame);
        expect(state.segments.single.sourceStart, 0, reason: 'nothing to wait for: no lead to trim');
        expect(state.segments.single.sourceEnd, 12);
        final timeline = _compose(take);
        final places = reactionPlaces(layout: layout, window: take.window, videoAspect: photo.aspectRatio);
        _expectRect(_overlayOnCanvas(timeline.overlays.single, photo.aspectRatio), places.video);
        _expectRect(_clipOnCanvas(timeline.videoClips.single), places.camera);
      }
    });

    test("a held frame is a still in the video's place for as long as it was held", () {
      for (final layout in ReactionLayout.values) {
        final take = _take(layout: layout, pieces: const [
          ReactionPiece(startMs: 0, endMs: 4000, offsetMs: 0),
          ReactionPiece.hold(startMs: 4000, endMs: 9000, atMs: 4000, stillPath: '/camera/still_1.jpg'),
          ReactionPiece(startMs: 9000, endMs: 12000, offsetMs: -5000),
        ]);
        final state = reactionProject(take);
        expect(state.videoOverlays.map((o) => (o.timelineStart, o.timelineEnd, o.sourceStart)), [
          (Duration.zero, const Duration(seconds: 4), 0.0),
          (const Duration(seconds: 9), const Duration(seconds: 12), 4.0),
        ]);
        final still = state.imageOverlays.single;
        expect(still.imagePath, '/camera/still_1.jpg');
        expect((still.startTime, still.endTime), (const Duration(seconds: 4), const Duration(seconds: 9)));
        expect(still.referenceCanvasSize, kReactionFrame);
        final places = reactionPlaces(layout: layout, window: take.window, videoAspect: take.video.aspectRatio);
        final composed = _compose(take).overlays.where((o) => o.id == still.id).single;
        _expectRect(_overlayOnCanvas(composed, take.video.aspectRatio), places.video);
      }
    });

    test('a video held at its end keeps you recording to the end of the take', () {
      final state = reactionProject(_take(pieces: const [
        ReactionPiece(startMs: 0, endMs: 5000, offsetMs: 55000),
        ReactionPiece.hold(startMs: 5000, endMs: 12000, atMs: 60000, stillPath: '/camera/still_end.jpg'),
      ]));
      expect(state.segments.single.sourceEnd, 12, reason: 'the take is not cut where the video ran out');
      expect(state.imageOverlays.single.endTime, const Duration(seconds: 12));
    });

    test('a hold whose still could not be taken shows nothing there, and fails nothing', () {
      final state = reactionProject(_take(pieces: const [
        ReactionPiece(startMs: 0, endMs: 4000, offsetMs: 0),
        ReactionPiece.hold(startMs: 4000, endMs: 12000, atMs: 4000),
      ]));
      expect(state.imageOverlays, isEmpty);
      expect(state.videoOverlays, hasLength(1));
    });

    test('the video removed: you fill the whole frame from that moment', () {
      for (final layout in ReactionLayout.values) {
        final take = _take(layout: layout, removedAtMs: 8000, pieces: const [
          ReactionPiece(startMs: 0, endMs: 5000, offsetMs: 55000),
          ReactionPiece.hold(startMs: 5000, endMs: 8000, atMs: 60000, stillPath: '/camera/still_end.jpg'),
        ]);
        final state = reactionProject(take);
        expect(state.segments.map((s) => (s.sourceStart, s.sourceEnd)), [(0.0, 8.0), (8.0, 12.0)]);
        final clips = _compose(take).videoClips;
        final places = reactionPlaces(layout: layout, window: take.window, videoAspect: take.video.aspectRatio);
        _expectRect(_clipOnCanvas(clips[0]), places.camera);
        _expectRect(_clipOnCanvas(clips[1]), const Rect.fromLTWH(0, 0, 1, 1));
        expect(state.imageOverlays.single.endTime, const Duration(seconds: 8));
      }
    });

    test('out loud the microphone already has the video, so its layer is muted', () {
      final state = reactionProject(_take());
      expect(state.videoOverlays.single.isMuted, isTrue, reason: 'unmuted it would be heard twice, a moment apart');
      expect(state.videoOverlays.single.keyframes.isEmpty, isTrue);
      expect(state.segments.single.volume.isAnimated, isFalse);
    });

    test('with headphones the video keeps its own clean sound beside your voice, both at full', () {
      final state = reactionProject(_take(videoSoundInCamera: false));
      expect(state.videoOverlays.single.isMuted, isFalse);
      expect(state.videoOverlays.single.keyframes.isEmpty, isTrue);
      expect(state.segments.single.volume.isAnimated, isFalse);
    });

    test('a take saved while the video was lowered under talking opens with no volume curves', () {
      final saved = {
        ..._take().toJson(),
        'speech': [
          [4000, 6000],
        ],
      };
      final state = reactionProject(ReactionTake.fromJson(saved)!);
      expect(state.videoOverlays.single.isMuted, isTrue);
      expect(state.videoOverlays.single.keyframes.isEmpty, isTrue);
      expect(state.segments.single.volume.isAnimated, isFalse);
      expect(ReactionTake.fromJson(saved)!.toJson().containsKey('speech'), isFalse);
    });

    test('a take survives a round trip', () {
      final take = _take(
        layout: ReactionLayout.float,
        window: const ReactionWindow(centerX: 0.6, centerY: 0.3, width: 0.5),
        pieces: const [
          ReactionPiece(startMs: 0, endMs: 4000, offsetMs: -80),
          ReactionPiece.hold(startMs: 4000, endMs: 6000, atMs: 3920, stillPath: '/camera/still.jpg'),
          ReactionPiece(startMs: 6000, endMs: 12000, offsetMs: 140),
        ],
        videoSoundInCamera: false,
        removedAtMs: 11000,
      );
      final back = ReactionTake.fromJson(take.toJson())!;
      expect(back.toJson(), take.toJson());
      expect(ReactionTake.fromJson({'layout': 'float'}), isNull);
    });
  });

  group('sync', () {
    test('one run is one piece at the offset measured through it', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..sample(recordingMs: 300, videoMs: 180)
        ..sample(recordingMs: 600, videoMs: 481)
        ..sample(recordingMs: 900, videoMs: 779)
        ..endRun(recordingMs: 1000);
      expect(log.pieces(), const [ReactionPiece(startMs: 0, endMs: 1000, offsetMs: -120)]);
    });

    test('one sample far off the others does not move the offset', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..sample(recordingMs: 300, videoMs: 200)
        ..sample(recordingMs: 600, videoMs: 500)
        ..sample(recordingMs: 900, videoMs: 1400)
        ..endRun(recordingMs: 1000);
      expect(log.pieces().single.offsetMs, -100);
    });

    test('a run too short to measure keeps where it began', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 2000)
        ..endRun(recordingMs: 150);
      expect(log.pieces(), const [ReactionPiece(startMs: 0, endMs: 150, offsetMs: 2000)]);
    });

    test('runs that agree after a pause stay one piece', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..sample(recordingMs: 500, videoMs: 400)
        ..endRun(recordingMs: 2000)
        ..beginRun(recordingMs: 2000, videoMs: 1900)
        ..sample(recordingMs: 2500, videoMs: 2420)
        ..endRun(recordingMs: 3000);
      expect(log.pieces(), const [ReactionPiece(startMs: 0, endMs: 3000, offsetMs: -100)]);
    });

    test('a pause that slipped the video starts a new piece where the run began', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..sample(recordingMs: 500, videoMs: 400)
        ..endRun(recordingMs: 2000)
        ..beginRun(recordingMs: 2000, videoMs: 1900)
        ..sample(recordingMs: 2500, videoMs: 2600)
        ..endRun(recordingMs: 3000);
      expect(log.pieces(), const [
        ReactionPiece(startMs: 0, endMs: 2000, offsetMs: -100),
        ReactionPiece(startMs: 2000, endMs: 3000, offsetMs: 100),
      ]);
    });

    test('a hold keeps the frame the video stopped on until it plays again', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..endRun(recordingMs: 2000)
        ..beginHold(recordingMs: 2000, videoMs: 1980)
        ..endHold(recordingMs: 3000)
        ..beginRun(recordingMs: 3000, videoMs: 1980)
        ..endRun(recordingMs: 5000);
      expect(log.pieces(), const [
        ReactionPiece(startMs: 0, endMs: 2000, offsetMs: 0),
        ReactionPiece.hold(startMs: 2000, endMs: 3000, atMs: 1980),
        ReactionPiece(startMs: 3000, endMs: 5000, offsetMs: -1020),
      ]);
    });

    test('runs either side of a hold stay apart, even a hold too short to slip them', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..endRun(recordingMs: 2000)
        ..beginHold(recordingMs: 2000, videoMs: 2000)
        ..endHold(recordingMs: 2010)
        ..beginRun(recordingMs: 2010, videoMs: 2000)
        ..endRun(recordingMs: 4000);
      expect(log.pieces(), hasLength(3));
      expect(log.pieces()[2], const ReactionPiece(startMs: 2010, endMs: 4000, offsetMs: -10));
    });

    test('a hold still open when the take ends closes with it', () {
      final log = ReactionSyncLog()
        ..beginRun(recordingMs: 0, videoMs: 0)
        ..endRun(recordingMs: 2000)
        ..beginHold(recordingMs: 2000, videoMs: 2000);
      expect(log.isHolding, isTrue);
      log.endHold(recordingMs: 7000);
      expect(log.pieces().last, const ReactionPiece.hold(startMs: 2000, endMs: 7000, atMs: 2000));
    });

    test('nothing recorded is no pieces', () {
      expect(ReactionSyncLog().pieces(), isEmpty);
    });
  });

  group('sound', () {
    test('the microphone hears the video only from the speaker, out loud', () {
      expect(videoSoundReachesMicrophone(headphones: false, videoSoundOn: true), isTrue);
      expect(videoSoundReachesMicrophone(headphones: true, videoSoundOn: true), isFalse);
      expect(videoSoundReachesMicrophone(headphones: false, videoSoundOn: false), isFalse);
    });
  });
}
