import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/media_save_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_fonts.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/result_exit.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/widgets/discard_dialog.dart';
import '../logic/camera_controller.dart';
import '../logic/camera_files.dart';
import 'camera_screen.dart';

/// Plays a shot's video in the review: the real one is [video_player]'s;
/// widget tests give a still.
typedef ShotVideoView = Widget Function(String path);

/// Saves a shot to the gallery; the real one is [MediaSaveService].
typedef ShotSave = Future<void> Function(String path);

/// Hands a shot to the share sheet; true unless it was closed unused.
typedef ShotShare = Future<bool> Function(String path);

/// After every shot: the photo, or the video playing on a loop, and
/// **Retake · Save · Share · Edit**. Save copies it to the gallery, Share hands
/// over a copy, Edit opens it in the editor as a new project.
///
/// Leaving by Retake or Back throws the shot away — the app's own file, of no
/// use once off screen: a saved one is in the gallery and a shared one was
/// copied — after asking, when it was neither saved nor shared (the result
/// screens' rule, [ResultExit]). Edit keeps it: the editor's draft plays
/// from it. Until then the shot holds the app ([ResultExit.hold]), so a tap
/// on the home screen widget cannot throw it away.
class CameraReviewScreen extends StatefulWidget {
  const CameraReviewScreen({
    super.key,
    required this.shot,
    this.deleteShot,
    this.videoView,
    this.save,
    this.share,
  });

  final CameraShot shot;
  final Future<void> Function(Iterable<String> paths)? deleteShot;
  final ShotVideoView? videoView;
  final ShotSave? save;
  final ShotShare? share;

  @override
  State<CameraReviewScreen> createState() => _CameraReviewScreenState();
}

class _CameraReviewScreenState extends State<CameraReviewScreen> {
  late final ResultExit _exit = ResultExit(delete: widget.deleteShot ?? _deleteFromCameraFolder);

  bool get _isVideo => widget.shot is VideoShot;

  @override
  void initState() {
    super.initState();
    _exit.hold();
  }

  @override
  void dispose() {
    _exit.release();
    super.dispose();
  }

  static Future<void> _deleteFromCameraFolder(Iterable<String> paths) async =>
      (await CameraFiles.open()).delete(paths);

  Future<void> _retake() async {
    final leave = await _exit.leave(
      outputs: [widget.shot.path],
      confirm: () => confirmDiscard(context, isVideo: _isVideo, count: 1),
    );
    if (leave && mounted) Navigator.of(context).pop(CameraReviewOutcome.retake);
  }

  Future<void> _save() async {
    try {
      await (widget.save ?? _saveToGallery)(widget.shot.path);
      _exit.markKept();
      HapticFeedback.mediumImpact();
      if (mounted) ToastUtils.show(context, 'Saved to gallery');
    } catch (e) {
      if (mounted) ToastUtils.show(context, 'Could not save: $e', isError: true);
    }
  }

  static Future<void> _saveToGallery(String path) =>
      MediaSaveService.saveOptimizedMediaToGallery([path]);

  Future<void> _share() async {
    final shared = await (widget.share ?? _shareFile)(widget.shot.path);
    if (shared) _exit.markKept();
  }

  static Future<bool> _shareFile(String path) => MediaSaveService.shareFiles([path]);

  /// The file stays: the editor's draft plays from it.
  void _edit() {
    _exit.markKept();
    Navigator.of(context).pop(CameraReviewOutcome.edit);
  }

  @override
  Widget build(BuildContext context) {
    final shot = widget.shot;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_retake());
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // The file as it is, whole: a photo or a video kept wider than
              // the screen is not cropped here, where it is judged.
              if (shot is VideoShot)
                (widget.videoView ?? (path) => _LoopingVideo(path: path))(shot.path)
              else
                Image.file(
                  File(shot.path),
                  key: const ValueKey('camera_review_photo'),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Center(
                    child: Icon(LucideIcons.imageOff, color: AppColors.textSecondary, size: 40),
                  ),
                ),
              const _FootShade(),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ReviewAction(
                          key: const ValueKey('camera_review_retake'),
                          icon: LucideIcons.rotateCcw,
                          label: 'Retake',
                          onTap: _retake,
                        ),
                        _ReviewAction(
                          key: const ValueKey('camera_review_save'),
                          icon: LucideIcons.download,
                          label: 'Save',
                          onTap: _save,
                        ),
                        _ReviewAction(
                          key: const ValueKey('camera_review_share'),
                          icon: LucideIcons.share2,
                          label: 'Share',
                          onTap: _share,
                        ),
                        _ReviewAction(
                          key: const ValueKey('camera_review_edit'),
                          icon: LucideIcons.pencil,
                          label: 'Edit',
                          primary: true,
                          onTap: () async => _edit(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FootShade extends StatelessWidget {
  const _FootShade();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.background.withValues(alpha: 0.7)],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewAction extends StatelessWidget {
  const _ReviewAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  /// White on purple: the step most shots go on to.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(onTap()),
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary ? AppColors.primaryStart : AppColors.surface.withValues(alpha: 0.85),
                ),
                child: Icon(icon, size: 22, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: kInterfaceFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recorded video, playing on a loop the moment it is ready; a tap
/// pauses or plays, and the bar above the actions scrubs.
class _LoopingVideo extends StatefulWidget {
  const _LoopingVideo({required this.path});

  final String path;

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
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
