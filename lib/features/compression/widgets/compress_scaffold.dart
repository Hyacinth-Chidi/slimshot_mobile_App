import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/colour_field_backdrop.dart';
import 'compress_panels.dart';

/// Wide enough for the picture and its settings side by side: a tablet, or
/// a phone turned on its side.
const double kCompressTwoColumnWidth = 700;

/// The one layout every compress screen shares — the video and photo
/// screens and the result — so they cannot drift apart: Home's light behind
/// a top bar, the picture, an optional thumbnail row, the content, and the
/// action pinned beneath.
///
/// On a phone it is one column that scrolls under the pinned action, the
/// picture [phonePictureHeight] tall. From [kCompressTwoColumnWidth] it is
/// two: the picture (and thumbnails) filling the left, the content scrolling
/// on the right above the action.
class CompressScaffold extends StatelessWidget {
  const CompressScaffold({
    super.key,
    required this.topBar,
    required this.picture,
    required this.phonePictureHeight,
    required this.content,
    required this.action,
    this.thumbnails,
  });

  final Widget topBar;
  final Widget picture;
  final double phonePictureHeight;
  final Widget? thumbnails;
  final List<Widget> content;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kCompressTwoColumnWidth;
    final bottom = CompressBottomBar(child: action);
    final thumbs = thumbnails;

    final Widget body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 11,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
                  child: Column(children: [
                    Expanded(child: picture),
                    if (thumbs != null) ...[const SizedBox(height: 12), thumbs],
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
                        children: content,
                      ),
                    ),
                  ),
                  bottom,
                ]),
              ),
            ],
          )
        : Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: phonePictureHeight, child: picture),
                    if (thumbs != null) ...[const SizedBox(height: 12), thumbs],
                    const SizedBox(height: 14),
                    ...content,
                  ],
                ),
              ),
            ),
            bottom,
          ]);

    return Material(
      color: AppColors.background,
      child: Stack(children: [
        const Positioned.fill(child: ColourFieldBackdrop()),
        SafeArea(
          child: Column(children: [topBar, Expanded(child: body)]),
        ),
      ]),
    );
  }
}

/// How tall the picture is on a phone: the picture's own shape across the
/// width, capped at [capFraction] of the height so a tall picture leaves
/// room for its settings, and never under 160.
double compressPhonePictureHeight(
  Size screen, {
  required double aspectRatio,
  double capFraction = 0.42,
}) {
  final width = screen.width - 32;
  final cap = screen.height * capFraction;
  final fitted = width / aspectRatio;
  return (fitted < cap ? fitted : cap).clamp(160.0, double.infinity);
}

/// One picture per file, the one on screen ringed; a tap on another asks
/// [onPreview] to show it. Each tile is keyed `<keyPrefix>_<index>`.
class CompressThumbnailRow extends StatelessWidget {
  const CompressThumbnailRow({
    super.key,
    required this.count,
    required this.thumbnails,
    required this.previewIndex,
    required this.onPreview,
    required this.keyPrefix,
  });

  final int count;
  final List<Widget> thumbnails;
  final int previewIndex;
  final ValueChanged<int>? onPreview;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final shown = i == previewIndex;
            return GestureDetector(
              key: Key('${keyPrefix}_$i'),
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
}

/// Progress over the picture: the current file's percent and, for several,
/// which one ("2 of 5").
class CompressProgressRing extends StatelessWidget {
  const CompressProgressRing(this.progress, this.batchLine, {super.key});

  /// The current file's progress, 0–100.
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

/// "Keep SlimShot open until it finishes." — the one line beside a running
/// compression.
class CompressKeepOpenNote extends StatelessWidget {
  const CompressKeepOpenNote({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Keep SlimShot open until it finishes.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      );
}
