import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Which camera on the phone.
enum CameraLens { front, back }

/// What the shutter makes. REACT records you as video does, while a video
/// plays beside you — privately: the reaction made from the take is what
/// goes to the gallery, not the take.
enum CameraMode { photo, video, react }

/// A photo's flash; in video it is the torch, which is only off or on.
enum CameraFlash { off, auto, on }

enum CameraStatus { closed, opening, ready, failed }

enum RecordingState { idle, recording, paused }

/// A camera operation the phone refused, worded for the user.
class CameraFailure implements Exception {
  const CameraFailure(this.message);

  final String message;

  @override
  String toString() => 'CameraFailure: $message';
}

/// What the open camera is, as the phone describes it.
///
/// The preview fields arrive a moment after the camera opens — CameraX tells
/// them once the picture has somewhere to go — so they start unknown.
@immutable
class CameraInfo {
  const CameraInfo({
    required this.textureId,
    required this.lens,
    required this.mode,
    required this.hasFlash,
    required this.minZoom,
    required this.maxZoom,
    required this.canFlip,
    this.previewWidth,
    this.previewHeight,
    this.rotation = 0,
    this.mirrored = false,
    this.cameraTransform = true,
    this.displayRotation = 0,
    this.galleryNeedsPermission = false,
  });

  final int textureId;
  final CameraLens lens;
  final CameraMode mode;
  final bool hasFlash;
  final double minZoom;
  final double maxZoom;

  /// The phone has a camera on both sides.
  final bool canFlip;

  /// The camera's buffer, before it is turned upright.
  final int? previewWidth;
  final int? previewHeight;

  /// Degrees, clockwise, that turn the buffer upright on the screen.
  final int rotation;

  /// The buffer is to be shown mirrored (a selfie).
  final bool mirrored;

  /// The camera itself turned and mirrored the picture on its way to the
  /// texture, so nothing is left to do but the screen's own rotation.
  final bool cameraTransform;

  /// The screen's rotation from the phone's natural orientation, in degrees.
  final int displayRotation;

  /// Android 10 and older: saving to the gallery, and reading a saved shot
  /// back, needs storage access. Android 11 and up need none for the app's
  /// own files.
  final bool galleryNeedsPermission;

  CameraInfo withPreview(PreviewChanged preview) => CameraInfo(
        textureId: textureId,
        lens: lens,
        mode: mode,
        hasFlash: hasFlash,
        minZoom: minZoom,
        maxZoom: maxZoom,
        canFlip: canFlip,
        previewWidth: preview.previewWidth ?? previewWidth,
        previewHeight: preview.previewHeight ?? previewHeight,
        rotation: preview.rotation,
        mirrored: preview.mirrored,
        cameraTransform: preview.cameraTransform,
        displayRotation: preview.displayRotation,
        galleryNeedsPermission: galleryNeedsPermission,
      );
}

/// Something the camera says on its own.
sealed class CameraEvent {
  const CameraEvent();
}

/// The picture's buffer, turn or mirroring changed.
class PreviewChanged extends CameraEvent {
  const PreviewChanged({
    this.previewWidth,
    this.previewHeight,
    this.rotation = 0,
    this.mirrored = false,
    this.cameraTransform = true,
    this.displayRotation = 0,
  });

  final int? previewWidth;
  final int? previewHeight;
  final int rotation;
  final bool mirrored;
  final bool cameraTransform;
  final int displayRotation;
}

/// How long the recording running now holds.
class RecordingProgress extends CameraEvent {
  const RecordingProgress({required this.durationMs, required this.paused});

  final int durationMs;
  final bool paused;
}

/// A recording ended without being asked to — the app left the screen, or
/// the camera was taken away. [path] is null when nothing usable was kept.
class RecordingEnded extends CameraEvent {
  const RecordingEnded({this.path, this.uri, this.durationMs = 0});

  final String? path;

