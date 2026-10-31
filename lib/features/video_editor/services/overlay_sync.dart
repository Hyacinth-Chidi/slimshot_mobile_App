import 'dart:convert';
import 'dart:ui' show Size;

import '../models/editor_timeline.dart';
import '../models/image_overlay_model.dart';
import '../models/video_editor_state.dart';
import '../models/video_overlay_model.dart';

/// Decides when the preview must be sent its overlays — photos, videos and
/// the texts the engine draws — only when they changed.
///
/// The screen asks on **every** state change — during playback that is a
/// position event about thirty times a second — so the common answer must be
/// cheap. Untouched lists keep their identity through `copyWith`, and the
/// text entries keep theirs until `PreviewTextAtlases` changes them, which
/// answers most calls without composing anything; a list rebuilt with the
/// same content is caught by the payload's text. A drag changes both, so it
/// goes out every frame of the drag. `EffectBarsSync` is the same rule for
/// the effect bars.
class OverlaySync {
  List<ImageOverlayModel>? _images;
  List<VideoOverlayModel>? _videos;
  List<EditorTimelineOverlay>? _texts;
  Size? _canvas;
  String? _sentSignature;

  /// The payload to send for [state], with [textEntries] on [canvasSize], or
  /// null when it is what was last sent. [compose] builds the payload
  /// (`NativeTimelinePreviewService.overlayPayload`).
  List<Map<String, dynamic>>? payloadFor(
    VideoEditorState state,
    Size canvasSize,
    List<EditorTimelineOverlay> textEntries,
    List<Map<String, dynamic>> Function(
      VideoEditorState state,
      Size canvasSize,
      List<EditorTimelineOverlay> textEntries,
    ) compose,
  ) {
    if (_sentSignature != null &&
        identical(state.imageOverlays, _images) &&
        identical(state.videoOverlays, _videos) &&
        identical(textEntries, _texts) &&
        canvasSize == _canvas) {
      return null;
    }
    _images = state.imageOverlays;
    _videos = state.videoOverlays;
    _texts = textEntries;
    _canvas = canvasSize;
    final payload = compose(state, canvasSize, textEntries);
    final signature = jsonEncode(payload);
    if (signature == _sentSignature) return null;
    _sentSignature = signature;
    return payload;
  }

  /// Forgets what was sent, so the next call sends — after a send failed, or
  /// with the preview unavailable for this project.
  void reset() {
    _images = null;
    _videos = null;
    _texts = null;
    _canvas = null;
    _sentSignature = null;
  }
}
