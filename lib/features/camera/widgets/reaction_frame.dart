import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../video_editor/services/media_import_service.dart';
import '../logic/reaction.dart';
import '../logic/reaction_session.dart';

/// What REACT reacts to — a video, or a photo — as the take's player, and its
/// picture to lay out.
abstract class ReactionVideo implements ReactionPlayer {
  /// The picture's width over its height, upright.
  double get aspectRatio;

  /// A still: no sound, no clock — its player does nothing and never ends.
  bool get isPhoto;

  /// The video's picture, in its own shape.
  Widget picture();

  Future<void> setVolume(double volume);

  Future<void> dispose();
}

/// Opens the video or photo at a path for REACT; null when it will not open.
typedef ReactionVideoOpener = Future<ReactionVideo?> Function(String path);

/// What a live reaction reacts to, as the screen needs it: its upright shape
/// and its kind. The live recorder plays it; the screen only lays it out.
@immutable
class ReactionSourceInfo {
  const ReactionSourceInfo({required this.aspect, required this.isPhoto});

  final double aspect;
  final bool isPhoto;
}

/// Measures the file at a path for a live reaction; null when it cannot be read.
typedef ReactionSourceProbe = Future<ReactionSourceInfo?> Function(String path);

/// The editor's own probe — its fits are made from it, so a live reaction's
/// layout is the editor's for the same file.
Future<ReactionSourceInfo?> probeReactionSource(String path) async {
  try {
    final assets = await MediaImportService().assetsFor([XFile(path)]);
    final asset = assets.isEmpty ? null : assets.first;
    if (asset == null) return null;
    final aspect = asset.aspectRatio;
    return ReactionSourceInfo(aspect: aspect.isFinite && aspect > 0 ? aspect : 16 / 9, isPhoto: asset.isImage);
  } catch (error) {
    debugPrint('REACT: could not probe $path: $error');
    return null;
  }
}

/// The file at [path] opened for REACT: a photo as a still, anything else
/// through `video_player`. Its kind and a photo's upright shape come from the
/// editor's own probe, the one its fits are made from.
Future<ReactionVideo?> openReactionSource(String path) async {
  try {
    final assets = await MediaImportService().assetsFor([XFile(path)]);
    final asset = assets.isEmpty ? null : assets.first;
    if (asset != null && asset.isImage) {
      final aspect = asset.aspectRatio;
      return PhotoReactionSource(path, aspect.isFinite && aspect > 0 ? aspect : 1);
    }
  } catch (error) {
    debugPrint('REACT: could not probe $path: $error');
  }
  return PluginReactionVideo.open(path);
}

/// A photo as what REACT reacts to: there for the whole take, silent.
class PhotoReactionSource implements ReactionVideo {
  PhotoReactionSource(this.path, this.aspectRatio);

  final String path;

  @override
  final double aspectRatio;

  @override
  bool get isPhoto => true;

  @override
  int get durationMs => 0;

  @override
  bool get completed => false;

  @override
  Future<int?> positionMs() async => 0;

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekTo(int ms) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Widget picture() => Image.file(File(path), fit: BoxFit.fill, gaplessPlayback: true);

  @override
  Future<void> dispose() async {}
}

/// `video_player` as REACT's video.
class PluginReactionVideo implements ReactionVideo {
  PluginReactionVideo._(this._player);

  final VideoPlayerController _player;

  static Future<ReactionVideo?> open(String path) async {
    final player = VideoPlayerController.file(File(path));
    try {
      await player.initialize();
      await player.setLooping(false);
      return PluginReactionVideo._(player);
    } catch (_) {
      unawaited(player.dispose());
      return null;
    }
  }

  @override
  bool get isPhoto => false;

  @override
  double get aspectRatio {
    final aspect = _player.value.aspectRatio;
    return aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
  }

  @override
  int get durationMs => _player.value.duration.inMilliseconds;

  @override
  bool get completed => _player.value.isCompleted;

  @override
  Future<int?> positionMs() async => (await _player.position)?.inMilliseconds;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seekTo(int ms) => _player.seekTo(Duration(milliseconds: ms));

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Widget picture() => VideoPlayer(_player);

  @override
  Future<void> dispose() => _player.dispose();
}

/// The reaction as the file will show it: a 9:16 frame with you and the video
/// where [layout] puts you ([reactionPlaces], the one definition the file is
/// rendered from). Each picture fills its place edge to edge; in the float,
/// the video's window can be dragged and pinched while [windowMovable].
/// A [placeholder] stands in the video's place, unscaled, until there is one.
/// Through a take, [onVideoTap] answers a tap on the video, [videoChrome] is
/// laid over its place, and once the video is gone ([videoGone]) you fill
/// the frame. With a [composite] — REACT recorded live, where the recorder
/// draws both pictures into one texture — that is drawn under everything and
/// neither picture is drawn here; the video's place keeps its gestures,
/// placeholder and chrome.
class ReactionFrame extends StatefulWidget {
  const ReactionFrame({
    super.key,
    required this.layout,
    required this.window,
    required this.videoAspect,
    required this.video,
    required this.camera,
    this.onWindowChanged,
    this.windowMovable = true,
    this.placeholder,
    this.onVideoTap,
    this.videoChrome,
    this.videoGone = false,
    this.composite,
  });

