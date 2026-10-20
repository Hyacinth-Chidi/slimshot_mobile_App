import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// The Extract sheet's video: plays the picked video, looping between the
/// handles, so the user hears exactly the sound they will get.
abstract class ExtractPreviewPlayer {
  Future<void> open(String videoPath);

  /// Plays from [start] and comes back to it at [end], in seconds.
  Future<void> playRange(double start, double end);

  Future<void> pause();

  Future<void> dispose();

  /// The picture, sized to the video's own shape.
  Widget view();
}

/// [ExtractPreviewPlayer] over `video_player`. Plugin code, device-tested.
class VideoPlayerExtractPreview implements ExtractPreviewPlayer {
  VideoPlayerController? _controller;
  final ValueNotifier<int> _opened = ValueNotifier(0);
  double _start = 0;
  double _end = double.infinity;
  bool _wantsToPlay = false;
  bool _disposed = false;

  @override
  Future<void> open(String videoPath) async {
    await _release();
    if (_disposed) return;
    final controller = VideoPlayerController.file(File(videoPath));
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      // No picture is not a reason to refuse the sound.
      return;
    }
    // Closed, or another video opened, while this one loaded: `_release`
    // has already disposed it, and the notifier may be gone with the sheet.
    if (_disposed || _controller != controller) return;
    controller.addListener(_loop);
    _opened.value++;
  }

  /// Back to the start of the range at its end — and at the file's end,
  /// where the player stops on its own.
  void _loop() {
    final controller = _controller;
    if (controller == null || !_wantsToPlay) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    final seconds = value.position.inMicroseconds / 1e6;
    if (seconds >= _end || value.isCompleted) {
      controller.seekTo(_at(_start));
      if (!value.isPlaying) controller.play();
    }
  }

  static Duration _at(double seconds) =>
      Duration(microseconds: (seconds * 1e6).round());

  @override
  Future<void> playRange(double start, double end) async {
    _start = start;
    _end = end;
    _wantsToPlay = true;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(_at(start));
    await controller.play();
  }

  @override
  Future<void> pause() async {
    _wantsToPlay = false;
    await _controller?.pause();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _release();
    _opened.dispose();
  }

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_loop);
    await controller.dispose();
  }

  @override
  Widget view() => ValueListenableBuilder<int>(
        valueListenable: _opened,
        builder: (context, _, _) {
          final controller = _controller;
          if (controller == null || !controller.value.isInitialized) {
            return const SizedBox.shrink();
          }
          return AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          );
        },
      );
}
