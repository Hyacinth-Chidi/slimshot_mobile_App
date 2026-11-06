import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'reaction.dart';
import 'reaction_sound.dart';

/// REACT recorded live: your camera and the video are drawn together straight
/// into the file as you record, and the sound mixed as it happens, so stop
/// means the reaction is finished — the way a screen recorder or a
/// dual-camera app works. Today's way, where the reaction is made from the
/// take afterwards, stays for a phone that cannot keep up.
///
/// This file holds the decisions, apart from the phone: which way a phone
/// records ([chooseReactCapture]), whether a take came out choppy, and the
/// scene the native recorder draws ([reactionScene]) — the layout rules stay
/// [reactionPlaces]'s, sent as rects, so the recorder only draws.

/// How a phone records a reaction.
enum ReactCapture {
  /// Live, at 1080x1920.
  live1080,

  /// Live, at 720x1280: the phone's 1080p is borderline, or a 1080p take
  /// came out choppy.
  live720,

  /// Today's way: your camera recorded alone, the reaction made afterwards.
  afterwards;

  /// The short side a live reaction records at; null for [afterwards].
  int? get shortSide => switch (this) {
        ReactCapture.live1080 => 1080,
        ReactCapture.live720 => 720,
        ReactCapture.afterwards => null,
      };
}

/// What the phone's video encoder says it can do, asked once: the frames a
/// second it achieves at 1080x1920 and at 720x1280, 0 where it cannot take
/// the size at all.
@immutable
class ReactLiveFacts {
  const ReactLiveFacts({required this.fps1080, required this.fps720});

  static const none = ReactLiveFacts(fps1080: 0, fps720: 0);

  final double fps1080;
  final double fps720;

  static ReactLiveFacts fromMap(Map<Object?, Object?>? map) {
    double read(Object? raw) => raw is num && raw.isFinite && raw > 0 ? raw.toDouble() : 0;
    if (map == null) return none;
    return ReactLiveFacts(fps1080: read(map['fps1080']), fps720: read(map['fps720']));
  }
}

/// Above this, a size is comfortable for live recording.
const double kReactComfortableFps = 40;

/// Below this, a size cannot be recorded live at all.
const double kReactMinimumFps = 30;

/// Which way a phone records, from what it says it can do and the step down
/// it was given before ([stepAfterChoppy]): 0 none, 1 at most 720p, 2
/// afterwards. Borderline at 1080p means 720p — choosing the smaller size
/// whenever the answer is close keeps a choppy first take rare.
ReactCapture chooseReactCapture(ReactLiveFacts facts, {int step = 0}) {
  if (step >= 2) return ReactCapture.afterwards;
  if (step <= 0 && facts.fps1080 >= kReactComfortableFps) return ReactCapture.live1080;
  if (facts.fps720 >= kReactMinimumFps) return ReactCapture.live720;
  return ReactCapture.afterwards;
}

/// A take lost too many of its camera's frames: at least ten, and at least
/// one in twenty. A few lost is normal on any phone.
bool takeWasChoppy({required int frames, required int missedFrames}) {
  final total = frames + missedFrames;
  return missedFrames >= math.max(10, total * 0.05);
}

/// The step a choppy take leaves: 1080p goes to 720p, 720p to afterwards.
int stepAfterChoppy(ReactCapture used) => used == ReactCapture.live1080 ? 1 : 2;

const kReactStepTo720Message = 'The next reaction will record at 720p.';
const kReactStepToAfterMessage = 'This phone will make reactions after recording.';
const kReactLiveFailedMessage = 'Live recording stopped on this phone. Reactions will be made after recording.';

/// One picture of the scene: where it goes ([dst]) and the part of it shown
/// ([src]), both as fractions — of the frame, and of the upright picture —
/// with y down.
@immutable
class ReactionQuad {
  const ReactionQuad({required this.dst, required this.src});

  final Rect dst;
  final Rect src;

  Map<String, Object?> toJson() => {'dst': _rect(dst), 'src': _rect(src)};

  @override
  bool operator ==(Object other) => other is ReactionQuad && other.dst == dst && other.src == src;

  @override
  int get hashCode => Object.hash(dst, src);

  @override
  String toString() => 'ReactionQuad($dst <- $src)';
}

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

/// What the live recorder draws: your camera, and the video over its place.
@immutable
class ReactionScene {
  const ReactionScene({required this.camera, this.video});

  final ReactionQuad camera;

  /// Null before anything is chosen, and once the video is taken away.
  final ReactionQuad? video;

  Map<String, Object?> toJson() => {
        'camera': camera.toJson(),
        if (video != null) 'video': video!.toJson(),
      };

  @override
  bool operator ==(Object other) => other is ReactionScene && other.camera == camera && other.video == video;

  @override
  int get hashCode => Object.hash(camera, video);
}

/// The scene for a layout, from the same rules the reaction made afterwards
/// is rendered by: each picture covers its place, the window's video whole.
/// With the video [removed], your camera fills the frame.
ReactionScene reactionScene({
  required ReactionLayout layout,
  required ReactionWindow window,
  required double cameraAspect,
  required double videoAspect,
  required bool hasVideo,
  bool removed = false,
}) {
  const whole = Rect.fromLTWH(0, 0, 1, 1);
  if (removed) {
    return ReactionScene(
      camera: ReactionQuad(dst: whole, src: coverCrop(contentAspect: cameraAspect, regionAspect: 9 / 16)),
    );
  }
  final places = reactionPlaces(layout: layout, window: window, videoAspect: videoAspect);
  final camera = ReactionQuad(
    dst: places.camera,
    src: coverCrop(contentAspect: cameraAspect, regionAspect: reactionRegionAspect(places.camera)),
  );
  if (!hasVideo) return ReactionScene(camera: camera);
  return ReactionScene(
    camera: camera,
    video: ReactionQuad(
      dst: places.video,
      src: layout == ReactionLayout.float
          ? whole
          : coverCrop(contentAspect: videoAspect, regionAspect: reactionRegionAspect(places.video)),
    ),
  );
}

/// A live take's sound: whether the video is lowered while you talk (out
/// loud, where the microphone hears it), and by how much — the numbers the
/// reaction made afterwards uses, defined once, here in Dart.
@immutable
class ReactLiveTake {
  const ReactLiveTake({
    required this.lowerVideo,
    this.duckVolume = kReactionDuckVolume,
    this.micGateVolume = kReactionMicGateVolume,
    this.rampMs = kSpeechRampMs,
  });

  final bool lowerVideo;
  final double duckVolume;
  final double micGateVolume;
  final int rampMs;

  Map<String, Object?> toJson() => {
        'lowerVideo': lowerVideo,
        'duck': duckVolume,
        'gate': micGateVolume,
        'rampMs': rampMs,
      };
}
