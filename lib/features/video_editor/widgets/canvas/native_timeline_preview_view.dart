import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../services/native_timeline_preview_service.dart';

/// The native preview surface.
///
/// This is a Flutter [Texture], not a platform view. The native engine renders
/// its OpenGL output straight into a texture from Flutter's `TextureRegistry`,
/// which Flutter then composites like any other layer.
///
/// The earlier `AndroidView` version ran in virtual-display mode: a native
/// `TextureView` drew into a virtual display, and Flutter copied that display
/// into a texture every frame. That extra copy churned gralloc buffers per
/// frame and made playback visibly sluggish. Rendering into Flutter's own
/// texture removes the hop entirely.
class NativeTimelinePreviewView extends StatefulWidget {
  const NativeTimelinePreviewView({super.key, required this.service});

  final NativeTimelinePreviewService service;

  @override
  State<NativeTimelinePreviewView> createState() =>
      _NativeTimelinePreviewViewState();
}

class _NativeTimelinePreviewViewState extends State<NativeTimelinePreviewView> {
  int? _textureId;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.android) {
      _attachTexture();
    }
  }

  Future<void> _attachTexture() async {
    try {
      final textureId = await widget.service.initialize();
      if (!mounted) return;
      setState(() => _textureId = textureId);
    } catch (_) {
      // The engine reports its own failures over the event channel; there is
      // nothing useful to draw here, so fall through to the empty box.
    }
  }

  @override
  Widget build(BuildContext context) {
    final textureId = _textureId;
    if (textureId == null) return const SizedBox.expand();
    return Texture(textureId: textureId);
  }
}
