import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/logic/react_live.dart';

/// A camera that does what it is told and remembers it.
class FakeCamera implements CameraBackend {
  final calls = <String>[];
  final _events = StreamController<CameraEvent>.broadcast();
  CameraLens? openedLens;
  CameraMode? openedMode;
  bool failOpen = false;
  CameraMode? refuseMode;
  Completer<void>? photoGate;
  bool hasFlash = true;
  bool canFlip = true;
  String? recordedPath;
  int recordedMs = 0;
  bool? lastAudio;

  /// Whether the last photo or recording was asked to go to the gallery.
  bool? lastGallery;

  /// Android 10 and older: saving to the gallery needs storage access.
  bool galleryNeedsPermission = false;

  /// The phone's sound is going to headphones.
  bool headphones = false;

  /// The gallery will not take a finished video.
  bool refusePublish = false;

  /// What [publishVideo] was handed.
  final published = <String>[];

  /// REACT recorded live: what the encoder says, what was asked of the recorder.
  /// None by default: REACT is today's way unless a test gives the phone more.
  ReactLiveFacts liveFacts = ReactLiveFacts.none;
  ReactLiveTake? lastReactLive;
  int? lastLiveShortSide;
  final scenes = <ReactionScene>[];
  final playback = <bool>[];
  final sound = <bool>[];
  bool refuseSource = false;
  int recordedFrames = 0;
  int recordedMissedFrames = 0;

  CameraInfo _info(CameraLens lens, CameraMode mode) => CameraInfo(
        textureId: 7,
        lens: lens,
        mode: mode,
        hasFlash: lens == CameraLens.back && hasFlash,
        minZoom: 1,
        maxZoom: 8,
        canFlip: canFlip,
        previewWidth: 1920,
        previewHeight: 1080,
        rotation: 90,
        mirrored: lens == CameraLens.front,
        galleryNeedsPermission: galleryNeedsPermission,
      );

  @override
  Stream<CameraEvent> get events => _events.stream;

  void emit(CameraEvent event) => _events.add(event);

  @override
  Future<CameraInfo> open({
    required CameraLens lens,
    required CameraMode mode,
    required CameraFlash flash,
    int? liveShortSide,
  }) async {
    calls.add('open ${lens.name} ${mode.name}${liveShortSide == null ? '' : ' live$liveShortSide'}');
    if (failOpen) throw const CameraFailure('The camera is in use.');
    openedLens = lens;
    openedMode = mode;
    return _info(lens, mode);
  }

  @override
  Future<CameraInfo> configure({
    required CameraLens lens,
    required CameraMode mode,
    required CameraFlash flash,
    int? liveShortSide,
  }) async {
    calls.add('configure ${lens.name} ${mode.name} ${flash.name}${liveShortSide == null ? '' : ' live$liveShortSide'}');
    lastLiveShortSide = liveShortSide;
    if (mode == refuseMode) throw const CameraFailure('Video is not available.');
    return _info(lens, mode);
  }

  @override
  Future<void> setFlash(CameraFlash flash) async => calls.add('flash ${flash.name}');

  @override
  Future<void> setZoom(double ratio) async => calls.add('zoom $ratio');

  @override
  Future<void> focus(Offset point) async => calls.add('focus ${point.dx} ${point.dy}');

  @override
  Future<SavedShot> takePhoto(String path, {required bool gallery}) async {
    calls.add('photo $path');
    lastGallery = gallery;
    await photoGate?.future;
    return SavedShot(path: path, uri: gallery ? 'content://media/$path' : null);
  }

  @override
  Future<void> startRecording(
    String path, {
    required bool audio,
    required bool gallery,
    ReactLiveTake? reactLive,
  }) async {
    calls.add('record $path');
    lastAudio = audio;
    lastGallery = gallery;
    lastReactLive = reactLive;
    recordedPath = path;
  }

  @override
  Future<ReactLiveFacts> reactLiveFacts() async => liveFacts;

  @override
  Future<void> reactSource(String path, {required bool photo}) async {
    calls.add('source $path ${photo ? 'photo' : 'video'}');
    if (refuseSource) throw const CameraFailure("This can't be opened.");
  }

  @override
  Future<void> reactClearSource() async => calls.add('clear source');

  /// As the phone: a scene sent before REACT is bound live has no recorder to
  /// go to, and is lost.
  @override
  Future<void> reactScene(ReactionScene scene) async {
    if (lastLiveShortSide == null) return;
    scenes.add(scene);
  }

  @override
  Future<void> reactPlayback({required bool playing}) async => playback.add(playing);

  @override
  Future<void> reactSound({required bool on}) async => sound.add(on);

  @override
  Future<void> pauseRecording() async => calls.add('pause');

  @override
  Future<void> resumeRecording() async => calls.add('resume');

  @override
  Future<RecordedVideo?> stopRecording() async {
    calls.add('stop');
    final path = recordedPath;
    recordedPath = null;
    return path == null || recordedMs == 0
        ? null
        : RecordedVideo(
            path: path,
            uri: lastGallery == true ? 'content://media/$path' : null,
            durationMs: recordedMs,
            frames: recordedFrames,
            missedFrames: recordedMissedFrames,
          );
  }

  @override
  Future<bool> headphonesConnected() async => headphones;

  @override
  Future<SavedShot?> publishVideo(String path) async {
    calls.add('publish $path');
    published.add(path);
    if (refusePublish) return null;
    final name = path.split('/').last;
    return SavedShot(path: '/gallery/SlimShot_$name', uri: 'content://media/video/$name');
  }

  @override
  Future<void> close() async => calls.add('close');
}
