import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../models/video_editor_state.dart';
import '../../providers/video_editor_notifier.dart';
import 'editor_sheet.dart';

/// The solid colours offered for the letterbox background. Black first: it is
/// the default every project starts on, and the tile that reads as current for
/// a draft written before the picker existed.
const List<Color> kBackgroundPresets = [
  Colors.black,
  Colors.white,
  Color(0xFF1E1E1E),
  Color(0xFF2C3E50),
  Color(0xFFE74C3C),
  Color(0xFF3498DB),
  Color(0xFF2ECC71),
  Color(0xFFF1C40F),
  Color(0xFFE67E22),
  Color(0xFF9B59B6),
  Color(0xFFE91E63),
  Color(0xFF00BCD4),
  Color(0xFF607D8B),
  Color(0xFF795548),
];

/// One edge inset for the sheet, matching every other sheet's.
const double _kEdge = 16;

/// The gap between tiles, in both directions.
const double _kTileGap = 10;

/// Asks the user for a photo and answers its path, or null when they back out.
typedef BackgroundPhotoPicker = Future<String?> Function();

Future<String?> _pickFromGallery() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  return picked?.path;
}

/// The letterbox background picker: a photo tile, then square colour tiles.
///
/// **A sheet, not a panel.** A background is a choice *about* the picture with
/// no canvas or timeline gesture attached — the rule that already puts the
/// curve, filters and effects in sheets — so it opens over a clear canvas like
/// they do and the user watches the bars change as they tap. **Capped at
/// [kEditorSheetPreviewFraction] of the screen** and scrolling inside, because
/// a sheet that climbs to half the screen hides the very picture it is about.
///
/// **The "Solid Color" switch is gone.** It toggled between a `black` type and
/// a `color` type, but black is a colour: it is the first tile, and picking any
/// tile is the whole interaction. The `black` type survives in the model for
/// drafts already written and shows here as the black tile being current.
///
/// **The photo tile is the grid's first cell**, with the colours flowing on
/// from it in the same row — alone on a row of its own it read as a separate
/// section. Empty, it is an invitation: a dashed frame, an add-photo glyph and
/// "Photo" beneath the glyph *inside* the tile. With a photo chosen it shows
/// that photo with the caption along its foot, and keeps showing it while a
/// colour is in use, so one tap brings the photo back without another trip to
/// the picker (tapping it while already in use replaces it). It is exactly a
/// colour tile's size — the label lives inside so the rows stay level; hanging
/// under the tile it would make the first row taller and push the second row
/// down. The caption is what sets it apart, and that is the point: it is an
/// action where the others are values.
///
/// **Tiles, not circles**, the width of the crop panel's ratio tiles and square
/// because a colour needs no label. Every tap applies live and is one undo
/// step; the ✓ only dismisses.
class BackgroundSheet extends ConsumerWidget {
  const BackgroundSheet({super.key, this.pickImage});

  /// How a photo is asked for. The gallery picker in the app; a stub in tests,
  /// which have no platform to answer one.
  final BackgroundPhotoPicker? pickImage;

  /// The side of a tile: the crop panel's tile width, so the two pickers match.
  static const double kTileSize = 64.0;

  /// The photo tile's box (not its label), for tests and anything that needs
  /// to find it.
  static const Key photoTileKey = Key('background_photo_tile');

  /// The blur tile, second in the grid.
  static const Key blurTileKey = Key('background_blur_tile');