  final ReactionLayout layout;
  final ReactionWindow window;
  final double videoAspect;
  final Widget video;

  /// The camera's picture, covering a place of the size it is given.
  final Widget Function(Size place) camera;

  final ValueChanged<ReactionWindow>? onWindowChanged;
  final bool windowMovable;
  final Widget? placeholder;
  final VoidCallback? onVideoTap;
  final Widget? videoChrome;
  final bool videoGone;
  final Widget? composite;

  /// Where the camera's picture sits in a frame of [frame] — what a tap to
  /// focus is measured against.
  static Rect cameraPlace({
    required ReactionLayout layout,
    required ReactionWindow window,
    required double videoAspect,
    required Size frame,
    bool videoGone = false,
  }) =>
      videoGone
          ? Offset.zero & frame
          : _scaled(reactionPlaces(layout: layout, window: window, videoAspect: videoAspect).camera, frame);

  @override
  State<ReactionFrame> createState() => _ReactionFrameState();
}

Rect _scaled(Rect fractions, Size frame) => Rect.fromLTWH(
      fractions.left * frame.width,
      fractions.top * frame.height,
      fractions.width * frame.width,
      fractions.height * frame.height,
    );

class _ReactionFrameState extends State<ReactionFrame> {
  // The window follows an anchor — where the finger came down, and the
  // window then — never a sum of moves: a move held back at the frame's edge
  // is not lost, so the window stays under the finger.
  ReactionWindow _startWindow = ReactionWindow.initial;
  Offset _startFocal = Offset.zero;
  double _startScale = 1;
  int _pointers = 0;

  /// Where the last finger came down. The scale gesture starts only once the
  /// finger has travelled, and anchoring there would leave the window that
  /// far behind it.
  Offset? _downAt;

  void _anchor(Offset focal, double scale, int pointers) {
    _startWindow = widget.window;
    _startFocal = focal;
    _startScale = scale;
    _pointers = pointers;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = constraints.biggest;
        final places = reactionPlaces(layout: widget.layout, window: widget.window, videoAspect: widget.videoAspect);
        final cameraRect = widget.videoGone ? Offset.zero & frame : _scaled(places.camera, frame);
        final videoRect = _scaled(places.video, frame);
        final composite = widget.composite;
        final video = widget.placeholder ?? (composite != null ? const SizedBox.expand() : ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: 100 * widget.videoAspect,
              height: 100,
              child: widget.video,
            ),
          ),
        ));
        return ClipRect(
          child: Stack(
            children: [
              if (composite != null)
                Positioned.fill(child: composite)
              else
                Positioned.fromRect(
                  rect: cameraRect,
                  child: ClipRect(child: widget.camera(cameraRect.size)),
                ),
              if (!widget.videoGone)
                Positioned.fromRect(
                  key: const ValueKey('reaction_video'),
                  rect: videoRect,
                  child: _withChrome(_tappable(widget.layout == ReactionLayout.float
                    ? IgnorePointer(
                        ignoring: !widget.windowMovable,
                        child: Listener(
                          onPointerDown: (event) => _downAt = event.position,
                          child: GestureDetector(
                            key: const ValueKey('reaction_window'),
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: (details) => _anchor(
                              details.pointerCount == 1 ? _downAt ?? details.focalPoint : details.focalPoint,
                              1,
                              details.pointerCount,
                            ),
                            onScaleUpdate: (details) {
                              // A finger joining or leaving moves the focal
                              // point: the gesture carries on from here.
                              if (details.pointerCount != _pointers) {
                                _anchor(details.focalPoint, details.scale, details.pointerCount);
                                return;
                              }
                              final moved = details.focalPoint - _startFocal;
                              final scale = _startScale > 0 ? details.scale / _startScale : 1.0;
                              widget.onWindowChanged?.call(ReactionWindow(
                                centerX: _startWindow.centerX + moved.dx / frame.width,
                                centerY: _startWindow.centerY + moved.dy / frame.height,
                                width: _startWindow.width * scale,
                              ).fittedFor(widget.videoAspect));
                            },
                            child: video,
                          ),
                        ),
                      )
                    : video)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tappable(Widget child) {
    final onTap = widget.onVideoTap;
    if (onTap == null) return child;
    return GestureDetector(
      key: const ValueKey('reaction_video_tap'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }

  Widget _withChrome(Widget child) {
    final chrome = widget.videoChrome;
    if (chrome == null) return child;
    return Stack(fit: StackFit.expand, children: [child, chrome]);
  }
}

/// The reaction frame's place on a screen: 9:16, as large as fits, centred.
Rect reactionFrameOn(Size screen) {
  const aspect = 9 / 16;
  if (screen.width <= 0 || screen.height <= 0) return Offset.zero & screen;
  final width = screen.width / screen.height > aspect ? screen.height * aspect : screen.width;
  final height = width / aspect;
  return Rect.fromCenter(center: screen.center(Offset.zero), width: width, height: height);
}
