import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../compression/widgets/compress_panels.dart';
import '../../compression/widgets/compress_scaffold.dart';
import '../logic/photo_metadata.dart';
import '../providers/privacy_provider.dart';
import 'privacy_details.dart';

/// The Privacy report: what the photos carried, each line ticked only where
/// the cleaned file was read back and the detail is gone. A detail that
/// survived is said, never ticked; a file that could not be read back is
/// left unticked rather than assumed clean.
class PrivacyReportView extends StatelessWidget {
  const PrivacyReportView({
    super.key,
    required this.state,
    required this.photo,
    required this.onClose,
    required this.onSave,
    required this.onShare,
    required this.onNew,
    this.photoAspectRatio,
    this.thumbnails = const [],
    this.previewIndex = 0,
    this.onPreview,
  });

  final PrivacyState state;
  final Widget photo;
  final double? photoAspectRatio;
  final List<Widget> thumbnails;
  final int previewIndex;
  final ValueChanged<int>? onPreview;

  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onNew;

  int get _count => state.outputPaths.length;

  List<PhotoMetadata?> get _remaining =>
      state.remaining ?? List.filled(_count, null);

  /// Every cleaned file was read back.
  bool get _verified => _remaining.every((m) => m != null);

  bool get _allClean => _verified && _remaining.every((m) => m!.isEmpty);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return CompressScaffold(
      topBar: CompressTopBar(
        title: 'Done',
        icon: LucideIcons.x,
        iconLabel: 'Close',
        backKey: const Key('privacy_close'),
        badge: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.success,
          ),
          child: const Icon(LucideIcons.check, size: 15, color: Colors.white),
        ),
        onBack: onClose,
      ),
      phonePictureHeight: compressPhonePictureHeight(screen,
          aspectRatio: photoAspectRatio ?? 3 / 4, capFraction: 0.40),
      picture: ClipRRect(
        key: const Key('privacy_preview'),
        borderRadius: BorderRadius.circular(22),
        child: Stack(fit: StackFit.expand, children: [
          CompressPhotoPicture(photo: photo, aspectRatio: photoAspectRatio),
          if (_allClean)
            const Positioned(
              left: 12,
              top: 12,
              child: CompressInfoChip('Details removed',
                  icon: LucideIcons.shieldCheck),
            ),
        ]),
      ),
      thumbnails: _count > 1
          ? CompressThumbnailRow(
              count: _count,
              thumbnails: thumbnails,
              previewIndex: previewIndex,
              onPreview: onPreview,
              keyPrefix: 'privacy_thumb',
            )
          : null,
      content: _content(),
      action: Column(mainAxisSize: MainAxisSize.min, children: [
        CompressPrimaryButton(
          key: const Key('privacy_save'),
          label: _count > 1 ? 'Save $_count to gallery' : 'Save to gallery',
          icon: LucideIcons.download,
          onPressed: onSave,
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: CompressGlassIconButton(
              key: const Key('privacy_share'),
              icon: LucideIcons.share2,
              label: 'Share',
              onPressed: onShare,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CompressGlassIconButton(
              key: const Key('privacy_new'),
              icon: LucideIcons.plus,
              label: 'New photos',
              onPressed: onNew,
            ),
          ),
        ]),
      ]),
    );
  }

  List<Widget> _content() {
    final lines = privacyDetailLines(state.found ?? const []);
    if (lines.isEmpty) {
      return [
        const SizedBox(height: 6),
        PrivacyNote(
          text: 'No location, camera or date was in '
              '${_count > 1 ? 'these photos' : 'this photo'}.',
        ),
      ];
    }
    return [
      const SizedBox(height: 6),
      const CompressSectionLabel('Removed'),
      CompressGroup(children: [
        for (final line in lines)
          PrivacyDetailRow(
            line,
            state: privacyDetailCount(_remaining, line.detail) > 0
                ? PrivacyDetailState.survived
                : _verified
                    ? PrivacyDetailState.removed
                    : PrivacyDetailState.found,
          ),
      ]),
      const SizedBox(height: 8),
    ];
  }
}
