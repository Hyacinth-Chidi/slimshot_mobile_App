import 'dart:math' as math;

import 'caption_word.dart';

/// What each highlight style does to a word, as a **pure function** of time.
///
/// Three consumers read it and nothing else may describe a highlight: the
/// preview painter, the Kotlin port `CaptionHighlightCurves.kt` that the
/// export uses, and the preset tiles. `test/fixtures/caption_highlight_fixture.json`
/// pins the Dart and the Kotlin together — the text-animation fixture's
/// mechanism, with its caveat: it catches divergence tomorrow, never a wrong
/// curve today.

/// How the word being spoken is marked.
///
/// Appended to, never reordered: the name is what a draft stores.
enum CaptionHighlightStyle {
  none,

  /// The active word is drawn in the highlight colour.
  colour,

  /// Colour, and the word swells and settles as it starts.
  pop,

  /// A rounded box in the highlight colour behind the active word; the text
  /// keeps its own colour.
  pill,

  /// The highlight colour sweeps across each word as it is spoken; spoken
  /// words stay lit.
  karaoke,

  /// Words appear as they are spoken.
  reveal,

  /// Words not being spoken are dimmed.
  focus,
}

/// The styles a user can choose — every one but none.
const List<CaptionHighlightStyle> kSelectableHighlightStyles = [
  CaptionHighlightStyle.colour,
  CaptionHighlightStyle.pop,
  CaptionHighlightStyle.pill,
  CaptionHighlightStyle.karaoke,
  CaptionHighlightStyle.reveal,
  CaptionHighlightStyle.focus,
];

String captionHighlightLabel(CaptionHighlightStyle style) => switch (style) {
      CaptionHighlightStyle.none => 'None',
      CaptionHighlightStyle.colour => 'Colour',
      CaptionHighlightStyle.pop => 'Pop',
      CaptionHighlightStyle.pill => 'Pill',
      CaptionHighlightStyle.karaoke => 'Karaoke',
      CaptionHighlightStyle.reveal => 'Reveal',
      CaptionHighlightStyle.focus => 'Focus',
    };

/// How long scale, pill and opacity take to settle. **Colour never ramps**:
/// a glyph drawn half in each look would cast its shadow twice.
const double kHighlightRampSeconds = 0.08;

/// Pop: how far the word swells, and how long the swell takes to settle.
const double kHighlightPopScale = 1.15;
const double kHighlightPopSeconds = 0.25;

/// Focus: how present a word not being spoken is.
const double kHighlightFocusDim = 0.5;

/// One word's spoken span, in seconds **relative to the caption's start**.
class WordSpan {
  const WordSpan(this.start, this.end);

  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is WordSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'WordSpan($start–$end)';
}

/// What a word looks like at an instant.
class WordHighlightState {
  const WordHighlightState({
    this.highlighted = false,
    this.fill = 0,
    this.scale = 1,
    this.opacity = 1,
    this.pill = 0,
  });

  /// Drawn whole in the highlight colour.
  final bool highlighted;

  /// Karaoke: how much of the word, from its leading edge, is in the
  /// highlight colour. 0..1.
  final double fill;

  /// About the **word's** centre.
  final double scale;

  /// 0..1, multiplying the glyph's own.
  final double opacity;

  /// How present the box behind the word is. 0..1.
  final double pill;

  static const WordHighlightState resting = WordHighlightState();

  @override
  bool operator ==(Object other) =>
      other is WordHighlightState &&
      other.highlighted == highlighted &&
      other.fill == fill &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.pill == pill;

  @override
  int get hashCode => Object.hash(highlighted, fill, scale, opacity, pill);

  @override
  String toString() =>
      'WordHighlightState(hl=$highlighted fill=$fill scale=$scale '
      'opacity=$opacity pill=$pill)';
}

/// [CaptionWord]s as spans in seconds.
List<WordSpan> wordSpansOf(List<CaptionWord> words) => [
      for (final w in words)
        WordSpan(w.start.inMicroseconds / 1e6, w.end.inMicroseconds / 1e6),
    ];

/// The word whose text range holds the glyph at [charIndex], or -1 for a
/// glyph between words — a dash, a stray mark — which draws in the base look.
int wordIndexForChar(List<CaptionWord> words, int charIndex) {
  for (var i = 0; i < words.length; i++) {
    if (charIndex >= words[i].textStart && charIndex < words[i].textEnd) {
      return i;
    }
  }
  return -1;
}

double _ramp(double elapsed) =>
    (elapsed / kHighlightRampSeconds).clamp(0.0, 1.0).toDouble();

/// Word [index]'s state at [t] seconds into a caption of [spanSeconds].
///
/// **A word is active from its start until the next word starts**; the last
/// word until the caption ends. Before the first word nothing is active —
/// the caption shows a moment before its first word. Word times are clamped
/// to the caption's span, because a caption can end a little before its last
/// word does (the next caption's lead takes that room).
WordHighlightState wordHighlightStateAt({
  required CaptionHighlightStyle style,
  required double t,
  required List<WordSpan> words,
  required int index,
  required double spanSeconds,
}) {
  if (style == CaptionHighlightStyle.none ||
      index < 0 ||
      index >= words.length) {
    return WordHighlightState.resting;
  }
  final span = math.max(0.0, spanSeconds);
  double clamp(double v) => v.clamp(0.0, span).toDouble();

  final word = words[index];
  final start = clamp(word.start);
  final end = math.max(start, clamp(word.end));
  final activeEnd =
      index + 1 < words.length ? math.max(start, clamp(words[index + 1].start)) : span;
  final active = t >= start && (index == words.length - 1 || t < activeEnd);
  final spoken = t >= start;
  final elapsed = t - start;

  switch (style) {
    case CaptionHighlightStyle.none:
      return WordHighlightState.resting;
    case CaptionHighlightStyle.colour:
      return WordHighlightState(highlighted: active);
    case CaptionHighlightStyle.pop:
      if (!active) return WordHighlightState.resting;
      final p = (elapsed / kHighlightPopSeconds).clamp(0.0, 1.0);
      return WordHighlightState(
        highlighted: true,
        scale: 1 + (kHighlightPopScale - 1) * math.sin(math.pi * p),
      );
    case CaptionHighlightStyle.pill:
      return WordHighlightState(pill: active ? _ramp(elapsed) : 0);
    case CaptionHighlightStyle.karaoke:
      if (!spoken) return WordHighlightState.resting;
      final length = end - start;
      final fill = length <= 0 ? 1.0 : (elapsed / length).clamp(0.0, 1.0).toDouble();
      return WordHighlightState(highlighted: fill >= 1, fill: fill);
    case CaptionHighlightStyle.reveal:
      return WordHighlightState(opacity: spoken ? _ramp(elapsed) : 0);
    case CaptionHighlightStyle.focus:
      return WordHighlightState(opacity: active ? 1 : kHighlightFocusDim);
  }
}
