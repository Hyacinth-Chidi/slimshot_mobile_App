import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../core/services/ad_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../features/compression/logic/compression_presets.dart';
import '../features/compression/providers/compression_provider.dart';
import '../features/compression/widgets/compress_video_view.dart';
import '../features/compression/widgets/video_frame_thumb.dart';

/// Compress one video, or several shared from another app. The layout is
/// [CompressVideoView]; this owns the player and the provider.
class CompressVideoScreen extends ConsumerStatefulWidget {
  const CompressVideoScreen({super.key, this.initialVideos = const []});

  final List<XFile> initialVideos;

  @override
  ConsumerState<CompressVideoScreen> createState() =>
      _CompressVideoScreenState();
}

class _CompressVideoScreenState extends ConsumerState<CompressVideoScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoPlaying = false;

  /// Which of several videos plays in the preview.
  int _previewIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(compressionProvider.notifier).reset();
      final videos = widget.initialVideos;
      if (videos.isNotEmpty) {
        _useVideos(videos);
      } else {
        _leave();
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  /// Back where the user came from — or home, when the screen was opened
  /// from the share sheet and has nothing beneath it.
  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
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
    } else {
      await controller.dispose();
    }
  }

  Future<void> _useVideos(List<XFile> videos) async {
    ref.read(compressionProvider.notifier).setInputFiles(
          videos,
          defaultPreset: CompressionPresets.videoPresets[1],
        );
    await _initVideoController(File(videos.first.path));
    ref.read(compressionProvider.notifier).analyzeFirstVideo();
  }

  Future<void> _preview(int index) async {
    final files = ref.read(compressionProvider).inputFiles;
    if (index < 0 || index >= files.length) return;
    setState(() {
      _previewIndex = index;
      _isVideoPlaying = false;
    });
    await _initVideoController(File(files[index].path));
  }

  void _toggleVideoPlay() {
    final controller = _videoController;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _isVideoPlaying = false;
      } else {
        controller.play();
        _isVideoPlaying = true;
      }
    });
  }

  Future<void> _handleCompress() async {
    // Compressing replaces the preview with the progress; a playing video
    // would carry on under it.
    if (_isVideoPlaying) _toggleVideoPlay();
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

  void _selectPreset(CompressionPreset preset) {
    final notifier = ref.read(compressionProvider.notifier);
    final selected = ref.read(compressionProvider).selectedPreset;
    if (preset.isPro && selected?.id != preset.id) {
      // With ads off this grants at once (`AdService.enabled`).
      AdService.showRewardedAd(
        context,
        onRewardEarned: () {
          if (mounted) notifier.selectPreset(preset);
        },
        onFailed: () {
          if (mounted) {
            ToastUtils.show(
              context,
              'Check your connection to unlock ${preset.name}.',
              isWarning: true,
            );
          }
        },
      );
    } else {
      notifier.selectPreset(preset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compressionProvider);
    final notifier = ref.read(compressionProvider.notifier);
    final controller = _videoController;
    final ready = controller != null && controller.value.isInitialized;

    if (state.inputFiles.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryStart),
        ),
      );
    }

    return CompressVideoView(
      state: state,
      preview: ready
          ? VideoPlayer(controller)
          : const Center(
              child: CircularProgressIndicator(color: AppColors.primaryStart),
            ),
      previewAspectRatio: ready ? controller.value.aspectRatio : null,
      isPlaying: _isVideoPlaying,
      onTogglePlay: _toggleVideoPlay,
      onBack: _leave,
      onSelectPreset: _selectPreset,
      onToggleWhatsApp: notifier.toggleWhatsAppOptimize,
      onToggleRemoveLocation: notifier.toggleRemoveMetadata,
      onFormat: notifier.setTargetVideoFormat,
      onCompress: _handleCompress,
      onCancel: notifier.cancelCompression,
      thumbnails: [
        for (final file in state.inputFiles)
          VideoFrameThumb(key: ValueKey(file.path), path: file.path),
      ],
      previewIndex: _previewIndex,
      onPreview: _preview,
    );
  }
}
