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

import 'package:slimshotai/core/services/media_picker_service.dart';
import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/core/utils/toast_utils.dart';
import 'package:slimshotai/core/widgets/compression_loader.dart';
import 'package:slimshotai/core/widgets/permission_dialog.dart';
import 'package:slimshotai/features/privacy/providers/privacy_provider.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  final List<XFile>? initialImages;

  const PrivacyScreen({super.key, this.initialImages});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  final MediaPickerService _picker = MediaPickerService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(privacyProvider.notifier).reset();
      final initialImages = widget.initialImages;
      if (initialImages != null && initialImages.isNotEmpty) {
        ref.read(privacyProvider.notifier).setInputFiles(initialImages);
      } else {
        if (mounted) context.pop();
      }
    });
  }

  Future<void> _pickImages() async {
    try {
      final images = await _picker.pickImages();
      if (images.isNotEmpty) {
        await ref.read(privacyProvider.notifier).setInputFiles(images);
      } else {
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        if (MediaPickerService.isPermissionError(e)) {
          _showPermissionDialog();
        } else {
          ToastUtils.show(context, 'Error picking image: $e', isError: true);
        }
      }
    }
  }

  void _showPermissionDialog() {
    PermissionDialog.showGalleryAccessRequired(
      context: context,
      message: 'SlimShotAI needs access to your gallery to select photos.',
      onCancel: () {
        if (mounted) context.pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(privacyProvider);

    ref.listen<PrivacyState>(privacyProvider, (previous, next) {
      if (previous?.isProcessing == true &&
          !next.isProcessing &&
          next.outputPaths.isNotEmpty &&
          next.error == null) {
        context.push('/privacy/result');
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
            left: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
              begin: const Offset(0, 0),
              end: const Offset(30, 30),
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
                        'Privacy Strip',
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

                        if (!state.isProcessing) _buildRemovedDataCard(),

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


  Widget _buildPreviewGrid(PrivacyState state) {
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
          height: MediaQuery.of(context).size.height * 0.32,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: state.inputFiles.length,
            itemBuilder: (context, index) {
              final file = File(state.inputFiles[index].path);
              final fileSize = file.lengthSync();
              return Container(
                width: MediaQuery.of(context).size.width * 0.65,
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
                      if (state.inputFiles.length > 1)
                        Positioned(
                          top: 10,
                          right: 10,
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
                              ),
                            ),
                            child: Text(
                              FileUtils.formatFileSize(fileSize),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
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

  Widget _buildProcessingView(PrivacyState state) {
    return CompressionLoaderOverlay(
      progress: state.progress,
      isVideo: false,
      batchStatus:
          'Stripping ${state.currentProcessingIndex + 1} of ${state.inputFiles.length}',
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

  Widget _buildRemovedDataCard() {
    final items = [
      (LucideIcons.mapPin, 'GPS Location'),
      (LucideIcons.camera, 'Camera Info'),
      (LucideIcons.clock, 'Timestamps'),
      (LucideIcons.user, 'Author Data'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data to remove',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (item) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF334155).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$1,
                        color: const Color(0xFF6366F1),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.$2,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildStatsRow(PrivacyState state) {
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

  Widget _buildActionButtons(PrivacyState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                ref.read(privacyProvider.notifier).stripMetadata();
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
              child: Text(
                'Strip Metadata from ${state.inputFiles.length} Photo${state.inputFiles.length > 1 ? 's' : ''}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
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
