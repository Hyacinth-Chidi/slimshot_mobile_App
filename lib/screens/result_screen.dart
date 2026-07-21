import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../core/models/history_item.dart';
import '../core/services/history_service.dart';
import '../core/services/media_save_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/toast_utils.dart';
import '../core/services/ad_service.dart';
import '../core/widgets/before_after_slider.dart';
import '../core/widgets/gradient_button.dart';
import '../core/widgets/responsive_layout.dart';
import '../features/compression/logic/compression_presets.dart';
import '../features/compression/providers/compression_provider.dart';

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
  bool _showCheckmark = true;
  bool _historySaved = false;

  @override
  void initState() {
    super.initState();
    AdService.loadInterstitialAd();
    HapticFeedback.mediumImpact();
    _initVideoPlayer();
    _saveHistory();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showCheckmark = false;
        });
      }
    });
  }

  void _initVideoPlayer() {
    final state = ref.read(compressionProvider);
    if (state.outputPaths.isNotEmpty &&
        MediaSaveService.isVideoPath(state.outputPaths.first)) {
      _videoController =
          VideoPlayerController.file(File(state.outputPaths.first))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {
                  _totalDuration = _videoController!.value.duration;
                });
              }
              _videoController?.setLooping(false);
              _videoController?.addListener(() {
                if (mounted && _videoController!.value.isInitialized) {
                  setState(() {
                    _currentPosition = _videoController!.value.position;
                    if (_videoController!.value.position >=
                        _videoController!.value.duration) {
                      _isVideoPlaying = false;
                    }
                  });
                }
              });
            });
    }
  }

  Future<void> _saveHistory() async {
    if (_historySaved) return;
    _historySaved = true;

    final state = ref.read(compressionProvider);
    if (state.outputPaths.isEmpty) return;

    final isVideo = MediaSaveService.isVideoPath(state.outputPaths.first);
    final detail = state.selectedOutputPresetId != null
        ? 'Quick preset: ${state.selectedOutputPresetId}'
        : state.compressionMode == CompressionMode.targetSize
            ? 'Target size mode'
            : state.selectedPreset?.name ?? 'Compression';

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
    _videoController?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isVideoPlaying = false;
      } else {
        if (_videoController!.value.position >=
            _videoController!.value.duration) {
          _videoController!.seekTo(Duration.zero);
        }
        _videoController!.play();
        _isVideoPlaying = true;
      }
    });
  }

  void _openFullScreen() {
    if (_videoController == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) =>
                _FullScreenPlayer(controller: _videoController!),
          ),
        )
        .then((_) {
          if (mounted) {
            setState(() {
              _isVideoPlaying = _videoController!.value.isPlaying;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compressionProvider);

    if (state.outputPaths.isEmpty) {
      return Scaffold(
        body: Center(
          child: GradientButton(
            title: "Go Home",
            width: 200,
            onPress: () => context.go('/home'),
          ),
        ),
      );
    }

    final ratio = FileUtils.calculateCompressionRatio(
      state.originalSize,
      state.compressedSize,
    );
    final isVideo = MediaSaveService.isVideoPath(state.outputPaths.first);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surfaceLight,
                    AppColors.background,
                    AppColors.background,
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          Positioned(
            top: -60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryStart.withValues(alpha: 0.15),
                      AppColors.success.withValues(alpha: 0.08),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: ResponsiveCenter(
              child: Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _showCheckmark
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 16),
                              Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppColors.primaryStart,
                                          AppColors.primaryEnd,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primaryStart.withValues(alpha: 0.4),
                                          blurRadius: 28,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      LucideIcons.check,
                                      color: Colors.white,
                                      size: 34,
                                    ),
                                  )
                                  .animate()
                                  .scale(
                                    duration: 600.ms,
                                    curve: Curves.elasticOut,
                                    begin: const Offset(0, 0),
                                    end: const Offset(1, 1),
                                  )
                                  .then()
                                  .shimmer(duration: 1500.ms, delay: 500.ms),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    'Ready to Share!',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3, end: 0),

                  const SizedBox(height: 4),

                  Text(
                    state.outputPaths.length == 1
                        ? (isVideo
                              ? 'Your video has been optimized'
                              : 'Your photo has been optimized')
                        : (isVideo
                              ? '${state.outputPaths.length} videos have been optimized'
                              : '${state.outputPaths.length} photos have been optimized'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ).animate().fadeIn(delay: 300.ms),

                  const SizedBox(height: 20),

                  Expanded(
                    flex: 8,
                    child:
                        Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: isVideo
                                  ? _buildVideoPreview()
                                  : _buildImagePreview(
                                      state
                                          .inputFiles[_selectedPreviewIndex]
                                          .path,
                                      state.outputPaths[_selectedPreviewIndex],
                                    ),
                            )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .slideY(begin: 0.2, end: 0),
                  ),

                  if (!isVideo && state.outputPaths.length > 1) ...[
                    const SizedBox(height: 16),
                    _buildThumbnailSelector(state.outputPaths),
                  ],

                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatItem(
                              icon: LucideIcons.file,
                              label: 'Original',
                              value: FileUtils.formatFileSize(
                                state.outputPaths.length > 1 && !isVideo
                                    ? File(
                                        state
                                            .inputFiles[_selectedPreviewIndex]
                                            .path,
                                      ).lengthSync()
                                    : state.originalSize,
                              ),
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: AppColors.border,
                          ),
                          Expanded(
                            child: _StatItem(
                              icon: LucideIcons.zap,
                              label: 'New Size',
                              value: FileUtils.formatFileSize(
                                state.outputPaths.length > 1 && !isVideo
                                    ? File(
                                        state
                                            .outputPaths[_selectedPreviewIndex],
                                      ).lengthSync()
                                    : state.compressedSize,
                              ),
                              color: AppColors.primaryStart,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: AppColors.border,
                          ),
                          Expanded(
                            child: _StatItem(
                              icon: LucideIcons.trendingDown,
                              label: 'Saved',
                              value: '${ratio.toStringAsFixed(0)}%',
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),

                  const Spacer(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: Column(
                      children: [
                        GradientButton(
                          title: "Save to Gallery",
                          icon: LucideIcons.download,
                          onPress: () {
                            AdService.showInterstitialAd(
                              context,
                              onAdDismissed: () async {
                                try {
                                  await MediaSaveService
                                      .saveOptimizedMediaToGallery(
                                    state.outputPaths,
                                  );

                                  HapticFeedback.mediumImpact();
                                  if (context.mounted) {
                                    ToastUtils.show(context, 'Saved to Gallery!');
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ToastUtils.show(
                                      context,
                                      'Error saving: $e',
                                      isError: true,
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: _OutlineButton(
                                title: 'Share',
                                icon: LucideIcons.share2,
                                onTap: () {
                                  if (state.outputPaths.isNotEmpty) {
                                    MediaSaveService.shareFiles(
                                      state.outputPaths,
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _OutlineButton(
                                title: 'New File',
                                icon: LucideIcons.filePlus,
                                onTap: () => context.go('/home'),
                              ),
                            ),
                          ],
                        ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryStart,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            color: AppColors.surface,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                ),

                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _isVideoPlaying ? 0.0 : 1.0,
                    duration: 200.ms,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _isVideoPlaying
                                ? LucideIcons.pause
                                : LucideIcons.play,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 10,
                              ),
                              trackHeight: 2.5,
                              thumbColor: AppColors.primaryStart,
                              activeTrackColor: AppColors.primaryStart,
                              inactiveTrackColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            child: Slider(
                              value: _currentPosition.inMilliseconds
                                  .toDouble()
                                  .clamp(
                                    0,
                                    _totalDuration.inMilliseconds.toDouble(),
                                  ),
                              min: 0.0,
                              max: _totalDuration.inMilliseconds.toDouble(),
                              onChanged: (value) {
                                _videoController!.seekTo(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(_totalDuration),
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _openFullScreen,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              LucideIcons.maximize,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildImagePreview(String beforePath, String afterPath) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return BeforeAfterSlider(
                  key: ValueKey('$beforePath-$afterPath'),
                  beforeImage: File(beforePath),
                  afterImage: File(afterPath),
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              },
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => _openFullScreenImage(beforePath, afterPath),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.maximize,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
                      color: Colors.white,
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

  Widget _buildThumbnailSelector(List<String> outputPaths) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: outputPaths.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final isSelected = index == _selectedPreviewIndex;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPreviewIndex = index;
              });
              HapticFeedback.selectionClick();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryStart
                      : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primaryStart.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(outputPaths[index]), fit: BoxFit.cover),
              ),
            ),
          );
        },
      ),
    );
  }
}


class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color.withValues(alpha: 0.7), size: 16),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _OutlineButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _OutlineButton({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: 120.ms,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: 120.ms,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isPressed
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
                  : const Color(0xFF334155),
              width: 1.5,
            ),
            color: _isPressed
                ? const Color(0xFF1E293B)
                : const Color(0xFF1E293B).withValues(alpha: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: const Color(0xFF94A3B8), size: 18),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFF8FAFC),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
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
