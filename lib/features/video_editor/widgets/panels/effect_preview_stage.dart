import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/effects/effect_preview_atlases.dart';
import '../../logic/effects/effect_preview_layout.dart';

/// Decodes an effect's atlas into a picture the tile owns.
///
/// Deliberately not `Image.memory`, which puts every decoded picture into
/// Flutter's shared image cache — up to 100 MB held until something evicts
/// it. A `ui.Image` decoded here has one owner, the stage, and one `dispose`.
typedef EffectAtlasDecoder = Future<ui.Image> Function(Uint8List bytes);

/// The default decoder: the bytes, whole, no resize — an atlas is already
/// drawn at its final size.
Future<ui.Image> decodeEffectAtlas(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// An effect tile's stage: the effect playing on the sample picture, or the
/// effect's icon while there is nothing to play.
///
/// The stage **owns its picture**. Every async step — the ask, the decode —
/// is checked against a generation bumped on dispose and on a change of
/// effect, and a picture that lands stale is disposed rather than dropped;
/// dispose frees the one painted and withdraws the tile's ask, so scrolling
/// a category never leaves atlases being drawn for nobody. The icon shows
/// while an effect has no atlas yet or could not be drawn; cached bytes
/// decoding show the empty stage instead, so nothing flickers from icon to
/// picture on a scroll back.
class EffectPreviewStage extends StatefulWidget {
  const EffectPreviewStage({
    super.key,
    required this.effectId,
    required this.icon,
    required this.isSelected,
    required this.atlases,
    required this.frameIndex,
    this.decode = decodeEffectAtlas,
  });

  final String effectId;
  final IconData icon;
  final bool isSelected;
  final EffectPreviewAtlases atlases;

  /// The sheet's shared clock, reduced to the frame to show — one listenable
  /// every tile repaints from, only when the frame changes.
  final ValueListenable<int> frameIndex;

  final EffectAtlasDecoder decode;

  @override
  State<EffectPreviewStage> createState() => _EffectPreviewStageState();
}

class _EffectPreviewStageState extends State<EffectPreviewStage> {
  ui.Image? _image;
  EffectPreviewTicket? _ticket;
  bool _decoding = false;

  /// Bumped on dispose and on a change of effect; an async step whose
  /// generation no longer matches owns nothing and frees what it got.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EffectPreviewStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectId == widget.effectId) return;
    _reset();
    _load();
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  void _reset() {
    _generation++;
    _ticket?.withdraw();
    _ticket = null;
    _image?.dispose();
    _image = null;
    _decoding = false;
  }

  void _load() {
    final cached = widget.atlases.peek(widget.effectId);
    if (cached != null) {
      _decode(cached);
      return;
    }
    if (widget.atlases.hasFailed(widget.effectId)) return;
    final generation = _generation;
    final ticket = widget.atlases.request(widget.effectId);
    _ticket = ticket;
    ticket.atlas.then((bytes) {
      if (!mounted || generation != _generation || bytes == null) return;
      setState(() => _decode(bytes));
    });
  }

  void _decode(Uint8List bytes) {
    _decoding = true;
    final generation = _generation;
    widget.decode(bytes).then((image) {
      if (!mounted || generation != _generation) {
        // Landed for a tile that is gone or shows another effect: the image
        // is this continuation's to free, or it leaks for the session.
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _decoding = false;
      });
    }, onError: (Object _) {
      if (!mounted || generation != _generation) return;
      setState(() => _decoding = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image != null) {
      return CustomPaint(
        painter: EffectPreviewPainter(image, widget.frameIndex),
        size: Size.infinite,
      );
    }
    // Cached bytes decoding: the empty stage, never the icon — a flicker from
    // icon to picture on every scroll back reads as the grid stuttering.
    if (_decoding) return const SizedBox.expand();
    return Center(
      child: Icon(
        widget.icon,
        color:
            widget.isSelected ? AppColors.textPrimary : AppColors.textSecondary,
        size: 22,
      ),
    );
  }
}

/// Paints the atlas cell [frameIndex] names, cover-fitted — repainting when
/// the frame changes ([CustomPainter]'s own `repaint`), not on every vsync.
class EffectPreviewPainter extends CustomPainter {
  EffectPreviewPainter(this.image, this.frameIndex) : super(repaint: frameIndex);

  final ui.Image image;
  final ValueListenable<int> frameIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final src = effectPreviewCellRect(frameIndex.value);
    final scale =
        (size.width / src.width).clamp(size.height / src.height, double.infinity);
    final dst = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: src.width * scale,
      height: src.height * scale,
    );
    canvas.clipRect(Offset.zero & size);
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(EffectPreviewPainter oldDelegate) =>
      oldDelegate.image != image;
}
