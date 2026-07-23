import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/services/ad_service.dart';
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

class CompressImageScreen extends ConsumerStatefulWidget {
  final List<XFile>? initialImages;

  const CompressImageScreen({super.key, this.initialImages});

  @override
  ConsumerState<CompressImageScreen> createState() =>
      _CompressImageScreenState();
}

class _CompressImageScreenState extends ConsumerState<CompressImageScreen> {
  final MediaPickerService _picker = MediaPickerService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(compressionProvider.notifier).reset();
      final initialImages = widget.initialImages;
      if (initialImages != null && initialImages.isNotEmpty) {
        ref.read(compressionProvider.notifier).setInputFiles(
              initialImages,
              defaultPreset: CompressionPresets.imagePresets[1],
            );
      } else {
        if (mounted) context.pop();
      }
    });
  }

  void _handleCompress() async {
    await ref.read(compressionProvider.notifier).compressImage();

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

  String _formatTargetSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb == mb.roundToDouble()
          ? '${mb.toInt()} MB'
          : '${mb.toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compressionProvider);
    final notifier = ref.read(compressionProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.isProcessing ? 'Compressing Photo...' : 'Configure Photo',
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
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.35,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: state.inputFiles.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      width: MediaQuery.of(context).size.width * 0.7,
                                      margin: EdgeInsets.only(right: index == state.inputFiles.length - 1 ? 0 : 16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(15),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Image.file(File(state.inputFiles[index].path), fit: BoxFit.cover),
                                            BackdropFilter(
                                              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                              child: Container(color: Colors.black.withValues(alpha: 0.4)),
                                            ),
                                            Image.file(File(state.inputFiles[index].path), fit: BoxFit.contain),
                                            if (state.inputFiles.length > 1)
                                              Positioned(
                                                top: 12,
                                                right: 12,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withValues(alpha: 0.5),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: Colors.white.withValues(alpha: 0.15),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(LucideIcons.image, color: Colors.white, size: 12),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        FileUtils.formatFileSize(File(state.inputFiles[index].path).lengthSync()),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ).animate().fadeIn(),

                              const SizedBox(height: 12),

                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    state.inputFiles.length > 1 ? 'Total Batch Size' : 'Original Size',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    FileUtils.formatFileSize(
                                      state.originalSize,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn(),

                              const SizedBox(height: 32),
                            ],

                            if (state.isProcessing) ...[
                              CompressionLoaderOverlay(
                                progress: state.progress,
                                isVideo: false,
                                batchStatus: 'Processing ${state.currentProcessingIndex + 1} of ${state.inputFiles.length}',
                                child: Container(
                                  width: double.infinity,
                                  height:
                                      MediaQuery.of(context).size.height * 0.35,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.file(File(state.inputFiles[state.currentProcessingIndex].path), fit: BoxFit.cover),
                                        BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                          child: Container(color: Colors.black.withValues(alpha: 0.4)),
                                        ),
                                        Image.file(File(state.inputFiles[state.currentProcessingIndex].path), fit: BoxFit.contain),
                                      ],
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
                                children: CompressionPresets.imagePresets.asMap().entries.expand((entry) {
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
                                                  color: isSelected ? AppColors.primaryStart : AppColors.border,
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

                                  if (index == CompressionPresets.imagePresets.length - 1) {
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
                                      value: state.targetImageFormat,
                                      dropdownColor: AppColors.surface,
                                      underline: const SizedBox(),
                                      icon: const Icon(LucideIcons.chevronDown, color: AppColors.textSecondary, size: 16),
                                      items: const [
                                        DropdownMenuItem(value: 'jpg', child: Text('JPG', style: TextStyle(color: Colors.white))),
                                        DropdownMenuItem(value: 'png', child: Text('PNG', style: TextStyle(color: Colors.white))),
                                        DropdownMenuItem(value: 'webp', child: Text('WebP', style: TextStyle(color: Colors.white))),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          notifier.setTargetImageFormat(val);
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
                          title: "Compress Photo",
                          icon: LucideIcons.zap,
                          onPress: state.selectedPreset != null &&
                                  (state.compressionMode !=
                                          CompressionMode.targetSize ||
                                      state.targetImageSizeBytes != null)
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
