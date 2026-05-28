import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/core/utils/toast_utils.dart';
import 'package:slimshotai/core/widgets/compression_loader.dart';
import 'package:slimshotai/features/convert/providers/convert_provider.dart';

class ConvertScreen extends ConsumerStatefulWidget {
  const ConvertScreen({super.key});

  @override
  ConsumerState<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends ConsumerState<ConvertScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(convertProvider.notifier).reset();
      _pickImages();
    });
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        await ref.read(convertProvider.notifier).setInputFiles(images);
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
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              'Permission Required',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'SlimShotAI needs access to your gallery to select photos.',
              style: TextStyle(color: Color(0xFFCBD5E1)),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                  style: TextStyle(color: Color(0xFF6366F1)),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(convertProvider);

    ref.listen<ConvertState>(convertProvider, (previous, next) {
      if (previous?.isProcessing == true &&
          !next.isProcessing &&
          next.outputPaths.isNotEmpty &&
          next.error == null) {
        context.push('/convert/result');
      }
      if (next.error != null && mounted) {
        ToastUtils.show(context, next.error!, isError: true);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
              begin: const Offset(0, 0),
              end: const Offset(-30, 30),
              duration: 4500.ms,
              curve: Curves.easeInOutSine,
            ).blur(begin: const Offset(60, 60), end: const Offset(60, 60)),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: const Icon(
                            LucideIcons.arrowLeft,
                            color: Color(0xFF94A3B8),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Format Converter',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF8FAFC),
                        ),
                      ),
                    ],
                  ).animate().fadeIn().slideY(begin: -0.2, end: 0),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state.inputFiles.isNotEmpty && !state.isProcessing)
                          _buildPreviewGrid(state),

                        if (state.isProcessing) _buildProcessingView(state),

                        const SizedBox(height: 24),

                        if (!state.isProcessing) _buildFormatSelector(state),

                        const SizedBox(height: 24),

                        if (state.inputFiles.isNotEmpty && !state.isProcessing)
                          _buildStatsRow(state),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

                if (!state.isProcessing && state.inputFiles.isNotEmpty)
                  _buildActionButtons(state),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewGrid(ConvertState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${state.inputFiles.length} Photo${state.inputFiles.length > 1 ? 's' : ''} Selected',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF94A3B8),
              ),
            ),
            GestureDetector(
              onTap: _pickImages,
              child: Text(
                'Change',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6366F1),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.28,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: state.inputFiles.length,
            itemBuilder: (context, index) {
              final file = File(state.inputFiles[index].path);
              final fileSize = file.lengthSync();
              final ext =
                  state.inputFiles[index].path.split('.').last.toUpperCase();
              return Container(
                width: MediaQuery.of(context).size.width * 0.6,
                margin: EdgeInsets.only(
                  right: index == state.inputFiles.length - 1 ? 0 : 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(file, fit: BoxFit.cover),
                      BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.4),
                        ),
                      ),
                      Image.file(file, fit: BoxFit.contain),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ext,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      if (state.inputFiles.length > 1)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              FileUtils.formatFileSize(fileSize),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
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
      ],
    );
  }

  Widget _buildProcessingView(ConvertState state) {
    return CompressionLoaderOverlay(
      progress: state.progress,
      isVideo: false,
      batchStatus:
          'Converting ${state.currentProcessingIndex + 1} of ${state.inputFiles.length}',
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.35,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(state.inputFiles[state.currentProcessingIndex].path),
                fit: BoxFit.cover,
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(color: Colors.black.withValues(alpha: 0.5)),
              ),
              Image.file(
                File(state.inputFiles[state.currentProcessingIndex].path),
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn();
  }

  Widget _buildFormatSelector(ConvertState state) {
    final formats = [
      ('webp', 'WebP', 'Best for web & sharing'),
      ('jpg', 'JPG', 'Universal compatibility'),
      ('png', 'PNG', 'Lossless transparency'),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF334155).withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Convert to',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF8FAFC),
                ),
              ),
              const SizedBox(height: 12),
              ...formats.map((f) {
                final isSelected = state.targetFormat == f.$1;
                return GestureDetector(
                  onTap: () =>
                      ref.read(convertProvider.notifier).setTargetFormat(f.$1),
                  child: AnimatedContainer(
                    duration: 150.ms,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                          : const Color(0xFF0F172A).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6366F1).withValues(alpha: 0.6)
                            : const Color(0xFF334155).withValues(alpha: 0.5),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6366F1).withValues(alpha: 0.15)
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              f.$2,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.$2,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              Text(
                                f.$3,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            LucideIcons.checkCircle,
                            color: Color(0xFF6366F1),
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildStatsRow(ConvertState state) {
    final label =
        state.inputFiles.length > 1 ? 'Total Batch Size' : 'Original Size';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8))),
        Text(
          FileUtils.formatFileSize(state.originalSize),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFF8FAFC),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildActionButtons(ConvertState state) {
    final srcFormat = state.sourceFormat.toUpperCase();
    final dstFormat = state.targetFormat.toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ref.read(convertProvider.notifier).convertFiles();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.fileArchive, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Convert ${state.inputFiles.length} Photo${state.inputFiles.length > 1 ? 's' : ''}: $srcFormat → $dstFormat',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, end: 0);
  }
}
