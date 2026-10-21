import 'dart:convert';

import '../models/effect_bar_model.dart';
import '../models/video_editor_state.dart';

/// Decides when the preview must be sent the effect bars: only when they
/// changed.
///
/// The screen asks on **every** state change — during playback that is a
/// position event about thirty times a second — so the common answer must be
/// cheap. An untouched list keeps its identity through `copyWith`, which
/// answers most calls without composing anything; a list rebuilt with the same
/// bars (an unrelated edit that copied it) is caught by the payload's text.
/// A bar dragged changes both, so it goes out every frame of the drag.
class EffectBarsSync {
  List<EffectBarModel>? _sentBars;
  String? _sentSignature;

  /// The payload to send for [state], or null when it is what was last sent.
  /// [compose] builds the payload (`NativeTimelinePreviewService.effectPayload`).
  List<Map<String, dynamic>>? payloadFor(
    VideoEditorState state,
    List<Map<String, dynamic>> Function(VideoEditorState state) compose,
  ) {
    if (_sentSignature != null && identical(state.effectBars, _sentBars)) {
      return null;
    }
    _sentBars = state.effectBars;
    final payload = compose(state);
    final signature = jsonEncode(payload);
    if (signature == _sentSignature) return null;
    _sentSignature = signature;
    return payload;
  }

  /// Forgets what was sent, so the next call sends — after a send failed, or
  /// a new engine came up that has heard nothing.
  void reset() {
    _sentBars = null;
    _sentSignature = null;
  }
}
