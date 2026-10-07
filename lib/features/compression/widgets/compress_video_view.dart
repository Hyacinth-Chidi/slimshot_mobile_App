import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/ad_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/widgets/colour_field_backdrop.dart';
import '../logic/compression_presets.dart';
import '../logic/compress_labels.dart';
import '../providers/compression_provider.dart';
import 'compress_panels.dart';

/// Wide enough for the video and its settings side by side: a tablet, or a
/// phone turned on its side.
const double kCompressTwoColumnWidth = 700;

/// The Compress video screen as a picture of [state]: the screen owns the
/// player and the provider, and hands this the preview and the callbacks.
///
/// Home's light and glass (`ColourFieldBackdrop`, `FrostedGlass`) — this is
/// a screen outside the editor, where colour is not being judged.
class CompressVideoView extends StatelessWidget {
  const CompressVideoView({
    super.key,
    required this.state,
    required this.preview,
    required this.onBack,
    required this.onSelectPreset,
    required this.onToggleWhatsApp,
    required this.onToggleRemoveLocation,
    required this.onFormat,
    required this.onCompress,
    required this.onCancel,
    this.previewAspectRatio,
    this.isPlaying = false,
    this.onTogglePlay,
    this.showPro = AdService.enabled,
    this.thumbnails = const [],
    this.previewIndex = 0,
    this.onPreview,
  });

  final CompressionState state;

  /// The video itself; letterboxed by the frame at [previewAspectRatio].
  final Widget preview;
  final double? previewAspectRatio;
  final bool isPlaying;
  final VoidCallback? onTogglePlay;

  final VoidCallback onBack;
  final ValueChanged<CompressionPreset> onSelectPreset;
  final VoidCallback onToggleWhatsApp;
  final VoidCallback onToggleRemoveLocation;
  final ValueChanged<String> onFormat;
  final VoidCallback onCompress;
  final VoidCallback onCancel;

  /// A PRO badge promises an ad to unlock it; with ads off there is none.
  final bool showPro;

  /// One picture per video, shown as a row under the preview when there is
  /// more than one; [previewIndex] is the one playing above, and a tap on
  /// another asks [onPreview] to play that one instead.
  final List<Widget> thumbnails;
  final int previewIndex;
  final ValueChanged<int>? onPreview;

  bool get _showThumbnails => _count > 1 && !_compressing;

  bool get _compressing => state.isProcessing;
  int get _count => state.inputFiles.length;


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= kCompressTwoColumnWidth;
    final bottom = CompressBottomBar(
      child: _compressing
          ? CompressGlassButton(
              key: const Key('compress_cancel'),
              label: 'Cancel',
              onPressed: onCancel,
            )
          : CompressPrimaryButton(
              key: const Key('compress_start'),
              label: 'Compress',
              icon: LucideIcons.zap,
              onPressed: state.selectedPreset == null ? null : onCompress,
            ),
    );

