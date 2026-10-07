import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../logic/compress_labels.dart';
import 'compress_panels.dart';
import 'compress_scaffold.dart';

/// The finished compression, as a picture: the result, its real sizes, what
/// was applied, and what to do with it. The screen owns the player, the
/// history and the saving, and hands this the preview and the callbacks —
/// the same split as the compress screens', on the same [CompressScaffold].
class CompressResultView extends StatelessWidget {
  const CompressResultView({
    super.key,
    required this.isVideo,
    required this.count,
    required this.beforeBytes,
    required this.afterBytes,
    required this.preview,
    required this.format,
    required this.locationRemoved,
    required this.onClose,
    required this.onSave,
    required this.onShare,
    required this.onCompressAnother,
    this.previewAspectRatio,
    this.keptAsItWas = false,
    this.quality,
    this.thumbnails = const [],
    this.previewIndex = 0,
    this.onPreview,
  });

  final bool isVideo;
  final int count;

  /// Totals for every file, so the sizes and the saving agree.
  final int beforeBytes;
  final int afterBytes;

  /// Every file was already as small as it gets and was handed back as is.
  final bool keptAsItWas;

  /// A [ResultVideoFrame] or [ResultPhotoFrame].
  final Widget preview;
  final double? previewAspectRatio;

  final String? quality;
  final String format;
  final bool locationRemoved;

  final List<Widget> thumbnails;
  final int previewIndex;
  final ValueChanged<int>? onPreview;

  final VoidCallback onClose;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onCompressAnother;

  String get _noun => isVideo
      ? (count == 1 ? 'video' : 'videos')
      : (count == 1 ? 'photo' : 'photos');

  @override
  Widget build(BuildContext context) => CompressScaffold(
        topBar: CompressTopBar(
          title: 'Done',
          titleKey: const Key('result_title'),
          backKey: const Key('result_close'),
          icon: LucideIcons.x,
          iconLabel: 'Close',
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
        // A photo is compared by dragging across it, so it gets more room.
        phonePictureHeight: compressPhonePictureHeight(
          MediaQuery.sizeOf(context),
          aspectRatio: previewAspectRatio ?? (isVideo ? 16 / 9 : 3 / 4),
          capFraction: isVideo ? 0.42 : 0.45,
        ),
        picture: ClipRRect(
          key: const Key('result_preview'),
          borderRadius: BorderRadius.circular(22),
          child: preview,
        ),
        thumbnails: count > 1
            ? CompressThumbnailRow(
                count: count,
                thumbnails: thumbnails,
                previewIndex: previewIndex,
                onPreview: onPreview,
                keyPrefix: 'result_thumb',
              )
            : null,
        content: _facts(),
        action: _actions(),
      );

  List<Widget> _facts() => [
        CompressBeforeAfterCard(
          key: const Key('result_sizes'),
          before: compactSize(beforeBytes),
          after: compactSize(afterBytes),
          beforeBytes: beforeBytes,
          afterBytes: afterBytes,
          caption: keptAsItWas
              ? 'Already as small as it gets — kept as it was.'
              : count > 1
                  ? 'All $count $_noun'
                  : null,
        ),
        const SizedBox(height: 20),
        const CompressSectionLabel('Details'),
        CompressGroup(children: [
          if (quality != null)
            CompressValueRow(
              icon: LucideIcons.sparkles,
              label: 'Quality',
              value: quality!,
            ),
          CompressValueRow(
            icon: isVideo ? LucideIcons.fileVideo : LucideIcons.fileImage,
            label: 'Format',
            value: format,
          ),
          CompressValueRow(
            icon: LucideIcons.mapPinOff,
            label: 'Location',
            value: locationRemoved ? 'Removed' : 'Kept',
          ),
        ]),
        const SizedBox(height: 8),
      ];

  Widget _actions() => Column(mainAxisSize: MainAxisSize.min, children: [
        CompressPrimaryButton(
          key: const Key('result_save'),
          label: count > 1 ? 'Save $count to gallery' : 'Save to gallery',
          icon: LucideIcons.download,
          onPressed: onSave,
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: CompressGlassIconButton(
              key: const Key('result_share'),
              icon: LucideIcons.share2,
              label: 'Share',
              onPressed: onShare,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: CompressGlassIconButton(
              key: const Key('result_new'),
              icon: LucideIcons.plus,
              label: isVideo ? 'New video' : 'New photos',
              onPressed: onCompressAnother,
            ),
          ),
        ]),
      ]);
}

/// The compressed video: play, a time bar to scrub, and full screen.
class ResultVideoFrame extends StatelessWidget {
  const ResultVideoFrame({
    super.key,
    required this.video,
    required this.aspectRatio,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onFullScreen,
  });

  /// Null while the player is still opening the file.
  final Widget? video;
  final double aspectRatio;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onFullScreen;

  static String _clock(Duration d) {
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s'
        : '${d.inMinutes}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds.toDouble();
    final at =
        position.inMilliseconds.toDouble().clamp(0.0, math.max(total, 0.0)).toDouble();
    const time = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTogglePlay,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        if (video == null)
          const Center(
            child: CircularProgressIndicator(
                color: AppColors.primaryStart, strokeWidth: 2),
          )
        else
          Center(child: AspectRatio(aspectRatio: aspectRatio, child: video)),
        // The controls' backing, so the time reads over a bright frame.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 64,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ),
        ),
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
          top: 8,
          right: 8,
          child: _OverlayIconButton(
            icon: LucideIcons.maximize2,
            label: 'Full screen',
            onTap: onFullScreen,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 4,
          child: Row(children: [
            Text(_clock(position), style: time),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppColors.textPrimary,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: AppColors.textPrimary,
                ),
                child: Slider(
                  value: at,
                  max: total <= 0 ? 1 : total,
                  onChanged: total <= 0
                      ? null
                      : (v) => onSeek(Duration(milliseconds: v.round())),
                ),
              ),
            ),
            Text(_clock(duration), style: time),
          ]),
        ),
      ]),
    );
  }
}

/// A compressed photo against its original — the slider is the caller's —
/// labelled, with full screen.
class ResultPhotoFrame extends StatelessWidget {
  const ResultPhotoFrame({
    super.key,
    required this.compare,
    required this.onFullScreen,
  });

  final Widget compare;
  final VoidCallback onFullScreen;

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        compare,
        const Positioned(
          left: 12,
          top: 12,
          child: IgnorePointer(child: CompressInfoChip('Before')),
        ),
        const Positioned(
          right: 12,
          top: 12,
          child: IgnorePointer(child: CompressInfoChip('After')),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _OverlayIconButton(
            icon: LucideIcons.maximize2,
            label: 'Full screen',
            onTap: onFullScreen,
          ),
        ),
      ]);
}

class _OverlayIconButton extends StatelessWidget {
  const _OverlayIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          // 44px to touch, 36 to see.
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      );
}
