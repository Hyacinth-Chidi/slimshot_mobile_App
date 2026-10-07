import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/services/ad_service.dart';
import '../../../core/theme/lucide_icons.dart';
import '../logic/compress_labels.dart';
import '../logic/compression_presets.dart';
import '../providers/compression_provider.dart';
import 'compress_panels.dart';
import 'compress_scaffold.dart';

/// The Compress photo screen as a picture of [state] — the video screen's
/// design on the shared [CompressScaffold], with what photos have: no
/// player, no WhatsApp option (the photo compressor has none), and three
/// formats.
class CompressPhotoView extends StatelessWidget {
  const CompressPhotoView({
    super.key,
    required this.state,
    required this.photo,
    required this.onBack,
    required this.onSelectPreset,
    required this.onToggleRemoveLocation,
    required this.onFormat,
    required this.onCompress,
    required this.onCancel,
    this.photoAspectRatio,
    this.photoInfo,
    this.showPro = AdService.enabled,
    this.thumbnails = const [],
    this.previewIndex = 0,
    this.onPreview,
  });

  final CompressionState state;

  /// The photo on screen, drawn twice: sharp at [photoAspectRatio], and
  /// blurred behind it to fill the frame.
  final Widget photo;
  final double? photoAspectRatio;

  /// "HEIC · 12 MP" for the photo on screen.
  final String? photoInfo;

  final VoidCallback onBack;
  final ValueChanged<CompressionPreset> onSelectPreset;
  final VoidCallback onToggleRemoveLocation;
  final ValueChanged<String> onFormat;
  final VoidCallback onCompress;
  final VoidCallback onCancel;

  /// A PRO badge promises an ad to unlock it; with ads off there is none.
  final bool showPro;

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
        title: _compressing
            ? 'Compressing'
            : _count > 1
                ? 'Compress photos'
                : 'Compress photo',
        onBack: onBack,
      ),
      phonePictureHeight: _compressing
          ? screen.height * 0.42
          : compressPhonePictureHeight(screen,
              aspectRatio: photoAspectRatio ?? 3 / 4),
      picture: _PhotoFrame(
        key: const Key('compress_preview'),
        photo: photo,
        aspectRatio: photoAspectRatio,
        compressing: _compressing,
        progress: state.progress,
        batchLine: _count > 1
            ? '${state.currentProcessingIndex + 1} of $_count'
            : null,
        infoLabel: _count > 1 ? '$_count photos' : photoInfo,
        infoIcon: _count > 1 ? LucideIcons.layers : LucideIcons.image,
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
      content: _compressing
          ? const [CompressKeepOpenNote()]
          : [
              const SizedBox(height: 6),
              const CompressSectionLabel('Quality'),
              CompressGroup(children: [
                for (final preset in CompressionPresets.imagePresets)
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
                  key: const Key('compress_remove_location'),
                  icon: LucideIcons.mapPinOff,
                  label: 'Remove location',
                  value: state.removeMetadata,
                  onToggle: onToggleRemoveLocation,
                ),
                CompressOptionRow(
                  icon: LucideIcons.fileImage,
                  label: 'Format',
                  trailing: CompressSegmented(
                    options: const [
                      ('jpg', 'JPG'),
                      ('png', 'PNG'),
                      ('webp', 'WebP'),
                    ],
                    value: state.targetImageFormat,
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

/// The photo letterboxed over a blurred fill of itself, so a portrait photo
/// in a wide frame — or a wide one in a tall frame — has no dead bars.
class _PhotoFrame extends StatelessWidget {
  const _PhotoFrame({
    super.key,
    required this.photo,
    required this.aspectRatio,
    required this.compressing,
    required this.progress,
    required this.batchLine,
    required this.infoLabel,
    required this.infoIcon,
    required this.sizeLabel,
  });

  final Widget photo;
  final double? aspectRatio;
  final bool compressing;
  final double progress;
  final String? batchLine;
  final String? infoLabel;
  final IconData infoIcon;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: Colors.black),
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: SizedBox.expand(
              child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(
                width: 300,
                height: 300 / (aspectRatio ?? 3 / 4),
                child: photo,
              )),
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
          Center(
            child: AspectRatio(aspectRatio: aspectRatio ?? 3 / 4, child: photo),
          ),
          if (compressing) ...[
            ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            Center(child: CompressProgressRing(progress, batchLine)),
          ] else
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(children: [
                if (infoLabel != null && infoLabel!.isNotEmpty)
                  Flexible(child: CompressInfoChip(infoLabel!, icon: infoIcon)),
                const Spacer(),
                if (sizeLabel != null)
                  CompressInfoChip(sizeLabel!, icon: LucideIcons.hardDrive),
              ]),
            ),
        ]),
      );
}