  /// The video's address in the gallery; null for one kept in SlimShot.
  final String? uri;
  final int durationMs;
}

/// The camera opened, or was taken away — another app, a policy — with
/// [message] saying why. CameraX opens it again by itself when it can.
class CameraAvailability extends CameraEvent {
  const CameraAvailability({required this.open, this.message});

  final bool open;
  final String? message;
}

class RecordedVideo {
  const RecordedVideo({required this.path, this.uri, required this.durationMs});

  final String path;
  final String? uri;
  final int durationMs;
}

/// Where a photo was saved: the file, and its gallery address (null for one
/// kept in SlimShot's own folder).
class SavedShot {
  const SavedShot({required this.path, this.uri});

  final String path;
  final String? uri;
}

/// The phone's camera, as the controller needs it. The real one is
/// `MethodChannelCamera`; tests drive a fake.
abstract class CameraBackend {
  Stream<CameraEvent> get events;

  Future<CameraInfo> open({
    required CameraLens lens,
    required CameraMode mode,
    required CameraFlash flash,
  });

  /// Binds another lens or mode, with that mode's [flash] from the start —
  /// binding first and setting the flash after would blink a torch on.
  Future<CameraInfo> configure({
    required CameraLens lens,
    required CameraMode mode,
    required CameraFlash flash,
  });

  Future<void> setFlash(CameraFlash flash);

  Future<void> setZoom(double ratio);

  /// [point] in 0..1 of the whole upright picture, crop included.
  Future<void> focus(Offset point);

  /// Takes a photo into [path]; with [gallery] it is then moved into the
  /// gallery's SlimShotAI album, and the answer says where it landed.
  Future<SavedShot> takePhoto(String path, {required bool gallery});

  /// Records into the gallery's SlimShotAI album with [gallery], into [path]
  /// without it.
  Future<void> startRecording(String path, {required bool audio, required bool gallery});

  Future<void> pauseRecording();

  Future<void> resumeRecording();

  /// Null when nothing usable was recorded.
  Future<RecordedVideo?> stopRecording();

  /// The phone's sound is going to headphones, where the microphone cannot
  /// hear it.
  Future<bool> headphonesConnected();

  /// Moves a finished video — a reaction — into the gallery's SlimShotAI
  /// album. Null where the gallery would not take it; the file then stays.
  Future<SavedShot?> publishVideo(String path);

  Future<void> close();
}

/// What a press of the shutter made, already saved.
sealed class CameraShot {
  const CameraShot(this.path, {this.uri});

  final String path;

  /// The shot's address in the gallery; null for one kept in SlimShot.
  final String? uri;
}

class PhotoShot extends CameraShot {
  const PhotoShot(super.path, {super.uri});
}

class VideoShot extends CameraShot {
  const VideoShot(super.path, {super.uri, required this.durationMs});

  final int durationMs;
}

/// Where a new shot is written, for a file extension (`jpg`, `mp4`).
typedef ShotPath = Future<String> Function(String extension);

/// Whether a recording may take sound; asks the user where it has to.
typedef MicrophoneGate = Future<bool> Function();

/// Whether shots may go to the gallery where that needs storage access;
/// asks the user where it has to.
typedef StorageGate = Future<bool> Function();

const kRecordingWithoutSoundMessage = 'No microphone access — recording without sound.';
const kNothingRecordedMessage = 'Nothing was recorded.';
const kRecordingStoppedMessage = 'The recording stopped.';
const kCameraTakenAwayMessage = 'The camera stopped working.';
const kGalleryOffMessage = 'Storage access is off: shots are kept in SlimShot only.';

