import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/effects/effect_preview_atlases.dart';
import '../../logic/effects/effect_preview_layout.dart';
import '../../logic/tile_preview_store.dart';

/// An effect tile's stage: the effect playing on the sample picture, or the
/// effect's icon while there is nothing to play.
///
/// The stage **owns its picture**. Every async step — the ask, the decode —
/// is checked against a generation bumped on dispose and on a change of
/// effect, and a picture that lands stale is disposed rather than dropped;
/// dispose frees the one painted and withdraws the tile's ask, so scrolling
/// a category never leaves atlases being drawn for nobody.
///
/// **The icon stands in only while the engine draws** — the first time an
/// effect is ever shown, since its atlas is then kept on the phone — or
/// where it could not be drawn, and the picture fades in over it
/// ([kTilePictureFadeIn]). An atlas held in memory or read back from the
/// phone shows the empty stage until it is decoded and then simply appears,
/// so nothing flickers from icon to picture on a scroll back or a relaunch.
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

  /// Whether the icon stands in for the picture: the engine is drawing it,
  /// or could not. Up until the picture arrives, which then fades in over it.
  bool _iconUp = false;

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
    _iconUp = false;
  }

  void _load() {
    final cached = widget.atlases.peek(widget.effectId);
    if (cached != null) {
      _decode(cached);
      return;
    }
    if (widget.atlases.hasFailed(widget.effectId)) {
      _iconUp = true;
      return;
    }
    _iconUp = !widget.atlases.isSaved(widget.effectId);
    final generation = _generation;
    final ticket = widget.atlases.request(widget.effectId);
    _ticket = ticket;
    ticket.atlas.then((bytes) {
      if (!mounted || generation != _generation) return;
      // Nothing came — failed, or the engine was busy: the icon stands in.
      if (bytes == null) {
        if (!_iconUp) setState(() => _iconUp = true);
        return;
      }
      setState(() => _decode(bytes));
    });
  }

  void _decode(Uint8List bytes) {
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
      });
    }, onError: (Object _) {
      if (!mounted || generation != _generation) return;
      setState(() => _iconUp = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final Widget stage;
    if (image != null) {
      stage = CustomPaint(
        key: const ValueKey('picture'),
        painter: EffectPreviewPainter(image, widget.frameIndex),
        size: Size.infinite,
      );
    } else if (_iconUp) {
      stage = Center(
        key: const ValueKey('icon'),
        child: Icon(
          widget.icon,
          color: widget.isSelected
              ? AppColors.textPrimary
              : AppColors.textSecondary,
          size: 22,
        ),
      );
    } else {
      // Held or kept bytes on their way in: the empty stage, never the icon —
      // a flicker from icon to picture on every scroll back, or every launch,
      // reads as the grid stuttering.
      stage = const SizedBox.expand(key: ValueKey('empty'));
    }
    return AnimatedSwitcher(
      duration: _iconUp ? kTilePictureFadeIn : Duration.zero,
      child: stage,
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
