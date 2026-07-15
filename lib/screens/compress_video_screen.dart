import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/services/media_picker_service.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/gradient_button.dart';
import '../core/widgets/compression_loader.dart';
import '../core/widgets/permission_dialog.dart';
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
    ref
        .read(compressionProvider.notifier)
        .setInputFiles(
          [video],
          defaultPreset: CompressionPresets.videoPresets[1],
        );
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

  String _formatTargetSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb == mb.roundToDouble()
          ? '${mb.toInt()} MB'
          : '${mb.toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  void _showCustomTargetSizeDialog(CompressionNotifier notifier) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Custom Target Size',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Size in MB',
            labelStyle: TextStyle(color: AppColors.textSecondary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primaryStart),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) return;
              final bytes = (value * 1024 * 1024).round();
              notifier.setTargetVideoSize(bytes);
              Navigator.pop(context);
            },
            child: const Text(
              'Use Size',
              style: TextStyle(
                color: AppColors.primaryStart,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetSizeSelector(
    CompressionState state,
    CompressionNotifier notifier,
  ) {
    final isTargetMode = state.compressionMode == CompressionMode.targetSize;
    const targetSizes = CompressionPresets.targetVideoSizes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTargetMode ? AppColors.primaryStart : AppColors.border,
          width: isTargetMode ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.gauge,
                  color: AppColors.primaryStart,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Size',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Compress under a specific limit',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isTargetMode,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  if (value) {
                    notifier.setTargetVideoSize(
                      state.targetVideoSizeBytes ?? targetSizes[1],
                    );
                  } else {
                    notifier.usePresetCompression();
                  }
                },
                activeTrackColor: AppColors.primaryStart,
                inactiveTrackColor: const Color(0xFF334155),
              ),
            ],
          ),
          if (isTargetMode) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...targetSizes.map((size) {
                  final selected = state.targetVideoSizeBytes == size;
                  return ChoiceChip(
                    label: Text(_formatTargetSize(size)),
                    selected: selected,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      notifier.setTargetVideoSize(size);
                    },
                    selectedColor:
                        AppColors.primaryStart.withValues(alpha: 0.25),
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color:
                          selected ? AppColors.primaryStart : AppColors.border,
                    ),
                  );
                }),
                ActionChip(
                  label: Text(
                    state.targetVideoSizeBytes != null &&
                            !targetSizes.contains(state.targetVideoSizeBytes)
                        ? 'Custom: ${_formatTargetSize(state.targetVideoSizeBytes!)}'
                        : 'Custom',
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _showCustomTargetSizeDialog(notifier);
                  },
                  backgroundColor: AppColors.surfaceLight,
                  labelStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  side: const BorderSide(color: AppColors.border),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Very small targets may fail for long or high-resolution videos.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 260.ms);
  }

  Widget _buildQuickPresetSelector(
    CompressionState state,
    CompressionNotifier notifier,
  ) {
    final metadata = state.videoMetadata;
    final suggestion = metadata != null && metadata.durationSecs > 60
        ? 'Suggested: Save Storage for longer videos.'
        : 'Suggested: WhatsApp for quick sharing.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Presets',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ).animate().fadeIn(delay: 80.ms),
        const SizedBox(height: 8),
        Text(
          suggestion,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 14),
        ...CompressionPresets.videoOutputPresets.map((preset) {
          final isSelected = state.selectedOutputPresetId == preset.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.applyOutputPreset(preset);
              },
              child: AnimatedContainer(
                duration: 180.ms,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryStart.withValues(alpha: 0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        isSelected ? AppColors.primaryStart : AppColors.border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryStart
                            : AppColors.surfaceLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        preset.icon,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            preset.description,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        LucideIcons.checkCircle2,
                        color: AppColors.primaryStart,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    ).animate().fadeIn(delay: 120.ms);
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
                                            0.35,
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
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                                                  borderRadius: BorderRadius.circular(8),
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
                                        0.35,
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
                                batchStatus: 'Processing ${state.currentProcessingIndex + 1} of ${state.inputFiles.length}',
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
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _editCurrentVideo,
                                  icon: const Icon(LucideIcons.scissors),
                                  label: const Text('Edit Before Compression'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    side: const BorderSide(
                                      color: AppColors.primaryStart,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ).animate().fadeIn(delay: 80.ms),
                              const SizedBox(height: 22),
                              _buildQuickPresetSelector(state, notifier),
                              const SizedBox(height: 22),
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
                              ...CompressionPresets.videoPresets
                                  .map((preset) {
                                    final isSelected =
                                        state.selectedPreset?.id == preset.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          notifier.selectPreset(preset);
                                        },
                                        child: AnimatedContainer(
                                          duration: 200.ms,
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppColors.primaryStart
                                                      .withValues(alpha: 0.15)
                                                : AppColors.surface,
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.primaryStart
                                                  : AppColors.border,
                                              width: isSelected ? 2 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? AppColors.primaryStart
                                                      : AppColors.surfaceLight,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  preset.icon,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : AppColors.textSecondary,
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            preset.name,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 16,
                                                              color: isSelected
                                                                  ? Colors.white
                                                                  : AppColors
                                                                        .textPrimary,
                                                            ),
                                                          ),
                                                        ),
                                                        if (preset.id ==
                                                            'smart') ...[
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: AppColors
                                                                  .primaryStart
                                                                  .withValues(
                                                                    alpha: 0.2,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                            ),
                                                            child: const Text(
                                                              'Recommended',
                                                              style: TextStyle(
                                                                color: AppColors
                                                                    .primaryStart,
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                    Text(
                                                      preset.description,
                                                      style: const TextStyle(
                                                        color: AppColors
                                                            .textSecondary,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '~${preset.expectedCompression} smaller',
                                                      style: const TextStyle(
                                                        color: AppColors
                                                            .primaryStart,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(
                                                  LucideIcons.checkCircle2,
                                                  color: AppColors.primaryStart,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  })
                                  .toList()
                                  .animate(interval: 50.ms)
                                  .fadeIn(duration: 400.ms, delay: 200.ms)
                                  .slideY(
                                    begin: 0.1,
                                    end: 0,
                                    curve: Curves.easeOutQuad,
                                  ),

                              const SizedBox(height: 8),
                              _buildTargetSizeSelector(state, notifier),

                              const SizedBox(height: 24),
                              const Text(
                                'Output Settings',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ).animate().fadeIn(delay: 300.ms),
                              const SizedBox(height: 16),
                              
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                        color: AppColors.primaryStart.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(LucideIcons.shield, color: AppColors.primaryStart, size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Privacy Mode', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          Text('Remove location & EXIF data', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                                      inactiveTrackColor: const Color(0xFF334155),
                                    ),
                                  ],
                                ),
                              ).animate().fadeIn(delay: 350.ms),
                              
                              const SizedBox(height: 12),
                              
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                        color: AppColors.primaryStart.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(LucideIcons.fileType, color: AppColors.primaryStart, size: 20),
                                    ),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Text('Output Format', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                    DropdownButton<String>(
                                      value: state.targetVideoFormat,
                                      dropdownColor: AppColors.surface,
                                      underline: const SizedBox(),
                                      icon: const Icon(LucideIcons.chevronDown, color: AppColors.textSecondary, size: 16),
                                      items: const [
                                        DropdownMenuItem(value: 'mp4', child: Text('MP4', style: TextStyle(color: Colors.white))),
                                        DropdownMenuItem(value: 'webm', child: Text('WebM', style: TextStyle(color: Colors.white))),
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
                          onPress: state.selectedPreset != null &&
                                  (state.compressionMode !=
                                          CompressionMode.targetSize ||
                                      state.targetVideoSizeBytes != null)
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