/// The camera screen's decisions, apart from the widgets and the phone: the
/// mode, the lens, each mode's flash, the zoom, the recording's state, and
/// what the shutter does in each.
///
/// [message] is the last thing to tell the user. A notice is taken once with
/// [takeMessage]; while [status] is failed it is the reason, shown in place.
class CameraController extends ChangeNotifier {
  CameraController({
    required CameraBackend backend,
    required ShotPath newPath,
    required MicrophoneGate allowMicrophone,
    required StorageGate allowStorage,
    CameraLens initialLens = CameraLens.back,
    Duration Function()? clock,
  })  : _backend = backend,
        _newPath = newPath,
        _allowMicrophone = allowMicrophone,
        _allowStorage = allowStorage,
        _clock = clock ?? _monotonicClock,
        _lens = initialLens {
    _events = backend.events.listen(_onEvent);
  }

  final CameraBackend _backend;
  final ShotPath _newPath;
  final MicrophoneGate _allowMicrophone;
  final StorageGate _allowStorage;
  final Duration Function() _clock;
  late final StreamSubscription<CameraEvent> _events;

  static final Stopwatch _monotonic = Stopwatch()..start();
  static Duration _monotonicClock() => _monotonic.elapsed;

  CameraStatus _status = CameraStatus.closed;
  CameraInfo? _info;
  String? _message;
  CameraLens _lens;
  CameraMode _mode = CameraMode.photo;
  final Map<CameraMode, CameraFlash> _flashFor = {
    CameraMode.photo: CameraFlash.off,
    CameraMode.video: CameraFlash.off,
    CameraMode.react: CameraFlash.off,
  };
  double _zoom = 1;
  RecordingState _recording = RecordingState.idle;
  int _recordedMs = 0;

  /// When [_recordedMs] was last true: the recording's last report, or the
  /// resume since. Null until the running recording has reported.
  Duration? _progressAt;
  bool _busy = false;
  bool _saidNoSound = false;
  bool _saidGalleryOff = false;
  String? _recordingPath;
  CameraShot? _endedShot;
  bool _disposed = false;

  /// Failed because the camera was taken away, not because it never opened —
  /// only this failure lifts when the camera comes back.
  bool _takenAway = false;

  CameraStatus get status => _status;
  CameraInfo? get info => _info;
  String? get message => _message;
  CameraLens get lens => _lens;
  CameraMode get mode => _mode;
  double get zoom => _zoom;
  RecordingState get recording => _recording;
  int get recordedMs => _recordedMs;

  /// A photo is being taken, or a recording is starting or stopping.
  bool get busy => _busy;

  bool get isRecording => _recording != RecordingState.idle;

  /// The flash as it is: off on a lens that has none.
  CameraFlash get flash => (_info?.hasFlash ?? false) ? _flashFor[_mode]! : CameraFlash.off;

  bool get canChangeMode => _status == CameraStatus.ready && !isRecording && !_busy;

  bool get canFlip => canChangeMode && (_info?.canFlip ?? false);

  /// Where the running recording is now, in milliseconds of its file: its
  /// last report carried on to this instant, held still while paused. Null
  /// until the recording has reported, which is when it is known to run.
  ///
  /// REACT times the video against this. The reports come as the recorder
  /// writes, and between them the file grows at the clock's own rate.
  int? recordingNowMs() {
    final at = _progressAt;
    if (!isRecording || at == null) return null;
    if (_recording == RecordingState.paused) return _recordedMs;
    return _recordedMs + (_clock() - at).inMilliseconds;
  }

  /// The notice to show, once.
  String? takeMessage() {
    final said = _message;
    _message = null;
    return said;
  }

  /// A recording the camera ended by itself, once.
  CameraShot? takeEndedShot() {
    final shot = _endedShot;
    _endedShot = null;
    return shot;
  }

  Future<void> open() async {
    if (_status == CameraStatus.opening) return;
    _status = CameraStatus.opening;
    _takenAway = false;
    _message = null;
    _notify();
    try {
      _info = await _backend.open(lens: _lens, mode: _mode, flash: _flashFor[_mode]!);
      _adopt(_info!);
      _status = CameraStatus.ready;
    } on CameraFailure catch (failure) {
      _status = CameraStatus.failed;
      _message = failure.message;
    }
    _notify();
  }

