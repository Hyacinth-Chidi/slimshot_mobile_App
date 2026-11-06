import 'dart:async';

import 'package:flutter/services.dart';

import '../logic/camera_controller.dart';

/// The phone's camera over `slimshot_ai/camera` (`CameraChannel.kt`).
class MethodChannelCamera implements CameraBackend {
  MethodChannelCamera({
    MethodChannel channel = const MethodChannel('slimshot_ai/camera'),
    EventChannel eventChannel = const EventChannel('slimshot_ai/camera_events'),
  })  : _channel = channel,
        _eventChannel = eventChannel;

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  Stream<CameraEvent>? _events;

  @override
  Stream<CameraEvent> get events => _events ??= _eventChannel
      .receiveBroadcastStream()
      .map((raw) => cameraEventFrom(raw))
      .where((event) => event != null)
      .cast<CameraEvent>();

  @override
  Future<CameraInfo> open({
    required CameraLens lens,
    required CameraMode mode,
    required CameraFlash flash,
  }) =>
      _bind('open', lens, mode, flash);

  @override
  Future<CameraInfo> configure({
    required CameraLens lens,
    required CameraMode mode,
    required CameraFlash flash,
  }) =>
      _bind('configure', lens, mode, flash);

  Future<CameraInfo> _bind(String method, CameraLens lens, CameraMode mode, CameraFlash flash) async {
    final answer = await _call<Map<Object?, Object?>>(method, {
      'lens': lens.name,
      'mode': mode.name,
      'flash': flash.name,
    });
    final info = cameraInfoFrom(answer);
    if (info == null) throw const CameraFailure(kCameraUnavailableMessage);
    return info;
  }

  @override
  Future<void> setFlash(CameraFlash flash) => _call<void>('setFlash', {'mode': flash.name});

  @override
  Future<void> setZoom(double ratio) => _call<void>('setZoom', {'ratio': ratio});

  @override
  Future<void> focus(Offset point) => _call<void>('focus', {'x': point.dx, 'y': point.dy});

  @override
  Future<SavedShot> takePhoto(String path, {required bool gallery}) async {
    final answer = await _call<Map<Object?, Object?>>('takePhoto', {'path': path, 'gallery': gallery});
    final saved = answer?['path'];
    if (saved is! String || saved.isEmpty) throw const CameraFailure(kPhotoFailedMessage);
    final uri = answer?['uri'];
    return SavedShot(path: saved, uri: uri is String && uri.isNotEmpty ? uri : null);
  }

  @override
  Future<void> startRecording(String path, {required bool audio, required bool gallery}) =>
      _call<void>('startRecording', {'path': path, 'audio': audio, 'gallery': gallery});

  /// Deletes a shot from the gallery by its address; false where the phone
  /// would not.
  Future<bool> deleteShot(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('deleteShot', {'uri': uri}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> pauseRecording() => _call<void>('pauseRecording');

  @override
  Future<void> resumeRecording() => _call<void>('resumeRecording');

  @override
  Future<RecordedVideo?> stopRecording() async {
    final answer = await _call<Map<Object?, Object?>>('stopRecording');
    return recordedVideoFrom(answer);
  }

  @override
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      // Closing a camera that is already gone is nothing to report.
    } on MissingPluginException {
      // No camera channel (a test, another platform): nothing was open.
    }
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw CameraFailure(error.message ?? kCameraUnavailableMessage);
    } on MissingPluginException {
      throw const CameraFailure(kCameraUnavailableMessage);
    }
  }
}

const kCameraUnavailableMessage = 'The camera could not be opened.';
const kPhotoFailedMessage = 'The photo could not be taken.';

CameraLens _lensFrom(Object? raw) => raw == 'front' ? CameraLens.front : CameraLens.back;

CameraMode _modeFrom(Object? raw) => raw == 'video' ? CameraMode.video : CameraMode.photo;

int? _int(Object? raw) => raw is num ? raw.toInt() : null;

double? _double(Object? raw) => raw is num ? raw.toDouble() : null;

/// The camera's description from the channel, or null when it has no texture.
CameraInfo? cameraInfoFrom(Map<Object?, Object?>? map) {
  if (map == null) return null;
  final textureId = _int(map['textureId']);
  if (textureId == null) return null;
  final minZoom = _double(map['minZoom']) ?? 1;
  final maxZoom = _double(map['maxZoom']) ?? minZoom;
  return CameraInfo(
    textureId: textureId,
    lens: _lensFrom(map['lens']),
    mode: _modeFrom(map['mode']),
    hasFlash: map['hasFlash'] == true,
    minZoom: minZoom,
    maxZoom: maxZoom < minZoom ? minZoom : maxZoom,
    canFlip: map['canFlip'] == true,
    previewWidth: _int(map['previewWidth']),
    previewHeight: _int(map['previewHeight']),
    rotation: _int(map['rotation']) ?? 0,
    mirrored: map['mirrored'] == true,
    cameraTransform: map['cameraTransform'] != false,
    displayRotation: _int(map['displayRotation']) ?? 0,
    galleryNeedsPermission: map['galleryNeedsPermission'] == true,
  );
}

/// A finished recording from the channel; null for an empty answer.
RecordedVideo? recordedVideoFrom(Map<Object?, Object?>? map) {
  final path = map?['path'];
  if (path is! String || path.isEmpty) return null;
  final uri = map?['uri'];
  return RecordedVideo(
    path: path,
    uri: uri is String && uri.isNotEmpty ? uri : null,
    durationMs: _int(map?['durationMs']) ?? 0,
  );
}

/// One event from `slimshot_ai/camera_events`, or null for one this build
/// does not know.
CameraEvent? cameraEventFrom(Object? raw) {
  if (raw is! Map) return null;
  switch (raw['type']) {
    case 'preview':
      return PreviewChanged(
        previewWidth: _int(raw['previewWidth']),
        previewHeight: _int(raw['previewHeight']),
        rotation: _int(raw['rotation']) ?? 0,
        mirrored: raw['mirrored'] == true,
        cameraTransform: raw['cameraTransform'] != false,
        displayRotation: _int(raw['displayRotation']) ?? 0,
      );
    case 'recording':
      return RecordingProgress(
        durationMs: _int(raw['durationMs']) ?? 0,
        paused: raw['paused'] == true,
      );
    case 'recordingEnded':
      final video = recordedVideoFrom(raw.cast<Object?, Object?>());
      return RecordingEnded(
        path: video?.path,
        uri: video?.uri,
        durationMs: video?.durationMs ?? 0,
      );
    case 'camera':
      final message = raw['message'];
      return CameraAvailability(
        open: raw['open'] == true,
        message: message is String ? message : null,
      );
  }
  return null;
}
