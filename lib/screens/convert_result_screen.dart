import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/core/utils/toast_utils.dart';
import 'package:slimshotai/features/convert/providers/convert_provider.dart';
import 'package:slimshotai/core/services/ad_service.dart';

class ConvertResultScreen extends ConsumerStatefulWidget {
  const ConvertResultScreen({super.key});

  @override
  ConsumerState<ConvertResultScreen> createState() =>
      _ConvertResultScreenState();
}

class _ConvertResultScreenState extends ConsumerState<ConvertResultScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    AdService.loadInterstitialAd();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(convertProvider);

    if (state.outputPaths.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF020617),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final selectedPath = state.outputPaths[_selectedIndex];
    final isBatch = state.outputPaths.length > 1;
    final srcFormat = state.inputFiles.isNotEmpty
        ? state.inputFiles.first.path.split('.').last.toUpperCase()
        : '?';
    final dstFormat = state.targetFormat.toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          Positioned(
            bottom: -80,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
              begin: const Offset(0, 0),
              end: const Offset(30, -30),
              duration: 4000.ms,
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
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: const Color(0xFF334155)),
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
                        'Conversion Done',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF8FAFC),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: -0.2, end: 0),

                Expanded(
                  flex: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildImagePreview(selectedPath, srcFormat, dstFormat),
                  ),
                ),

                if (isBatch) _buildThumbnailSelector(state),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildStatsCard(state, selectedPath),
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

  Widget _buildImagePreview(
    String path,
    String srcFormat,
    String dstFormat,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 24,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
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
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      srcFormat,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      LucideIcons.arrowRight,
                      color: Color(0xFF6366F1),
                      size: 12,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dstFormat,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6366F1),
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

  Widget _buildThumbnailSelector(ConvertState state) {
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF334155),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
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

  Widget _buildStatsCard(ConvertState state, String selectedPath) {
    final originalSize = state.inputFiles.isNotEmpty
        ? File(
            state.inputFiles[_selectedIndex < state.inputFiles.length
                    ? _selectedIndex
                    : 0]
                .path,
          ).lengthSync()
        : state.originalSize;
    final convertedSize = File(selectedPath).lengthSync();
    final delta = originalSize - convertedSize;
    final saved = delta > 0;

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
          child: Row(
            children: [
              Expanded(
                child: _ConvertStat(
                  label: 'Before',
                  value: FileUtils.formatFileSize(originalSize),
                  color: const Color(0xFF94A3B8),
                ),
              ),
              Container(width: 1, height: 36, color: const Color(0xFF334155)),
              Expanded(
                child: _ConvertStat(
                  label: 'After',
                  value: FileUtils.formatFileSize(convertedSize),
                  color: const Color(0xFF6366F1),
                ),
              ),
              Container(width: 1, height: 36, color: const Color(0xFF334155)),
              Expanded(
                child: _ConvertStat(
                  label: saved ? 'Saved' : 'Larger',
                  value: FileUtils.formatFileSize(delta.abs()),
                  color: saved ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(ConvertState state, String selectedPath) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                AdService.showInterstitialAd(
                  context,
                  onAdDismissed: () async {
                    HapticFeedback.mediumImpact();
                    try {
                      if (state.outputPaths.length > 1) {
                        for (final path in state.outputPaths) {
                          await Gal.putImage(path);
                        }
                        if (mounted) {
                          ToastUtils.show(
                            context,
                            '${state.outputPaths.length} photos saved!',
                          );
                        }
                      } else {
                        await Gal.putImage(selectedPath);
                        if (mounted) ToastUtils.show(context, 'Saved to gallery!');
                      }
                    } catch (e) {
                      if (mounted) {
                        ToastUtils.show(context, 'Error saving: $e', isError: true);
                      }
                    }
                  },
                );
              },
              icon: const Icon(LucideIcons.download, size: 18),
              label: Text(
                'Save${state.outputPaths.length > 1 ? ' All' : ''}',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.selectionClick();
                final xFiles = state.outputPaths
                    .map((p) => XFile(p))
                    .toList();
                await Share.shareXFiles(xFiles);
              },
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text(
                'Share',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF334155)),
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

class _ConvertStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ConvertStat({
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
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
