import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../logic/overlay_box_fit.dart';
import '../services/video_thumbnail_service.dart';

/// The invisible box an overlay's selection frame and handles hang off.
///
/// GL draws the picture; this only has to be **the picture's shape**, so the
/// dotted frame hugs it. The shape is measured once per file and remembered:
/// a photo by decoding it tiny (which applies its EXIF orientation, where
/// reading the header alone would report a portrait phone photo as
/// landscape), a video from one thumbnail, which the provider scales with its
/// aspect intact and its rotation applied.
class OverlayContentBox extends StatefulWidget {
  const OverlayContentBox({
    super.key,
    required this.path,
    required this.isVideo,
    required this.box,
  });

  final String path;
  final bool isVideo;
  final double box;

  @override
  State<OverlayContentBox> createState() => _OverlayContentBoxState();
}

class _OverlayContentBoxState extends State<OverlayContentBox> {
  static final Map<String, double> _aspects = {};
  static final Map<String, Future<double?>> _pending = {};

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(OverlayContentBox old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path;
    if (_aspects.containsKey(path)) return;
    final future = _pending.putIfAbsent(
      path,
      () => widget.isVideo ? _videoAspect(path) : _imageAspect(path),
    );
    future.then((aspect) {
      _pending.remove(path);
      if (aspect != null) _aspects[path] = aspect;
      if (mounted && aspect != null) setState(() {});
    });
  }

  static Future<double?> _imageAspect(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      final codec = await ui.instantiateImageCodecFromBuffer(
        buffer,
        targetWidth: 64,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final aspect = image.height == 0 ? null : image.width / image.height;
      image.dispose();
      codec.dispose();
      return aspect;
    } catch (_) {
      return null;
    }
  }

  static Future<double?> _videoAspect(String path) async {
    try {
      final bytes = await VideoThumbnailService.instance.frameAtSize(
        path: path,
        timeMs: 0,
        width: 96,
        height: 96,
      );
      if (bytes == null) return null;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final aspect = image.height == 0 ? null : image.width / image.height;
      image.dispose();
      codec.dispose();
      return aspect;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = fittedOverlayBox(
      contentAspect: _aspects[widget.path],
      box: widget.box,
    );
    return SizedBox(width: size.width, height: size.height);
  }
}
