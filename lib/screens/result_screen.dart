import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../core/models/history_item.dart';
import '../core/services/ad_service.dart';
import '../core/services/history_service.dart';
import '../core/services/media_save_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/lucide_icons.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/before_after_slider.dart';
import '../features/compression/logic/compress_labels.dart';
import '../features/compression/providers/compression_provider.dart';
import '../features/compression/widgets/compress_panels.dart';
import '../features/compression/widgets/compress_result_view.dart';
import '../features/compression/widgets/video_frame_thumb.dart';

/// The finished compression. The layout is [CompressResultView]; this owns
/// the player, the history entry and saving.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key});

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  int _selectedPreviewIndex = 0;
  bool _historySaved = false;

  @override
  void initState() {
    super.initState();
    AdService.loadInterstitialAd();
    HapticFeedback.mediumImpact();
    final state = ref.read(compressionProvider);
    if (state.outputPaths.isNotEmpty &&
        MediaSaveService.isVideoPath(state.outputPaths.first)) {
      _openVideo(state.outputPaths.first);
    }
    _saveHistory();
  }

  Future<void> _openVideo(String path) async {
    final old = _videoController;
    old?.removeListener(_onVideoTick);
    final controller = VideoPlayerController.file(File(path));
    setState(() {
      _videoController = controller;
      _isVideoPlaying = false;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    });
    await old?.dispose();
    await controller.initialize();
    if (!mounted || _videoController != controller) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(false);
    controller.addListener(_onVideoTick);
    setState(() => _totalDuration = controller.value.duration);
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (!mounted || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _currentPosition = controller.value.position;
      if (controller.value.position >= controller.value.duration) {
        _isVideoPlaying = false;
      }
    });
  }

  Future<void> _saveHistory() async {
    if (_historySaved) return;
    _historySaved = true;

    final state = ref.read(compressionProvider);
    if (state.outputPaths.isEmpty) return;

    final isVideo = MediaSaveService.isVideoPath(state.outputPaths.first);
    final detail = state.selectedPreset?.name ?? 'Compression';

    await HistoryService.addItem(
      HistoryItem(
        id: state.outputPaths.join('|'),
        title: state.outputPaths.length == 1
            ? (isVideo ? 'Compressed video' : 'Compressed photo')
            : 'Compressed ${state.outputPaths.length} ${isVideo ? 'videos' : 'photos'}',
        operation: 'Compression',
        mediaType: isVideo ? 'video' : 'image',
        outputPaths: state.outputPaths,
        originalSize: state.originalSize,
        outputSize: state.compressedSize,
        detail: detail,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _isVideoPlaying = false;
      } else {
        if (controller.value.position >= controller.value.duration) {
          controller.seekTo(Duration.zero);
        }
        controller.play();
        _isVideoPlaying = true;
      }
    });
  }

  void _openFullScreen() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => _FullScreenPlayer(controller: controller),
          ),
        )
        .then((_) {
          if (mounted) {
            setState(() => _isVideoPlaying = controller.value.isPlaying);
          }
        });
  }

  void _openFullScreenImage(String beforePath, String afterPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return BeforeAfterSlider(
                        key: ValueKey('fullscreen-$beforePath-$afterPath'),
                        beforeImage: File(beforePath),
                        afterImage: File(afterPath),
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: IconButton(
                    icon: const Icon(
                      LucideIcons.x,
                      color: AppColors.textPrimary,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _preview(int index, {required bool isVideo}) {
    final outputs = ref.read(compressionProvider).outputPaths;
    if (index < 0 || index >= outputs.length) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedPreviewIndex = index);
    if (isVideo) _openVideo(outputs[index]);
  }

  void _save(List<String> outputPaths) {
    AdService.showInterstitialAd(
      context,
      onAdDismissed: () async {
        try {
          await MediaSaveService.saveOptimizedMediaToGallery(outputPaths);
          HapticFeedback.mediumImpact();
          if (mounted) ToastUtils.show(context, 'Saved to gallery');
        } catch (e) {
          if (mounted) {
            ToastUtils.show(context, 'Could not save: $e', isError: true);
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compressionProvider);

    if (state.outputPaths.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: SizedBox(
            width: 200,
            child: CompressPrimaryButton(
              label: 'Go home',
              icon: LucideIcons.home,
              onPressed: () => context.go('/home'),
            ),
          ),
        ),
      );
    }

    final outputs = state.outputPaths;
    final isVideo = MediaSaveService.isVideoPath(outputs.first);
    final index = _selectedPreviewIndex.clamp(0, outputs.length - 1);
    final controller = _videoController;
    final videoReady = controller != null && controller.value.isInitialized;

    final Widget preview;
    final double? aspect;
    if (isVideo) {
      aspect = videoReady ? controller.value.aspectRatio : null;
      preview = ResultVideoFrame(
        video: videoReady ? VideoPlayer(controller) : null,
        aspectRatio: aspect ?? 16 / 9,
        isPlaying: _isVideoPlaying,
        position: _currentPosition,
        duration: _totalDuration,
        onTogglePlay: _togglePlayPause,
        onSeek: (to) => controller?.seekTo(to),
        onFullScreen: _openFullScreen,
      );
    } else {
      aspect = null;
      final before = index < state.inputFiles.length
          ? state.inputFiles[index].path
          : outputs[index];
      final after = outputs[index];
      preview = ResultPhotoFrame(
        compare: LayoutBuilder(
          builder: (context, constraints) => BeforeAfterSlider(
            key: ValueKey('$before-$after'),
            beforeImage: File(before),
            afterImage: File(after),
            width: constraints.maxWidth,
            height: constraints.maxHeight,
          ),
        ),
        onFullScreen: () => _openFullScreenImage(before, after),
      );
    }

    final skipped = state.skippedCompressions;
    return CompressResultView(
      isVideo: isVideo,
      count: outputs.length,
      beforeBytes: state.originalSize,
      afterBytes: state.compressedSize,
      keptAsItWas: skipped.isNotEmpty && skipped.every((s) => s),
      preview: preview,
      previewAspectRatio: aspect,
      quality: state.selectedPreset?.name,
      format: formatName(
          isVideo ? state.targetVideoFormat : state.targetImageFormat),
      locationRemoved: state.removeMetadata,
      thumbnails: [
        for (final path in outputs)
          isVideo
              ? VideoFrameThumb(key: ValueKey(path), path: path)
              : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 160),
      ],
      previewIndex: index,
      onPreview: (i) => _preview(i, isVideo: isVideo),
      onClose: () => context.go('/home'),
      onSave: () => _save(outputs),
      onShare: () => MediaSaveService.shareFiles(outputs),
      onCompressAnother: () => context.go('/home'),
    );
  }
}

class _FullScreenPlayer extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullScreenPlayer({required this.controller});

  @override
  State<_FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends State<_FullScreenPlayer> {
  bool _isPlaying = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.controller.value.isPlaying;

    Future.delayed(3.seconds, () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });

    widget.controller.addListener(_videoListener);
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        if (widget.controller.value.position >=
            widget.controller.value.duration) {
          _isPlaying = false;
          _showControls = true;
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
        _isPlaying = false;
        _showControls = true;
      } else {
        if (widget.controller.value.position >=
            widget.controller.value.duration) {
          widget.controller.seekTo(Duration.zero);
        }
        widget.controller.play();
        _isPlaying = true;
        Future.delayed(2.seconds, () {
          if (mounted && _isPlaying) setState(() => _showControls = false);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),

            if (_showControls)
              Center(
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ).animate().fadeIn(),

            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.chevronLeft,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().slideY(begin: -1, end: 0),

            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(widget.controller.value.position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              trackHeight: 2,
                              thumbColor: AppColors.primaryStart,
                              activeTrackColor: AppColors.primaryStart,
                              inactiveTrackColor: Colors.white.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            child: Slider(
                              value: widget
                                  .controller
                                  .value
                                  .position
                                  .inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    widget
                                        .controller
                                        .value
                                        .duration
                                        .inMilliseconds
                                        .toDouble(),
                                  ),
                              min: 0.0,
                              max: widget
                                  .controller
                                  .value
                                  .duration
                                  .inMilliseconds
                                  .toDouble(),
                              onChanged: (value) {
                                widget.controller.seekTo(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(widget.controller.value.duration),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            LucideIcons.minimize,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().slideY(begin: 1, end: 0),
          ],
        ),
      ),
    );
  }
}
