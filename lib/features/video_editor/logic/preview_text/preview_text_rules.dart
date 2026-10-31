import 'dart:math' as math;
import 'dart:ui' show Size;

import '../../models/text_overlay_model.dart';

/// Which texts get a preview atlas made: those within this much of the
/// playhead. Ahead is generous — preparing while the user is paused means a
/// play from here meets texts the engine already has.
const double kPreviewTextPrepareBehindSeconds = 5.0;
const double kPreviewTextPrepareAheadSeconds = 30.0;

/// Which texts are sent to the engine. **This window is the GPU budget**:
/// the engine holds a texture only for what it is sent, so what is resident
/// is the text on screen and what starts within two seconds, however many
/// captions the project has. Two seconds is ample for a decode and an upload
/// ahead of a caption's first frame.
const double kPreviewTextSendBehindSeconds = 0.5;
const double kPreviewTextSendAheadSeconds = 2.0;

double _start(TextOverlayModel t) => t.startTime.inMicroseconds / 1e6;
double _end(TextOverlayModel t) => t.endTime.inMicroseconds / 1e6;

/// The ids of [texts] whose span meets `[playhead − behind, playhead + ahead]`.
///
/// Half-open like a text's own span: one that ended exactly at the window's
/// start is out, one starting exactly on its far edge is in.
Set<String> textsNear(
  Iterable<TextOverlayModel> texts,
  double playhead, {
  required double behind,
  required double ahead,
}) {
  final from = playhead - behind;
  final to = playhead + ahead;
  return {
    for (final t in texts)
      if (_start(t) <= to && _end(t) > from) t.id,
  };
}

/// The order to make atlases in: what is on screen, then what comes next in
/// the direction of play, then what has passed, nearest first.
List<String> previewAtlasOrder(Iterable<TextOverlayModel> texts, double playhead) {
  final live = <TextOverlayModel>[];
  final ahead = <TextOverlayModel>[];
  final behind = <TextOverlayModel>[];
  for (final t in texts) {
    if (_start(t) > playhead) {
      ahead.add(t);
    } else if (_end(t) > playhead) {
      live.add(t);
    } else {
      behind.add(t);
    }
  }
  live.sort((a, b) => _start(a).compareTo(_start(b)));
  ahead.sort((a, b) => _start(a).compareTo(_start(b)));
  behind.sort((a, b) => _end(b).compareTo(_end(a)));
  return [for (final t in [...live, ...ahead, ...behind]) t.id];
}

/// Whether [textId] is being edited: selected, with playback paused — every
/// edit pauses playback first. Flutter draws it then, so every change shows
/// in the frame it is made, as it always has.
bool isTextBeingEdited(
  String textId, {
  required String? selectedTextId,
  required bool isPlaying,
}) =>
    !isPlaying && selectedTextId == textId;

/// The preview texture's pixels per canvas pixel, never below 1: an atlas
/// drawn at the canvas's own density on a canvas larger than the texture
/// already has every pixel the texture can show.
double previewRasterScale({required Size textureSize, required Size canvasSize}) {
  final canvas = canvasSize.shortestSide;
  if (canvas <= 0) return 1.0;
  return math.max(1.0, textureSize.shortestSide / canvas);
}

const String _entryPrefix = 'text_';

/// The id a text's overlay entry carries — the export's own spelling.
String previewTextEntryId(String textId) => '$_entryPrefix$textId';

/// The text an entry id names, or null for an entry that is not a text's.
String? previewTextIdOf(String entryId) =>
    entryId.startsWith(_entryPrefix) ? entryId.substring(_entryPrefix.length) : null;