  /// Changes mode — and, with [lens], the lens with it in the one bind:
  /// REACT starts on the front camera, and two binds in a row would show the
  /// back camera for a moment.
  Future<void> setMode(CameraMode mode, {CameraLens? lens}) async {
    if (mode == _mode || !canChangeMode) return;
    final before = _mode;
    final lensBefore = _lens;
    _mode = mode;
    if (lens != null && (_info?.canFlip ?? false)) _lens = lens;
    _notify();
    if (!await _rebind()) {
      _mode = before;
      _lens = lensBefore;
      await _rebind(quietly: true);
    }
    _notify();
    // Asked on the way into video, so the shutter starts at once.
    if (_mode != CameraMode.photo) unawaited(_allowMicrophone());
  }

  Future<void> flip() async {
    if (!canFlip) return;
    final before = _lens;
    _lens = _lens == CameraLens.back ? CameraLens.front : CameraLens.back;
    _notify();
    if (!await _rebind()) {
      _lens = before;
      await _rebind(quietly: true);
    }
    _notify();
  }

  Future<void> cycleFlash() async {
    if (!(_info?.hasFlash ?? false) || _status != CameraStatus.ready) return;
    final now = _flashFor[_mode]!;
    final next = switch (_mode) {
      CameraMode.photo => switch (now) {
          CameraFlash.off => CameraFlash.auto,
          CameraFlash.auto => CameraFlash.on,
          CameraFlash.on => CameraFlash.off,
        },
      CameraMode.video || CameraMode.react => now == CameraFlash.on ? CameraFlash.off : CameraFlash.on,
    };
    _flashFor[_mode] = next;
    _notify();
    try {
      await _backend.setFlash(next);
    } on CameraFailure catch (failure) {
      _flashFor[_mode] = now;
      _say(failure.message);
    }
  }

  Future<void> zoomTo(double ratio) async {
    final info = _info;
    if (info == null || _status != CameraStatus.ready) return;
    final clamped = ratio.clamp(info.minZoom, info.maxZoom).toDouble();
    if (clamped == _zoom) return;
    _zoom = clamped;
    _notify();
    try {
      await _backend.setZoom(clamped);
    } on CameraFailure {
      // A zoom the camera did not take simply stays where the camera is.
    }
  }

  Future<void> focusAt(Offset point) async {
    if (_status != CameraStatus.ready) return;
    try {
      await _backend.focus(point);
    } on CameraFailure {
      // Focus is a hint; a camera that ignores it keeps its own.
    }
  }

