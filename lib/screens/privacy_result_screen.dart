import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:slimshotai/core/models/history_item.dart';
import 'package:slimshotai/core/services/history_service.dart';
import 'package:slimshotai/core/services/media_save_service.dart';
import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/core/utils/toast_utils.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/widgets/gradient_button.dart';
import 'package:slimshotai/features/privacy/providers/privacy_provider.dart';
import 'package:slimshotai/core/services/ad_service.dart';

class PrivacyResultScreen extends ConsumerStatefulWidget {
  const PrivacyResultScreen({super.key});

  @override
  ConsumerState<PrivacyResultScreen> createState() =>
      _PrivacyResultScreenState();
}

class _PrivacyResultScreenState extends ConsumerState<PrivacyResultScreen> {
  int _selectedIndex = 0;
  bool _historySaved = false;

  @override
  void initState() {
    super.initState();
    AdService.loadInterstitialAd();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveHistory();
    });
  }

  Future<void> _saveHistory() async {
    if (_historySaved) return;
    _historySaved = true;

    final state = ref.read(privacyProvider);
    if (state.outputPaths.isEmpty) return;

    await HistoryService.addItem(
      HistoryItem(
        id: state.outputPaths.join('|'),
        title: state.outputPaths.length == 1
            ? 'Privacy-clean photo'
            : 'Privacy-cleaned ${state.outputPaths.length} photos',
        operation: 'Privacy Strip',
        mediaType: 'image',
        outputPaths: state.outputPaths,
        originalSize: state.originalSize,
        outputSize: state.strippedSize,
        detail: 'Metadata removed',
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(privacyProvider);

    if (state.outputPaths.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selectedPath = state.outputPaths[_selectedIndex];
    final isBatch = state.outputPaths.length > 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child:
                Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: AppColors.primaryStart.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .move(
                      begin: const Offset(0, 0),
                      end: const Offset(-30, 30),
                      duration: 4000.ms,
                      curve: Curves.easeInOutSine,
                    )
                    .blur(
                      begin: const Offset(60, 60),
                      end: const Offset(60, 60),
                    ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(
                            LucideIcons.arrowLeft,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Privacy Report',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: -0.2, end: 0),

                Expanded(
                  flex: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildImagePreview(selectedPath),
                  ),
                ),

                if (isBatch) _buildThumbnailSelector(state),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildReportCard(state, selectedPath),
                ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),

                const SizedBox(height: 16),

                _buildActionButtons(state, selectedPath),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String path) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryStart.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(path), fit: BoxFit.cover),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
            Image.file(File(path), fit: BoxFit.contain),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.shieldCheck,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Metadata Stripped',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn().scale(
      begin: const Offset(0.97, 0.97),
      end: const Offset(1, 1),
    );
  }

  Widget _buildThumbnailSelector(PrivacyState state) {
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        itemCount: state.outputPaths.length,
        itemBuilder: (context, index) {
          final isSelected = index == _selectedIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            child: AnimatedContainer(
              duration: 200.ms,
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryStart
                      : AppColors.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.file(
                  File(state.outputPaths[index]),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReportCard(PrivacyState state, String selectedPath) {
    final originalFileSize = state.inputFiles.isNotEmpty
        ? File(
            state
                .inputFiles[_selectedIndex < state.inputFiles.length
                    ? _selectedIndex
                    : 0]
                .path,
          ).lengthSync()
        : state.originalSize;
    final strippedFileSize = File(selectedPath).lengthSync();

    final chips = [
      (LucideIcons.mapPin, 'GPS'),
      (LucideIcons.camera, 'Camera'),
      (LucideIcons.clock, 'Time'),
      (LucideIcons.user, 'Author'),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ReportStat(
                      label: 'Before',
                      value: FileUtils.formatFileSize(originalFileSize),
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: AppColors.border,
                  ),
                  Expanded(
                    child: _ReportStat(
                      label: 'After',
                      value: FileUtils.formatFileSize(strippedFileSize),
                      color: AppColors.primaryStart,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: chips
                    .map(
                      (c) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryStart.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.border.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                c.$1,
                                color: AppColors.primaryStart,
                                size: 14,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                c.$2,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(PrivacyState state, String selectedPath) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: GradientButton(
              onPress: () {
                AdService.showInterstitialAd(
                  context,
                  onAdDismissed: () async {
                    HapticFeedback.mediumImpact();
                    try {
                      if (state.outputPaths.length > 1) {
                        await MediaSaveService.saveImagesToGallery(
                          state.outputPaths,
                        );
                        if (mounted) {
                          ToastUtils.show(
                            context,
                            '${state.outputPaths.length} photos saved!',
                          );
                        }
                      } else {
                        await MediaSaveService.saveImagesToGallery([
                          selectedPath,
                        ]);
                        if (mounted) {
                          ToastUtils.show(context, 'Saved to gallery!');
                        }
                      }
                    } catch (e) {
                      if (mounted) {
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
              icon: LucideIcons.download,
              title: 'Save${state.outputPaths.length > 1 ? ' All' : ''}',
              borderRadius: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.selectionClick();
                await MediaSaveService.shareFiles(state.outputPaths);
              },
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text(
                'Share',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surfaceLight,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3, end: 0);
  }
}

class _ReportStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ReportStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
