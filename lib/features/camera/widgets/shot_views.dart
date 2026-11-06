import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../video_editor/services/video_thumbnail_service.dart';
import '../logic/camera_controller.dart';
import '../logic/camera_roll.dart';

/// Loads a video's first frame for a thumbnail; the real one is the
/// filmstrip's extractor, tests give their own.
typedef VideoFrameLoader = Future<Uint8List?> Function(String path);

Future<Uint8List?> _filmstripFrame(String path) =>
    VideoThumbnailService.instance.singleFrame(path: path, timeMs: 0, width: 192, height: 192);

/// A shot's small picture: a photo decoded small, or a video's first frame
/// with a play mark. A shot that will not load shows its kind's glyph.
class ShotThumbnail extends StatefulWidget {
  const ShotThumbnail({super.key, required this.shot, required this.size, this.loadFrame});

  final RollShot shot;
  final double size;
  final VideoFrameLoader? loadFrame;

  @override
  State<ShotThumbnail> createState() => _ShotThumbnailState();
}

class _ShotThumbnailState extends State<ShotThumbnail> {
  Uint8List? _frame;

  @override
  void initState() {
    super.initState();
    if (widget.shot.isVideo) _load();
  }

  @override
  void didUpdateWidget(ShotThumbnail old) {
    super.didUpdateWidget(old);
    if (widget.shot.isVideo && old.shot.path != widget.shot.path) {
      _frame = null;
      _load();
    }
  }

  void _load() {
    final path = widget.shot.path;
    final cached = widget.loadFrame == null ? VideoThumbnailService.instance.peek(path, 0) : null;
    if (cached != null) {
      _frame = cached;
      return;
    }
    unawaited((widget.loadFrame ?? _filmstripFrame)(path).then((bytes) {
      if (mounted && widget.shot.path == path && bytes != null) setState(() => _frame = bytes);
    }).catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shot;
    final pixels = (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget picture;
    if (shot.isVideo) {
      picture = _frame == null
          ? const _Placeholder(icon: LucideIcons.video)
          : Image.memory(_frame!, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      picture = Image.file(
        File(shot.path),
        fit: BoxFit.cover,
        cacheWidth: pixels,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => const _Placeholder(icon: LucideIcons.image),
      );
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          picture,
          if (shot.isVideo)
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  LucideIcons.play,
                  size: widget.size * 0.28,
                  color: AppColors.textPrimary,
                  shadows: [Shadow(color: AppColors.background.withValues(alpha: 0.7), blurRadius: 4)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceLight,
      child: Center(child: Icon(icon, size: 18, color: AppColors.textSecondary)),
    );
  }
}

/// A video shot playing on a loop the moment it is ready; a tap pauses or
/// plays, and a bar above [footHeight] scrubs.
class ShotVideo extends StatefulWidget {
  const ShotVideo({super.key, required this.path, this.footHeight = 0});

  final String path;

  /// The room the screen's own controls take at the foot.
  final double footHeight;

  @override
  State<ShotVideo> createState() => _ShotVideoState();
}

class _ShotVideoState extends State<ShotVideo> {
  late final VideoPlayerController _player = VideoPlayerController.file(File(widget.path));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _player.initialize();
      await _player.setLooping(true);
      await _player.play();
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  void _toggle() {
    if (!_player.value.isInitialized) return;
    setState(() {
      _player.value.isPlaying ? _player.pause() : _player.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(child: Icon(LucideIcons.videoOff, color: AppColors.textSecondary, size: 40));
    }
    final value = _player.value;
    if (!value.isInitialized) return const SizedBox.expand();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio,
              child: VideoPlayer(_player),
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _player,
            builder: (context, value, _) => IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: value.isPlaying ? 0 : 1,
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background.withValues(alpha: 0.45),
                    ),
                    child: const Icon(LucideIcons.play, color: AppColors.textPrimary, size: 28),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, widget.footHeight + 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _player,
                      builder: (context, value, _) => Text(
                        '${formatRecordingTime(value.position.inMilliseconds)} / '
                        '${formatRecordingTime(value.duration.inMilliseconds)}',
                        style: const TextStyle(
                          fontFamily: kInterfaceFontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: VideoProgressIndicator(
                        _player,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        colors: VideoProgressColors(
                          playedColor: AppColors.textPrimary,
                          bufferedColor: AppColors.textPrimary.withValues(alpha: 0.3),
                          backgroundColor: AppColors.textPrimary.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last shots stacked beside the shutter — the newest on top, two tilted
/// behind it — and the way into them. A new shot drops onto the stack.
class CameraRollPile extends StatelessWidget {
  const CameraRollPile({super.key, required this.shots, required this.onTap, this.loadFrame});

  /// Newest first.
  final List<RollShot> shots;
  final VoidCallback onTap;
  final VideoFrameLoader? loadFrame;

  static const double size = 46;

  /// The pile is three cards at most, however many shots there are (the
  /// owner's call): the newest and two behind it.
  static const int maxCards = 3;

  Widget _card(RollShot shot, {required bool top}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: top ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.7),
          width: 2,
        ),
        boxShadow: [BoxShadow(color: AppColors.background.withValues(alpha: 0.35), blurRadius: 6)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ShotThumbnail(shot: shot, size: size - 4, loadFrame: loadFrame),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) return const SizedBox(width: size, height: size);
    final behind = (shots.length < maxCards ? shots.length : maxCards) - 1;
    return Semantics(
      button: true,
      label: 'Your shots',
      child: GestureDetector(
        key: const ValueKey('camera_roll_pile'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: size + 12,
          height: size + 12,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (var i = behind; i >= 1; i--)
                Transform.translate(
                  offset: Offset(-4.0 * i, 3.0 * i),
                  child: Transform.rotate(angle: -0.16 * i, child: _card(shots[i], top: false)),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.35, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(shots.first.path), child: _card(shots.first, top: true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
