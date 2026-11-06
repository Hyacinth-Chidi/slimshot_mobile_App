import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter/foundation.dart';

import '../../video_editor/logic/animation/animatable_double.dart';
import '../../video_editor/logic/mask/clip_mask.dart';
import '../../video_editor/logic/overlay_box_fit.dart';
import '../../video_editor/models/image_overlay_model.dart';
import '../../video_editor/models/media_asset.dart';
import '../../video_editor/models/video_editor_state.dart';
import '../../video_editor/models/video_overlay_model.dart';
import '../../video_editor/models/video_segment.dart';

/// How REACT puts you and the video in one frame.
///
/// The two splits share the frame between the pictures, each filling its
/// half; the float gives you the whole frame and the video a window over it
/// the user moves and sizes. The video takes the first place of a split (the
/// top, the left) — what is being reacted to reads first.
enum ReactionLayout { topBottom, sideBySide, float }

/// The frame a reaction is laid out in and rendered from: 9:16, the editor's
/// own canvas shape, in the reference pixels its overlay is placed in.
///
/// The editor keeps an overlay's place in the pixels of the canvas it was
/// placed on, so the project carries this size with its overlay
/// (`VideoOverlayModel.referenceCanvasSize`) and the editor converts once it
/// knows its own canvas.
const Size kReactionFrame = Size(360, 640);

/// The float window is never narrower than this share of the frame: smaller,
/// the video stops being something to react to.
const double kMinReactionWindowWidth = 0.25;

/// How far apart two stretches of a take may run against the video before
/// they are kept as two pieces — about a frame.
const int kReactionSyncToleranceMs = 40;

/// The width over the height, in pixels, of [region] — fractions of the
/// reaction frame.
double reactionRegionAspect(Rect region) =>
    (region.width * kReactionFrame.width) / (region.height * kReactionFrame.height);

/// The float layout's window: its centre, and its width as a share of the
/// frame's width. Its height follows the video's own shape, so the video
/// shows whole in it.
@immutable
class ReactionWindow {
  const ReactionWindow({required this.centerX, required this.centerY, required this.width});

  /// Top left, out of the way of a face in the middle of the frame.
  static const initial = ReactionWindow(centerX: 0.27, centerY: 0.2, width: 0.42);

  final double centerX;
  final double centerY;
  final double width;

  /// The window's height as a share of the frame's, for a video of [videoAspect].
  double heightFor(double videoAspect) =>
      width * kReactionFrame.width / kReactionFrame.height / _aspect(videoAspect);

  /// This window held inside the frame: no narrower than
  /// [kMinReactionWindowWidth], no taller than the frame, and its edges on it.
  ReactionWindow fittedFor(double videoAspect) {
    final aspect = _aspect(videoAspect);
    final widest = math.min(1.0, aspect * kReactionFrame.height / kReactionFrame.width);
    final w = width.isFinite ? width.clamp(math.min(kMinReactionWindowWidth, widest), widest).toDouble() : widest;
    final h = w * kReactionFrame.width / kReactionFrame.height / aspect;
    double hold(double value, double half) => value.isFinite ? value.clamp(half, 1 - half).toDouble() : 0.5;
    return ReactionWindow(centerX: hold(centerX, w / 2), centerY: hold(centerY, h / 2), width: w);
  }

  ReactionWindow copyWith({double? centerX, double? centerY, double? width}) => ReactionWindow(
        centerX: centerX ?? this.centerX,
        centerY: centerY ?? this.centerY,
        width: width ?? this.width,
      );

  Map<String, Object?> toJson() => {'x': centerX, 'y': centerY, 'w': width};

