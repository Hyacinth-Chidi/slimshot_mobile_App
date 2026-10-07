import 'package:flutter/material.dart';

import '../../../core/services/ad_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../logic/compress_labels.dart';
import '../logic/compression_presets.dart';
import '../providers/compression_provider.dart';
import 'compress_panels.dart';
import 'compress_scaffold.dart';

export 'compress_scaffold.dart' show kCompressTwoColumnWidth;

/// The Compress video screen as a picture of [state]: the screen owns the
/// player and the provider, and hands this the preview and the callbacks.
///
/// Home's light and glass (`ColourFieldBackdrop`, `FrostedGlass`) — this is
/// a screen outside the editor, where colour is not being judged. The layout
/// is [CompressScaffold], shared with the photo screen and the result.
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

  bool get _compressing => state.isProcessing;
  int get _count => state.inputFiles.length;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return CompressScaffold(
      topBar: CompressTopBar(
        title: _compressing ? 'Compressing' : 'Compress video',
        onBack: onBack,
      ),
      // Hugs the video's own shape; only a tall video is capped. While it
      // compresses, the picture is what the screen is about.
      phonePictureHeight: _compressing
          ? screen.height * 0.42
          : compressPhonePictureHeight(screen,
              aspectRatio: previewAspectRatio ?? 16 / 9),
      picture: _PreviewFrame(
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
      ),
      thumbnails: _count > 1 && !_compressing
          ? CompressThumbnailRow(
              count: _count,
              thumbnails: thumbnails,
              previewIndex: previewIndex,
              onPreview: onPreview,
              keyPrefix: 'compress_thumb',
            )
          : null,
      // Sizes before and after belong to the result screen, where the after
      // is a fact rather than a guess.
      content: _compressing
          ? const [CompressKeepOpenNote()]
          : [
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
              const SizedBox(height: 8),
            ],
      action: _compressing
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
  }
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
              Center(child: CompressProgressRing(progress, batchLine)),
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