  /// The key of a colour's tile, for tests and for anything that needs to
  /// find one.
  static Key tileKey(Color colour) =>
      Key('background_tile_${colour.toARGB32().toRadixString(16)}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);
    final photoPath = state.backgroundImagePath;
    final usingPhoto =
        state.backgroundType == EditorBackgroundType.image && photoPath != null;
    // The old `black` type is the black tile; a colour is its colour; a photo
    // in use marks no colour at all.
    final int? currentColour = switch (state.backgroundType) {
      EditorBackgroundType.black => Colors.black.toARGB32(),
      EditorBackgroundType.color => state.backgroundColor.toARGB32(),
      EditorBackgroundType.image =>
        photoPath == null ? Colors.black.toARGB32() : null,
      EditorBackgroundType.blur => null,
    };
    final usingBlur = state.backgroundType == EditorBackgroundType.blur;
    final maxHeight =
        MediaQuery.sizeOf(context).height * kEditorSheetPreviewFraction;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kEdge),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Background',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      key: const Key('background_done'),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          LucideIcons.check,
                          color: AppColors.primaryStart,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Loose, so a short list takes only its height and a long one
              // stops at the cap and scrolls.
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.fromLTRB(_kEdge, 0, _kEdge, _kEdge),
                  // One grid: the photo tile is its first cell and the
                  // colours flow on from it in the same row. Alone on a row
                  // above them it read as a separate section.
                  child: Wrap(
                    spacing: _kTileGap,
                    runSpacing: _kTileGap,
                    children: [
                      _PhotoTile(
                        path: photoPath,
                        selected: usingPhoto,
                        onTap: () => _onPhotoTap(context, ref),
                      ),
                      // The clip blurred behind itself — what most editors
                      // default to for landscape footage on a portrait canvas.
                      // Second, beside the photo: the two are the "picture"
                      // fills, the colours are the flat ones.
                      _BlurTile(
                        key: blurTileKey,
                        selected: usingBlur,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          notifier.setBackgroundBlur();
                        },
                      ),
                      for (final colour in kBackgroundPresets)
                        _ColourTile(
                          key: tileKey(colour),
                          colour: colour,
                          selected: colour.toARGB32() == currentColour,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.setBackground(colour);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The photo tile's three meanings, by state: no photo → pick one; a photo
  /// resting while a colour is in use → use it again, no picker; the photo in
  /// use → pick a replacement.
  Future<void> _onPhotoTap(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final notifier = ref.read(videoEditorProvider.notifier);
    final state = ref.read(videoEditorProvider);
    if (state.backgroundImagePath != null &&
        state.backgroundType != EditorBackgroundType.image) {
      notifier.useBackgroundImage();
      return;
    }
    final picked = await (pickImage ?? _pickFromGallery)();
    if (picked == null) return;
    final ok = await notifier.importBackgroundImage(picked);
    if (!ok && context.mounted) {
      // Loudly, not silently: a tap that did nothing reads as a broken tile.
      ToastUtils.show(context, 'Could not use that photo.', isError: true);
    }
  }

  /// The grab handle, drawn exactly as every other sheet in the app draws it.
  Widget _handle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.path,
    required this.selected,
    required this.onTap,
  });

  final String? path;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = path;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: KeyedSubtree(
        key: BackgroundSheet.photoTileKey,
        child: SizedBox(
          width: BackgroundSheet.kTileSize,
          height: BackgroundSheet.kTileSize,
          child: photo == null
              ? const _EmptyPhotoTile()
              : _ChosenPhotoTile(path: photo, selected: selected),
        ),
      ),
    );
  }
}

/// The caption inside the photo tile: small, so the glyph stays the subject.
const TextStyle _kCaptionStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  height: 1.0,
);

/// No photo yet: a dashed frame, the add glyph and its caption — an
/// invitation, drawn in the palette's quiet tones so the colour tiles beside
/// it stay the loud ones.
class _EmptyPhotoTile extends StatelessWidget {
  const _EmptyPhotoTile();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedFramePainter(
        colour: AppColors.border,
        radius: 12,
        strokeWidth: 1.5,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.imagePlus,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(height: 5),
            Text(
              'Photo',
              style: _kCaptionStyle.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chosen photo, cover-fitted into the tile the way the engine cover-fits
/// it onto the canvas, its caption along the foot; the accent border and a
/// check when it is in use.
class _ChosenPhotoTile extends StatelessWidget {
  const _ChosenPhotoTile({required this.path, required this.selected});

  final String path;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primaryStart : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(path),
              fit: BoxFit.cover,
              // A missing file shows the glyph, never an exception: drafts
              // outlive cache folders.
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.surface,
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.image,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
            if (selected)
              Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: const Icon(LucideIcons.check, color: Colors.white, size: 22),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  'Photo',
                  textAlign: TextAlign.center,
                  style: _kCaptionStyle.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The blurred-clip fill: a soft two-tone tile with the aperture glyph and its
/// caption, in the same quiet tones as the empty photo tile.
class _BlurTile extends StatelessWidget {
  const _BlurTile({super.key, required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: BackgroundSheet.kTileSize,
        height: BackgroundSheet.kTileSize,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surfaceLight, AppColors.surface],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryStart : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.aperture,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(height: 5),
                Text(
                  'Blur',
                  style: _kCaptionStyle.copyWith(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            if (selected)
              const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(LucideIcons.check, color: AppColors.primaryStart, size: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ColourTile extends StatelessWidget {
  const _ColourTile({
    super.key,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The tile *is* the colour, so selection is the accent border plus a
    // check — and the check has to be legible on the tile's own colour, so it
    // is dark on light tiles and light on dark ones.
    final checkColour =
        colour.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: BackgroundSheet.kTileSize,
        height: BackgroundSheet.kTileSize,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryStart : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(LucideIcons.check, color: checkColour, size: 22)
            : null,
      ),
    );
  }
}

/// A rounded rectangle drawn as dashes: the empty photo tile's frame.
class _DashedFramePainter extends CustomPainter {
  const _DashedFramePainter({
    required this.colour,
    required this.radius,
    required this.strokeWidth,
  });

  final Color colour;
  final double radius;
  final double strokeWidth;

  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    for (final ui.PathMetric metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedFramePainter old) =>
      old.colour != colour || old.radius != radius || old.strokeWidth != strokeWidth;
}
