import 'dart:ui';

import '../../models/text_overlay_model.dart';
import '../text_glyph_layout.dart';
import 'caption_highlight.dart';
import 'caption_highlight_catalog.dart';

/// Where a caption's words sit among its glyphs, measured once.
///
/// **One definition for the canvas and the file.** The preview painter and
/// the export rasteriser both build this from the same glyph boxes
/// ([layoutTextGlyphs]), so a word's box, its pill and the line a karaoke
/// sweep crosses are the same rect in both.
class CaptionHighlightLayout {
  const CaptionHighlightLayout._({
    required this.highlight,
    required this.glyphWord,
    required this.wordBoxes,
    required this.wordRtl,
    required this.spans,
    required this.startSeconds,
    required this.spanSeconds,
  });

  /// Null for a text with no highlight, or no words to mark.
  static CaptionHighlightLayout? of(
    TextOverlayModel overlay,
    List<TextGlyphBox> glyphs,
  ) {
    final words = overlay.captionWords;
    if (overlay.highlight.isNone || words == null || words.isEmpty) return null;

    final glyphWord = [
      for (final g in glyphs) wordIndexForChar(words, g.charIndex),
    ];
    final boxes = List<Rect?>.filled(words.length, null);
    for (var i = 0; i < glyphs.length; i++) {
      final w = glyphWord[i];
      if (w < 0) continue;
      final box = glyphs[i].inkRect;
      boxes[w] = boxes[w]?.expandToInclude(box) ?? box;
    }
    final text = overlay.text;
    return CaptionHighlightLayout._(
      highlight: overlay.highlight,
      glyphWord: glyphWord,
      wordBoxes: boxes,
      wordRtl: [
        for (final w in words)
          w.textEnd <= text.length &&
              isRightToLeftWord(text.substring(w.textStart, w.textEnd)),
      ],
      spans: wordSpansOf(words),
      startSeconds: overlay.startTime.inMicroseconds / 1e6,
      spanSeconds: (overlay.endTime - overlay.startTime).inMicroseconds / 1e6,
    );
  }

  final CaptionHighlight highlight;

  /// Per glyph, the word it belongs to; -1 for a glyph between words.
  final List<int> glyphWord;

  /// Per word, the union of its glyphs' boxes, in box-local pixels; null for
  /// a word with no inked glyph.
  final List<Rect?> wordBoxes;

  final List<bool> wordRtl;
  final List<WordSpan> spans;
  final double startSeconds;
  final double spanSeconds;

  /// Word [word]'s state with the playhead at [timelineSeconds].
  WordHighlightState wordState(int word, double timelineSeconds) =>
      wordHighlightStateAt(
        style: highlight.style,
        t: timelineSeconds - startSeconds,
        words: spans,
        index: word,
        spanSeconds: spanSeconds,
      );

  /// The box behind word [word], or null for a word with no glyph.
  Rect? pillRect(int word) {
    final box = wordBoxes[word];
    if (box == null) return null;
    return captionPillRect(box, glyphHeight: box.height);
  }

  double pillRadius(int word) => captionPillRadius(wordBoxes[word]?.height ?? 0);
}