  /// [initial] for anything it cannot read.
  static ReactionWindow fromJson(Object? raw) {
    if (raw is! Map) return initial;
    final x = raw['x'];
    final y = raw['y'];
    final w = raw['w'];
    if (x is! num || y is! num || w is! num) return initial;
    return ReactionWindow(centerX: x.toDouble(), centerY: y.toDouble(), width: w.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is ReactionWindow && other.centerX == centerX && other.centerY == centerY && other.width == width;

  @override
  int get hashCode => Object.hash(centerX, centerY, width);

  @override
  String toString() => 'ReactionWindow($centerX, $centerY, $width)';
}

double _aspect(double value) => value.isFinite && value > 0 ? value : 16 / 9;

/// Where each picture goes, as fractions of the reaction frame.
@immutable
class ReactionPlaces {
  const ReactionPlaces({required this.camera, required this.video});

  final Rect camera;
  final Rect video;
}

/// The one definition of a layout, read by the live frame on the camera
/// screen and by the project the reaction is rendered from — so what was
/// recorded against is what the file shows.
ReactionPlaces reactionPlaces({
  required ReactionLayout layout,
  required ReactionWindow window,
  required double videoAspect,
}) {
  switch (layout) {
    case ReactionLayout.topBottom:
      return const ReactionPlaces(video: Rect.fromLTWH(0, 0, 1, 0.5), camera: Rect.fromLTWH(0, 0.5, 1, 0.5));
    case ReactionLayout.sideBySide:
      return const ReactionPlaces(video: Rect.fromLTWH(0, 0, 0.5, 1), camera: Rect.fromLTWH(0.5, 0, 0.5, 1));
    case ReactionLayout.float:
      final fitted = window.fittedFor(videoAspect);
      return ReactionPlaces(
        camera: const Rect.fromLTWH(0, 0, 1, 1),
        video: Rect.fromCenter(
          center: Offset(fitted.centerX, fitted.centerY),
          width: fitted.width,
          height: fitted.heightFor(videoAspect),
        ),
      );
  }
}

/// The part of a picture of [contentAspect] that fills a region of
/// [regionAspect] edge to edge — its middle, as fractions of the picture.
Rect coverCrop({required double contentAspect, required double regionAspect}) {
  const whole = Rect.fromLTWH(0, 0, 1, 1);
  if (!(contentAspect > 0) || !(regionAspect > 0) || !contentAspect.isFinite || !regionAspect.isFinite) {
    return whole;
  }
  if ((contentAspect - regionAspect).abs() < 1e-9) return whole;
  if (contentAspect > regionAspect) {
    final width = regionAspect / contentAspect;
    return Rect.fromLTWH((1 - width) / 2, 0, width, 1);
  }
  final height = contentAspect / regionAspect;
  return Rect.fromLTWH(0, (1 - height) / 2, 1, height);
}

/// Whether the microphone records the video's sound along with the voice: it
/// does when the video plays out of the phone's speaker. Then the project
/// keeps the video's own sound off, or it would be heard twice, a moment
/// apart.
bool videoSoundReachesMicrophone({required bool headphones, required bool videoSoundOn}) =>
    videoSoundOn && !headphones;

/// A stretch of the take: from [startMs] to [endMs] of the recording, either
/// the video running at the recording's time plus [offsetMs], or — a hold —
/// the video stopped on its frame at [holdAtMs] (paused by a tap, or at its
/// end) while you went on recording. A hold is drawn as a still of that
/// frame ([stillPath], taken when the reaction is made).
@immutable
class ReactionPiece {
  const ReactionPiece({required this.startMs, required this.endMs, required this.offsetMs})
      : holdAtMs = null,
        stillPath = null;

  const ReactionPiece.hold({required this.startMs, required this.endMs, required int atMs, this.stillPath})
      : offsetMs = 0,
        holdAtMs = atMs;

  final int startMs;
  final int endMs;
  final int offsetMs;

  /// The video's time of the frame held, for a hold; null while it plays.
  final int? holdAtMs;

  /// The held frame as a picture, once taken.
  final String? stillPath;

  bool get isHold => holdAtMs != null;

  ReactionPiece withStill(String? path) =>
      isHold ? ReactionPiece.hold(startMs: startMs, endMs: endMs, atMs: holdAtMs!, stillPath: path) : this;

  Map<String, Object?> toJson() => {
        's': startMs,
        'e': endMs,
        'o': offsetMs,
        if (holdAtMs != null) 'h': holdAtMs,
        if (stillPath != null) 'p': stillPath,
      };

  static ReactionPiece? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = raw['s'];
    final e = raw['e'];
    final o = raw['o'];
    final h = raw['h'];
    final path = raw['p'];
    if (s is! num || e is! num) return null;
    if (h is num) {
      return ReactionPiece.hold(
        startMs: s.toInt(),
        endMs: e.toInt(),
        atMs: h.toInt(),
        stillPath: path is String ? path : null,
      );
    }
    if (o is! num) return null;
    return ReactionPiece(startMs: s.toInt(), endMs: e.toInt(), offsetMs: o.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is ReactionPiece &&
      other.startMs == startMs &&
      other.endMs == endMs &&
      other.offsetMs == offsetMs &&
      other.holdAtMs == holdAtMs &&
      other.stillPath == stillPath;

  @override
  int get hashCode => Object.hash(startMs, endMs, offsetMs, holdAtMs, stillPath);

  @override
  String toString() =>
      isHold ? 'ReactionPiece.hold($startMs..$endMs, at $holdAtMs)' : 'ReactionPiece($startMs..$endMs, $offsetMs)';
}

/// How the video ran against the recording through a take.
///
/// The camera and the video player are two clocks. Starting, pausing and
/// resuming them together still leaves each a little early or late, so the
/// log measures instead of assuming: each stretch between a start or resume
/// and a pause or stop is a run, sampled for the video's time against the
/// recording's, and its offset is the median sample — one late answer from
/// the player cannot move it. A run that agrees with the piece before it
/// joins that piece; one that slipped starts its own, so the reaction lines
/// up with the video across every pause. A hold — the video stopped while
/// the recording went on — is a piece of its own, and no run joins across
/// one.
class ReactionSyncLog {
  final List<Object> _entries = [];
  _Run? _open;
  _Hold? _hold;

  /// A run starts. Until the first sample, the video is taken to be where it
  /// was asked to start from.
  void beginRun({required int recordingMs, required int videoMs}) {
    _open = _Run(recordingMs, videoMs - recordingMs);
  }

  /// The video's time and the recording's at one instant, both running.
  void sample({required int recordingMs, required int videoMs}) {
    _open?.samples.add(videoMs - recordingMs);
  }

  void endRun({required int recordingMs}) {
    final run = _open;
    _open = null;
    if (run == null || recordingMs <= run.startMs) return;
    run.endMs = recordingMs;
    _entries.add(run);
  }

  bool get isRunning => _open != null;

  /// The open run's offset as measured so far; null with no run open.
  int? get runningOffsetMs => _open?.offsetMs;

  /// The video stops on its frame at [videoMs] while the recording goes on.
  void beginHold({required int recordingMs, required int videoMs}) {
    _hold = _Hold(recordingMs, videoMs);
  }

  void endHold({required int recordingMs}) {
    final hold = _hold;
    _hold = null;
    if (hold == null || recordingMs <= hold.startMs) return;
    hold.endMs = recordingMs;
    _entries.add(hold);
  }

  bool get isHolding => _hold != null;

  List<ReactionPiece> pieces({int toleranceMs = kReactionSyncToleranceMs}) {
    final pieces = <ReactionPiece>[];
    for (final entry in _entries) {
      if (entry is _Hold) {
        pieces.add(ReactionPiece.hold(startMs: entry.startMs, endMs: entry.endMs, atMs: entry.videoMs));
        continue;
      }
      final run = entry as _Run;
      final offset = run.offsetMs;
      final last = pieces.isEmpty ? null : pieces.last;
      if (last != null && !last.isHold && (offset - last.offsetMs).abs() <= toleranceMs) {
        pieces[pieces.length - 1] = ReactionPiece(startMs: last.startMs, endMs: run.endMs, offsetMs: last.offsetMs);
      } else {
        pieces.add(ReactionPiece(startMs: run.startMs, endMs: run.endMs, offsetMs: offset));
      }
    }
    return pieces;
  }
}

class _Run {
  _Run(this.startMs, this.guessMs);

  final int startMs;
  final int guessMs;
  final List<int> samples = [];
  int endMs = 0;

  int get offsetMs {
    if (samples.isEmpty) return guessMs;
    final sorted = [...samples]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }
}

class _Hold {
  _Hold(this.startMs, this.videoMs);

  final int startMs;
  final int videoMs;
  int endMs = 0;
}

/// One finished REACT take: what was recorded, against what, laid out how.
/// Kept with the reaction in the camera's roll, so Edit can open it later as
/// the two layers it was made from.
@immutable
class ReactionTake {
  const ReactionTake({
    required this.id,
    required this.layout,
    required this.window,
    required this.camera,
    required this.video,
    required this.pieces,
    required this.videoSoundInCamera,
    this.removedAtMs,
  });

  /// Names the project made from it.
  final String id;
  final ReactionLayout layout;
  final ReactionWindow window;

  /// The recording of you.
  final MediaAsset camera;

  /// The video reacted to.
  final MediaAsset video;

  final List<ReactionPiece> pieces;

  /// The microphone heard the video too ([videoSoundReachesMicrophone]).
  final bool videoSoundInCamera;

  /// The recording's time at which the video was taken away and you filled
  /// the whole frame; null when it stayed to the end.
  final int? removedAtMs;

  /// The files of the camera's own this take made: the recording of you and
  /// each held frame's still. Never the video reacted to.
  List<String> get cameraFiles => [
        camera.path,
        for (final piece in pieces)
          if (piece.stillPath != null) piece.stillPath!,
      ];

  Map<String, Object?> toJson() => {
        'id': id,
        'layout': layout.name,
        'window': window.toJson(),
        'camera': camera.toJson(),
        'video': video.toJson(),
        'pieces': [for (final piece in pieces) piece.toJson()],
        'micHearsVideo': videoSoundInCamera,
        if (removedAtMs != null) 'removedAt': removedAtMs,
      };

  /// Null for anything it cannot read.
  static ReactionTake? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final camera = raw['camera'];
    final video = raw['video'];
    if (id is! String || camera is! Map || video is! Map) return null;
    final MediaAsset cameraAsset;
    final MediaAsset videoAsset;
    try {
      cameraAsset = MediaAsset.fromJson(Map<String, dynamic>.from(camera));
      videoAsset = MediaAsset.fromJson(Map<String, dynamic>.from(video));
    } catch (_) {
      return null;
    }
    final layout = ReactionLayout.values.where((value) => value.name == raw['layout']).firstOrNull;
    final pieces = raw['pieces'];
    return ReactionTake(
      id: id,
      layout: layout ?? ReactionLayout.topBottom,
      window: ReactionWindow.fromJson(raw['window']),
      camera: cameraAsset,
      video: videoAsset,
      pieces: [
        if (pieces is List)
          for (final piece in pieces) ?ReactionPiece.fromJson(piece),
      ],
      videoSoundInCamera: raw['micHearsVideo'] != false,
      removedAtMs: raw['removedAt'] is num ? (raw['removedAt'] as num).toInt() : null,
    );
  }
}

/// [take] as an editor project: your recording the main clip, cropped and
/// placed into your part of the frame; the video an overlay over its part —
/// in a split, filling its half and cut to it; in the float, whole in its
/// window. Separate layers, so the layout can still change in the editor.
///
/// The overlay is placed in [kReactionFrame]'s pixels and says so; the
/// reaction is rendered with that frame as its canvas.
VideoEditorState reactionProject(ReactionTake take) {
  final camera = take.camera;
  final video = take.video;
  final places = reactionPlaces(layout: take.layout, window: take.window, videoAspect: video.aspectRatio);
  final cameraMs = (camera.durationSeconds * 1000).round();
  final pieces = take.pieces.isEmpty
      ? [ReactionPiece(startMs: 0, endMs: cameraMs, offsetMs: 0)]
      : take.pieces;
  // A photo has no clock: it is there from the take's first instant to its
  // last, with nothing to wait for and nothing to run out.
  final photo = video.isImage;

  // Recording time 0 came before the video started: the project starts when
  // the video does.
  final first = pieces.first;
  final leadMs =
      photo || first.isHold ? 0 : (-first.offsetMs).clamp(0, math.max(0, cameraMs - 1)).toInt();

  // From the video's removal on, you fill the frame and nothing is over you.
  final removedMs = take.removedAtMs;
  final contentEndMs = removedMs != null && removedMs > leadMs && removedMs < cameraMs ? removedMs : cameraMs;

  // The video's part, in the reference frame's pixels. Its quad is the video
  // contain-fitted into the overlay's square box, then scaled.
  const frame = kReactionFrame;
  final target = places.video;
  final targetWidth = target.width * frame.width;
  final targetHeight = target.height * frame.height;
  final aspect = video.aspectRatio;
  final fitW = aspect >= 1 ? 1.0 : aspect;
  final fitH = aspect >= 1 ? 1 / aspect : 1.0;
  final box = take.layout == ReactionLayout.float
      ? targetWidth / fitW
      : math.max(targetWidth / fitW, targetHeight / fitH);
  final maskWidth = targetWidth / (box * fitW);
  final maskHeight = targetHeight / (box * fitH);
  final mask = maskWidth < 1 - 1e-6 || maskHeight < 1 - 1e-6
      ? ClipMask(shape: ClipMaskShape.rectangle, width: maskWidth, height: maskHeight, feather: 0)
      : ClipMask.none;
  final position = Offset((target.center.dx - 0.5) * frame.width, (target.center.dy - 0.5) * frame.height);

  ImageOverlayModel still(String id, String path, int fromMs, int toMs) => ImageOverlayModel(
        id: id,
        imagePath: path,
        position: position,
        scale: box / kImageOverlayBoxPx,
        startTime: Duration(milliseconds: fromMs - leadMs),
        endTime: Duration(milliseconds: toMs - leadMs),
        mask: mask,
        referenceCanvasSize: kReactionFrame,
      );

  final videoMs = (video.durationSeconds * 1000).round();
  final overlays = <VideoOverlayModel>[];
  final stills = <ImageOverlayModel>[
    if (photo) still('react_photo_${take.id}', video.path, leadMs, contentEndMs),
  ];
  for (var i = 0; i < (photo ? 0 : pieces.length); i++) {
    final piece = pieces[i];
    final fromMs = math.max(piece.startMs, leadMs);
    // The last piece runs to the end of what was recorded.
    final toMs = i == pieces.length - 1 ? contentEndMs : math.min(piece.endMs, contentEndMs);
    if (toMs <= fromMs) continue;
    if (piece.isHold) {
      final path = piece.stillPath;
      if (path == null) continue;
      stills.add(still('react_still_${take.id}_$i', path, fromMs, toMs));
      continue;
    }
    final videoFromMs = fromMs + piece.offsetMs;
    if (videoFromMs >= videoMs || videoFromMs < 0) continue;
    final startMs = fromMs - leadMs;
    var endMs = toMs - leadMs;
    if (videoFromMs + (endMs - startMs) > videoMs) endMs = startMs + (videoMs - videoFromMs);
    if (endMs <= startMs) continue;
    overlays.add(VideoOverlayModel(
      id: overlays.isEmpty ? 'react_video_${take.id}' : 'react_video_${take.id}_${overlays.length}',
      videoPath: video.path,
      position: position,
      scale: box / kVideoOverlayBoxPx,
      timelineStart: Duration(milliseconds: startMs),
      timelineEnd: Duration(milliseconds: endMs),
      sourceStart: videoFromMs / 1000,
      sourceEnd: (videoFromMs + endMs - startMs) / 1000,
      isMuted: take.videoSoundInCamera,
      mask: mask,
      referenceCanvasSize: kReactionFrame,
    ));
  }

  // A take made before holds stopped a moment after the video's last frame,
  // so where the video ran out the take ends too — that moment would be a
  // half of nothing. A take with holds or a removal ran on deliberately.
  var clipEndSeconds = camera.durationSeconds;
  final last = overlays.isEmpty ? null : overlays.last;
  final ranOnPurpose = removedMs != null || pieces.any((piece) => piece.isHold);
  if (!ranOnPurpose && last != null && (last.sourceEnd * 1000).round() >= videoMs) {
    clipEndSeconds = math.min(clipEndSeconds, (leadMs + last.timelineEnd.inMilliseconds) / 1000);
  }

  final segments = [
    _cameraClip('react_camera_${take.id}', camera, places.camera, leadMs / 1000,
        math.min(clipEndSeconds, contentEndMs / 1000)),
    if (contentEndMs < cameraMs && contentEndMs / 1000 < clipEndSeconds)
      _cameraClip('react_camera_${take.id}_full', camera, const Rect.fromLTWH(0, 0, 1, 1), contentEndMs / 1000,
          clipEndSeconds),
  ];

  return VideoEditorState(
    draftId: 'react_${take.id}',
    assets: [camera],
    segments: segments,
    trimRange: RangeValues(segments.first.sourceStart, segments.first.sourceEnd),
    durationSeconds: camera.durationSeconds,
    videoOverlays: overlays,
    imageOverlays: stills,
  );
}

/// The camera's part: cropped to [region]'s shape, which then fills the
/// region exactly — the engine's contain fit spans the full width (or
/// height), and the pinch scale and pan finish the job.
VideoSegment _cameraClip(String id, MediaAsset camera, Rect region, double fromSeconds, double toSeconds) {
  final regionAspect = reactionRegionAspect(region);
  const canvasAspect = 9 / 16;
  final fitWidth = regionAspect > canvasAspect ? 1.0 : regionAspect / canvasAspect;
  return VideoSegment(
    id: id,
    assetId: camera.id,
    sourceStart: fromSeconds,
    sourceEnd: toSeconds,
    canvasScale: AnimatableDouble(baseValue: region.width / fitWidth),
    canvasOffsetX: AnimatableDouble(baseValue: region.center.dx - 0.5),
    canvasOffsetY: AnimatableDouble(baseValue: region.center.dy - 0.5),
    cropRect: coverCrop(contentAspect: camera.aspectRatio, regionAspect: regionAspect),
  );
}