  /// A photo, or the start or end of a video. Null when nothing was made
  /// yet — a recording started — or nothing could be.
  Future<CameraShot?> shutter() async {
    if (_status != CameraStatus.ready || _busy) return null;
    _busy = true;
    _notify();
    try {
      switch (_mode) {
        case CameraMode.photo:
          final gallery = await _galleryAllowed();
          final saved = await _backend.takePhoto(await _newPath('jpg'), gallery: gallery);
          return PhotoShot(saved.path, uri: saved.uri);
        case CameraMode.video:
        case CameraMode.react:
          if (isRecording) return await _stop();
          await _start();
          return null;
      }
    } on CameraFailure catch (failure) {
      _message = failure.message;
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> pauseOrResume() async {
    if (!isRecording || _busy) return;
    try {
      if (_recording == RecordingState.recording) {
        final at = recordingNowMs();
        await _backend.pauseRecording();
        if (at != null) _recordedMs = at;
        _recording = RecordingState.paused;
      } else {
        await _backend.resumeRecording();
        // The file grows again from where it stopped, not from the report
        // before the pause.
        if (_progressAt != null) _progressAt = _clock();
        _recording = RecordingState.recording;
      }
    } on CameraFailure catch (failure) {
      _message = failure.message;
    }
    _notify();
  }

  Future<void> close() async {
    _status = CameraStatus.closed;
    _recording = RecordingState.idle;
    _notify();
    await _backend.close();
  }

  Future<void> _start() async {
    final audio = await _allowMicrophone();
    if (!audio && !_saidNoSound) {
      _saidNoSound = true;
      _message = kRecordingWithoutSoundMessage;
    }
    final gallery = _mode == CameraMode.video && await _galleryAllowed();
    final path = await _newPath('mp4');
    _progressAt = null;
    await _backend.startRecording(path, audio: audio, gallery: gallery);
    _recordingPath = path;
    _recordedMs = 0;
    _recording = RecordingState.recording;
  }

  Future<CameraShot?> _stop() async {
    final video = await _backend.stopRecording();
    _recording = RecordingState.idle;
    _recordingPath = null;
    _progressAt = null;
    if (video == null) {
      _message = kNothingRecordedMessage;
      return null;
    }
    return VideoShot(video.path, uri: video.uri, durationMs: video.durationMs);
  }

  /// Whether what the camera makes may go to the gallery — asked where that
  /// needs storage access (Android 10 and older), said once when refused.
  Future<bool> galleryAllowed() => _galleryAllowed();

  /// Every shot goes straight to the gallery; where that needs storage
  /// access and it is refused, shots stay in SlimShot's own folder, said once.
  Future<bool> _galleryAllowed() async {
    if (!(_info?.galleryNeedsPermission ?? false)) return true;
    if (await _allowStorage()) return true;
    if (!_saidGalleryOff) {
      _saidGalleryOff = true;
      _message = kGalleryOffMessage;
    }
    return false;
  }

  /// Binds the current lens and mode; false when the phone refused.
  Future<bool> _rebind({bool quietly = false}) async {
    try {
      final info = await _backend.configure(lens: _lens, mode: _mode, flash: _flashFor[_mode]!);
      _info = info;
      _adopt(info);
      _status = CameraStatus.ready;
      return true;
    } on CameraFailure catch (failure) {
      if (quietly) {
        _status = CameraStatus.failed;
      } else {
        _message = failure.message;
      }
      return false;
    }
  }

  void _adopt(CameraInfo info) {
    // The phone may answer with the other lens where it has only that one.
    _lens = info.lens;
    _zoom = 1.0.clamp(info.minZoom, info.maxZoom).toDouble();
  }

  void _onEvent(CameraEvent event) {
    switch (event) {
      case PreviewChanged():
        final info = _info;
        if (info == null) return;
        _info = info.withPreview(event);
      case RecordingProgress():
        if (!isRecording) return;
        _recordedMs = event.durationMs;
        if (!event.paused && _recording == RecordingState.recording) _progressAt = _clock();
      case RecordingEnded():
        if (!isRecording) return;
        _recording = RecordingState.idle;
        final path = event.path ?? _recordingPath;
        _recordingPath = null;
        if (event.path != null && path != null) {
          _endedShot = VideoShot(path, uri: event.uri, durationMs: event.durationMs);
        } else {
          _message = kRecordingStoppedMessage;
        }
      case CameraAvailability():
        if (event.open) {
          if (!_takenAway) return;
          _takenAway = false;
          _status = CameraStatus.ready;
          _message = null;
        } else {
          if (_status != CameraStatus.ready) return;
          _takenAway = true;
          _status = CameraStatus.failed;
          _message = event.message ?? kCameraTakenAwayMessage;
        }
    }
    _notify();
  }

  void _say(String message) {
    _message = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
    if (_status != CameraStatus.closed) unawaited(_backend.close());
    super.dispose();
  }
}

/// The running time of a recording: `0:07`, `1:05`, `1:00:03`.
String formatRecordingTime(int milliseconds) {
  final total = milliseconds ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  return '$minutes:$seconds';
}
