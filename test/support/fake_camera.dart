import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';

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
  }) async {
    calls.add('open ${lens.name} ${mode.name}');
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
  }) async {
    calls.add('configure ${lens.name} ${mode.name} ${flash.name}');
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
  Future<void> startRecording(String path, {required bool audio, required bool gallery}) async {
    calls.add('record $path');
    lastAudio = audio;
    lastGallery = gallery;
    recordedPath = path;
  }

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
