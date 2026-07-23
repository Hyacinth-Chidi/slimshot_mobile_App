import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/services/ad_service.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/gradient_button.dart';
import '../core/widgets/compression_loader.dart';

import '../core/widgets/responsive_layout.dart';
import '../features/compression/providers/compression_provider.dart';
import '../features/compression/logic/compression_presets.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/toast_utils.dart';

class CompressVideoScreen extends ConsumerStatefulWidget {
  final XFile? initialVideo;

  const CompressVideoScreen({super.key, this.initialVideo});

  @override
  ConsumerState<CompressVideoScreen> createState() =>
      _CompressVideoScreenState();
}

class _CompressVideoScreenState extends ConsumerState<CompressVideoScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(compressionProvider.notifier).reset();
      final initialVideo = widget.initialVideo;
      if (initialVideo != null) {
        _useVideo(initialVideo);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pop();
        });
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initVideoController(File file) async {
    final oldController = _videoController;
    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    await oldController?.dispose();
    if (mounted) {
      setState(() {
        _videoController = controller;
        _isVideoPlaying = false;
      });
    }
  }

  Future<void> _useVideo(XFile video) async {
    ref.read(compressionProvider.notifier).setInputFiles([
      video,
    ], defaultPreset: CompressionPresets.videoPresets[1]);
    await _initVideoController(File(video.path));
    ref.read(compressionProvider.notifier).analyzeFirstVideo();
  }

  void _toggleVideoPlay() {
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
        _isVideoPlaying = false;
      } else {
        _videoController!.play();
        _isVideoPlaying = true;
      }
    });
  }

  void _handleCompress() async {
    await ref.read(compressionProvider.notifier).compressVideo();

    if (!mounted) return;
    final state = ref.read(compressionProvider);
    if (state.inputFiles.isEmpty) return;
    if (state.outputPaths.isNotEmpty &&
        !state.isProcessing &&
        state.error == null) {
      context.push('/result');
    } else if (state.error != null) {
      ToastUtils.show(context, state.error!, isError: true);
    }
  }

  void _editCurrentVideo() {
    final state = ref.read(compressionProvider);
    if (state.inputFiles.isEmpty) return;
    context.push('/edit/video', extra: state.inputFiles.first);
  }


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compressionProvider);
    final notifier = ref.read(compressionProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.isProcessing ? 'Compressing Video...' : 'Configure Video',
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: state.inputFiles.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ResponsiveCenter(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!state.isProcessing) ...[
                              if (_videoController != null &&
                                  _videoController!.value.isInitialized)
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF334155,
                                      ), // slate-700
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF8B5CF6,
                                        ).withValues(alpha: 0.15),
                                        blurRadius: 24,
                                        spreadRadius: -4,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(19),
                                    child: Container(
                                      color: const Color(
                                        0xFF0F172A,
                                      ), // slate-900 bg
                                      constraints: BoxConstraints(
                                        maxHeight:
                                            MediaQuery.of(context).size.height *
                                            0.25,
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          AspectRatio(
                                            aspectRatio: _videoController!
                                                .value
                                                .aspectRatio,
                                            child: FittedBox(
                                              fit: BoxFit.contain,
                                              child: SizedBox(
                                                width: _videoController!
                                                    .value
                                                    .size
                                                    .width,
                                                height: _videoController!
                                                    .value
                                                    .size
                                                    .height,
                                                child: VideoPlayer(
                                                  _videoController!,
                                                ),
                                              ),
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
                                                      Colors.black.withValues(
                                                        alpha: 0.5,
                                                      ),
                                                    ],
                                                    stops: const [
                                                      0.0,
                                                      0.6,
                                                      1.0,
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _toggleVideoPlay,
                                            child: Container(
                                              color: Colors.transparent,
                                              alignment: Alignment.center,
                                              child: AnimatedOpacity(
                                                opacity: _isVideoPlaying
                                                    ? 0.0
                                                    : 1.0,
                                                duration: 200.ms,
                                                child: Container(
                                                  width: 64,
                                                  height: 64,
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.6),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.3,
                                                          ),
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: const Icon(
                                                    LucideIcons.play,
                                                    color: Colors.white,
                                                    size: 32,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 12,
                                            right: 12,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.7,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.1),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    LucideIcons.hardDrive,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.7),
                                                    size: 12,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    FileUtils.formatFileSize(
                                                      state.originalSize,
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (state.inputFiles.length > 1)
                                            Positioned(
                                              top: 12,
                                              right: 12,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF8B5CF6,
                                                  ).withValues(alpha: 0.9),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '${state.inputFiles.length} Videos',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ).animate().fadeIn()
                              else
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight:
                                        MediaQuery.of(context).size.height *
                                        0.25,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primaryStart,
                                        ),
                                      ),
                                    ),
                                  ),
                                ).animate().fadeIn(),
                            ],
                            if (state.isProcessing) ...[
                              CompressionLoaderOverlay(
                                progress: state.progress,
                                isVideo: true,
                                batchStatus:
                                    'Processing ${state.currentProcessingIndex + 1} of ${state.inputFiles.length}',
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight:
                                        MediaQuery.of(context).size.height *
                                        0.45,
                                  ),
                                  child:
                                      _videoController != null &&
                                          _videoController!.value.isInitialized
                                      ? AspectRatio(
                                          aspectRatio: _videoController!
                                              .value
                                              .aspectRatio,
                                          child: VideoPlayer(_videoController!),
                                        )
                                      : AspectRatio(
                                          aspectRatio: 16 / 9,
                                          child: Container(
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                ),
                              ).animate().fadeIn(),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: () {
                                    ref
                                        .read(compressionProvider.notifier)
                                        .cancelCompression();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF94A3B8),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: const BorderSide(
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      LucideIcons.messageCircle,
                                      color: Color(0xFF25D366),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    const Expanded(
                                      child: Text(
                                        'Optimize for WhatsApp',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: state.whatsAppOptimize,
                                      onChanged: (_) {
                                        HapticFeedback.selectionClick();
                                        notifier.toggleWhatsAppOptimize();
                                      },
                                      activeTrackColor: const Color(0xFF25D366),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(),
                              const SizedBox(height: 24),

                              const Text(
                                    'Compression Mode',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                  .animate()
                                  .fadeIn(duration: 400.ms, delay: 100.ms)
                                  .slideY(
                                    begin: 0.1,
                                    end: 0,
                                    curve: Curves.easeOutQuad,
                                  ),
                              const SizedBox(height: 16),
                              Row(
                                children: CompressionPresets.videoPresets.asMap().entries.expand((entry) {
                                  final index = entry.key;
                                  final preset = entry.value;
                                  final isSelected = state.selectedPreset?.id == preset.id;
                                  
                                  final card = Expanded(
                                    child: GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          if (preset.isPro && !isSelected) {
                                            AdService.showRewardedAd(
                                              context,
                                              onRewardEarned: () {
                                                if (context.mounted) {
                                                  notifier.selectPreset(preset);
                                                  ToastUtils.show(context, '${preset.name} unlocked!', isError: false);
                                                }
                                              },
                                              onFailed: () {
                                                if (context.mounted) {
                                                  ToastUtils.show(
                                                    context, 
                                                    'Please check your internet connection to unlock Pro features.', 
                                                    isWarning: true,
                                                    title: 'No Internet Connection',
                                                  );
                                                }
                                              },
                                            );
                                          } else {
                                            notifier.selectPreset(preset);
                                          }
                                        },
                                        child: Stack(
                                          children: [
                                            AnimatedContainer(
                                              duration: 200.ms,
                                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? AppColors.primaryStart.withValues(alpha: 0.15)
                                                    : AppColors.surface,
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? AppColors.primaryStart
                                                      : AppColors.border,
                                                  width: isSelected ? 2 : 1,
                                                ),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(
                                                      gradient: isSelected
                                                          ? const LinearGradient(
                                                              colors: [AppColors.primaryStart, AppColors.primaryEnd],
                                                              begin: Alignment.topLeft,
                                                              end: Alignment.bottomRight,
                                                            )
                                                          : null,
                                                      color: isSelected ? null : AppColors.surfaceLight,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Icon(
                                                      preset.icon,
                                                      color: isSelected ? Colors.white : AppColors.textSecondary,
                                                      size: 24,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    preset.name.replaceAll(' ', '\n'),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      height: 1.1,
                                                      color: isSelected ? Colors.white : AppColors.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isSelected ? AppColors.primaryStart.withValues(alpha: 0.2) : AppColors.surfaceLight,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      '-${preset.expectedCompression.replaceAll('~', '').replaceAll('smaller', '').trim()}',
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        color: isSelected ? AppColors.primaryStart : AppColors.textSecondary,
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Visibility(
                                                    visible: preset.isPro,
                                                    maintainSize: true,
                                                    maintainAnimation: true,
                                                    maintainState: true,
                                                    child: const Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(LucideIcons.playCircle, size: 10, color: Color(0xFFD946EF)),
                                                        SizedBox(width: 4),
                                                        Text(
                                                          'Watch ad\nto unlock',
                                                          textAlign: TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: 8,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFFD946EF),
                                                            height: 1.1,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (preset.isPro)
                                              Positioned(
                                                top: 0,
                                                left: 0,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: const BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [Color(0xFF8B5CF6), Color(0xFFD946EF)],
                                                    ),
                                                    borderRadius: BorderRadius.only(
                                                      topLeft: Radius.circular(16),
                                                      bottomRight: Radius.circular(8),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'PRO',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.w900,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  );

                                  if (index == CompressionPresets.videoPresets.length - 1) {
                                    return [card];
                                  }
                                  return [card, const SizedBox(width: 8)];
                                }).toList(),
                              )
                              .animate()
                              .fadeIn(duration: 400.ms, delay: 200.ms)
                              .slideY(
                                begin: 0.1,
                                end: 0,
                                curve: Curves.easeOutQuad,
                              ),

                              const SizedBox(height: 16),
                              const Text(
                                'Output Settings',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ).animate().fadeIn(delay: 300.ms),
                              const SizedBox(height: 16),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryStart
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.shield,
                                        color: AppColors.primaryStart,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Privacy Mode',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          Text(
                                            'Remove location & EXIF data',
                                            style: TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: state.removeMetadata,
                                      onChanged: (val) {
                                        HapticFeedback.selectionClick();
                                        notifier.toggleRemoveMetadata();
                                      },
                                      activeTrackColor: AppColors.primaryStart,
                                      inactiveTrackColor: const Color(
                                        0xFF334155,
                                      ),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(delay: 350.ms),

                              const SizedBox(height: 12),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryStart
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        LucideIcons.fileType,
                                        color: AppColors.primaryStart,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Text(
                                        'Output Format',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: state.targetVideoFormat,
                                      dropdownColor: AppColors.surface,
                                      underline: const SizedBox(),
                                      icon: const Icon(
                                        LucideIcons.chevronDown,
                                        color: AppColors.textSecondary,
                                        size: 16,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'mp4',
                                          child: Text(
                                            'MP4',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'webm',
                                          child: Text(
                                            'WebM',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          notifier.setTargetVideoFormat(val);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(delay: 400.ms),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!state.isProcessing)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                          border: Border(
                            top: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: GradientButton(
                          title: "Start Compression",
                          icon: LucideIcons.zap,
                          onPress:
                              state.selectedPreset != null
                              ? _handleCompress
                              : null,
                          isLoading: state.isProcessing,
                        ),
                      ).animate().slideY(begin: 1, end: 0),
                  ],
                ),
              ),
            ),
    );
  }
}
