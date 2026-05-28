import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/gradient_button.dart';
import '../core/widgets/compression_loader.dart';
import '../core/widgets/responsive_layout.dart';
import '../features/compression/providers/compression_provider.dart';
import '../features/compression/logic/compression_presets.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/toast_utils.dart';
import 'package:permission_handler/permission_handler.dart';

class CompressImageScreen extends ConsumerStatefulWidget {
  const CompressImageScreen({super.key});

  @override
  ConsumerState<CompressImageScreen> createState() =>
      _CompressImageScreenState();
}

class _CompressImageScreenState extends ConsumerState<CompressImageScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(compressionProvider.notifier).reset();
      _pickImage();
    });
  }

  Future<void> _pickImage() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        ref
            .read(compressionProvider.notifier)
            .setInputFiles(
              images,
              defaultPreset: CompressionPresets.imagePresets[1],
            );
      } else {
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        final isPermission =
            errorStr.contains('photo_access_denied') ||
            errorStr.contains('permission_denied') ||
            errorStr.contains('access_denied');

        if (isPermission) {
          _showPermissionDialog();
        } else {
          ToastUtils.show(context, 'Error picking image: $e', isError: true);
        }
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Permission Required',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'SlimShotAI needs access to your gallery to select photos for compression. Please allow access in settings.',
          style: TextStyle(color: Color(0xFFCBD5E1)),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) context.pop();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
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
                              ...CompressionPresets.imagePresets
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
                          onPress: state.selectedPreset != null
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
