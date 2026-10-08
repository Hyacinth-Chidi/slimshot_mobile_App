import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../compression/logic/compress_labels.dart';
import '../../compression/widgets/compress_panels.dart';
import '../../compression/widgets/compress_scaffold.dart';
import '../providers/privacy_provider.dart';
import 'privacy_details.dart';

/// The Privacy Strip screen as a picture of [state], on the compress
/// screens' [CompressScaffold]. It shows what the photos **really** carry —
/// read from each file — rather than a fixed list, and nothing at all where
/// there is nothing.
class PrivacyStripView extends StatelessWidget {
  const PrivacyStripView({
    super.key,
    required this.state,
    required this.photo,
    required this.onBack,
    required this.onChangePhotos,
    required this.onStrip,
    required this.onCancel,
    this.photoAspectRatio,
    this.photoInfo,
    this.thumbnails = const [],
    this.previewIndex = 0,
    this.onPreview,
  });

  final PrivacyState state;
  final Widget photo;
  final double? photoAspectRatio;
  final String? photoInfo;
  final List<Widget> thumbnails;
  final int previewIndex;
  final ValueChanged<int>? onPreview;

  final VoidCallback onBack;
  final VoidCallback onChangePhotos;
  final VoidCallback onStrip;
  final VoidCallback onCancel;

  bool get _busy => state.isProcessing;
  int get _count => state.inputFiles.length;
  String get _these => _count > 1 ? 'these photos' : 'this photo';

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return CompressScaffold(
      topBar: CompressTopBar(
        title: _busy ? 'Removing details' : 'Privacy strip',
        onBack: onBack,
        trailing: _busy
            ? null
            : CompressGlassIconAction(
                key: const Key('privacy_change'),
                icon: LucideIcons.imagePlus,
                label: 'Change photos',
                onPressed: onChangePhotos,
              ),
      ),
      phonePictureHeight: _busy
          ? screen.height * 0.42
          : compressPhonePictureHeight(screen,
              aspectRatio: photoAspectRatio ?? 3 / 4, capFraction: 0.40),
      picture: ClipRRect(
        key: const Key('privacy_preview'),
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          CompressPhotoPicture(photo: photo, aspectRatio: photoAspectRatio),
          if (_busy) ...[
            ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            Center(
              child: CompressProgressRing(
                state.progress,
                _count > 1
                    ? '${state.currentProcessingIndex + 1} of $_count'
                    : null,
              ),
            ),
          ] else
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(children: [
                if (_count > 1)
                  Flexible(
                    child: CompressInfoChip('$_count photos',
                        icon: LucideIcons.layers),
                  )
                else if (photoInfo != null && photoInfo!.isNotEmpty)
                  Flexible(
                    child: CompressInfoChip(photoInfo!, icon: LucideIcons.image),
                  ),
                const Spacer(),
                if (state.originalSize > 0)
                  CompressInfoChip(compactSize(state.originalSize),
                      icon: LucideIcons.hardDrive),
              ]),
            ),
        ]),
      ),
      thumbnails: _count > 1 && !_busy
          ? CompressThumbnailRow(
              count: _count,
              thumbnails: thumbnails,
              previewIndex: previewIndex,
              onPreview: onPreview,
              keyPrefix: 'privacy_thumb',
            )
          : null,
      content: _busy ? const [CompressKeepOpenNote()] : _found(),
      action: _busy
          ? CompressGlassButton(
              key: const Key('privacy_cancel'),
              label: 'Cancel',
              onPressed: onCancel,
            )
          : CompressPrimaryButton(
              key: const Key('privacy_strip'),
              label: _count > 1 ? 'Remove from $_count photos' : 'Remove details',
              icon: LucideIcons.shieldCheck,
              onPressed: onStrip,
            ),
    );
  }

  List<Widget> _found() {
    final found = state.found;
    final label = CompressSectionLabel('Found in $_these');
    if (found == null) {
      return [
        const SizedBox(height: 6),
        label,
        const PrivacyNote(
          key: Key('privacy_reading'),
          text: 'Reading…',
          leading: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primaryStart),
          ),
        ),
      ];
    }
    final lines = privacyDetailLines(found);
    return [
      const SizedBox(height: 6),
      label,
      if (lines.isEmpty)
        PrivacyNote(text: 'No location, camera or date in $_these.')
      else
        CompressGroup(children: [for (final l in lines) PrivacyDetailRow(l)]),
      const SizedBox(height: 8),
    ];
  }
}