    final Widget body;
    if (wide) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
              child: Column(children: [
                Expanded(child: _frame()),
                if (_showThumbnails) ...[
                  const SizedBox(height: 12),
                  _thumbnailRow(),
                ],
              ]),
            ),
          ),
          Expanded(
            flex: 9,
            child: Column(children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _settings(),
                  ),
                ),
              ),
              bottom,
            ]),
          ),
        ],
      );
    } else {
      final width = size.width - 32;
      final cap = size.height * 0.42;
      final aspect = previewAspectRatio ?? 16 / 9;
      // Hugs the video's own shape; only a tall video is capped. While it
      // compresses, the picture is what the screen is about.
      final previewHeight = _compressing
          ? cap
          : math.max(160.0, math.min(width / aspect, cap));
      body = Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: previewHeight, child: _frame()),
                if (_showThumbnails) ...[
                  const SizedBox(height: 12),
                  _thumbnailRow(),
                ],
                const SizedBox(height: 14),
                ..._settings(),
              ],
            ),
          ),
        ),
        bottom,
      ]);
    }

    return Material(
      color: AppColors.background,
      child: Stack(children: [
        const Positioned.fill(child: ColourFieldBackdrop()),
        SafeArea(
          child: Column(children: [
            CompressTopBar(
              title: _compressing ? 'Compressing' : 'Compress video',
              onBack: onBack,
            ),
            Expanded(child: body),
          ]),
        ),
      ]),
    );
  }

  Widget _frame() => _PreviewFrame(
        key: const Key('compress_preview'),
        preview: preview,
        aspectRatio: previewAspectRatio,
        compressing: _compressing,
        isPlaying: isPlaying,
        onTogglePlay: onTogglePlay,
        progress: state.progress,
        batchLine: _count > 1
            ? '${state.currentProcessingIndex + 1} of $_count'
            : null,
        infoLabel: _count > 1
            ? '$_count videos'
            : state.videoMetadata == null
                ? null
                : videoInfoLabel(state.videoMetadata!),
        infoIcon: _count > 1 ? LucideIcons.layers : LucideIcons.film,
        sizeLabel:
            state.originalSize > 0 ? compactSize(state.originalSize) : null,
      );

  Widget _thumbnailRow() => SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _count,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final shown = i == previewIndex;
            return GestureDetector(
              key: Key('compress_thumb_$i'),
              onTap: shown || onPreview == null ? null : () => onPreview!(i),
              child: Container(
                width: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: shown ? AppColors.primaryStart : AppColors.border,
                    width: shown ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: i < thumbnails.length
                      ? thumbnails[i]
                      : const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      );

  // Sizes before and after belong to the result screen, where the after is
  // a fact rather than a guess.
  List<Widget> _settings() => [
        if (_compressing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Keep SlimShot open until it finishes.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          )
        else ...[
          const SizedBox(height: 6),
          const CompressSectionLabel('Quality'),
          CompressGroup(children: [
            for (final preset in CompressionPresets.videoPresets)
              CompressChoiceRow(
                key: Key('compress_preset_${preset.id}'),
                icon: preset.icon,
                title: preset.name,
                subtitle: preset.description,
                selected: state.selectedPreset?.id == preset.id,
                tag: preset.id == 'smart' ? 'Recommended' : null,
                badge: preset.isPro && showPro ? 'PRO' : null,
                onTap: () => onSelectPreset(preset),
              ),
          ]),
          const SizedBox(height: 20),
          const CompressSectionLabel('Options'),
          CompressGroup(children: [
            CompressSwitchRow(
              key: const Key('compress_whatsapp'),
              icon: LucideIcons.messageCircle,
              label: 'WhatsApp ready',
              value: state.whatsAppOptimize,
              onToggle: onToggleWhatsApp,
            ),
            CompressSwitchRow(
              key: const Key('compress_remove_location'),
              icon: LucideIcons.mapPinOff,
              label: 'Remove location',
              value: state.removeMetadata,
              onToggle: onToggleRemoveLocation,
            ),
            CompressOptionRow(
              icon: LucideIcons.fileVideo,
              label: 'Format',
              trailing: CompressSegmented(
                options: const [('mp4', 'MP4'), ('webm', 'WebM')],
                value: state.targetVideoFormat,
                onChanged: onFormat,
              ),
            ),
          ]),
        ],
        const SizedBox(height: 8),
      ];
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    super.key,
    required this.preview,
    required this.aspectRatio,
    required this.compressing,
    required this.isPlaying,
    required this.onTogglePlay,
    required this.progress,
    required this.batchLine,
    required this.infoLabel,
    required this.infoIcon,
    required this.sizeLabel,
  });

  final Widget preview;
  final double? aspectRatio;
  final bool compressing;
  final bool isPlaying;
  final VoidCallback? onTogglePlay;

  /// The current file's progress, 0–100.
  final double progress;
  final String? batchLine;
  final String? infoLabel;
  final IconData infoIcon;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: compressing ? null : onTogglePlay,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Colors.black),
            Center(
              child: AspectRatio(
                aspectRatio: aspectRatio ?? 16 / 9,
                child: preview,
              ),
            ),
            if (compressing) ...[
              ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
              Center(child: _ProgressRing(progress, batchLine)),
            ] else ...[
              Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isPlaying ? 0 : 1,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: const Icon(LucideIcons.play,
                        color: AppColors.textPrimary, size: 24),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Row(children: [
                  if (infoLabel != null)
                    Flexible(child: CompressInfoChip(infoLabel!, icon: infoIcon)),
                  const Spacer(),
                  if (sizeLabel != null)
                    CompressInfoChip(sizeLabel!, icon: LucideIcons.hardDrive),
                ]),
              ),
            ],
          ]),
        ),
      );
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing(this.progress, this.batchLine);

  final double progress;
  final String? batchLine;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 104,
        height: 104,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0),
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              color: AppColors.lilac,
              backgroundColor: const Color(0x1FFFFFFF), // white12
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                '${progress.round()}%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (batchLine != null)
                Text(
                  batchLine!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
            ]),
          ),
        ]),
      );
}
