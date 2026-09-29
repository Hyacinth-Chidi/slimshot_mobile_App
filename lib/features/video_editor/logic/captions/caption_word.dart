import 'dart:math' as math;

/// One spoken word inside a caption: where it sits in the caption's text and
/// when it is said, **relative to the caption's own start** — so dragging a
/// caption bar moves its words with it.
///
/// Offsets are UTF-16, the unit `TextGlyphBox.charIndex` already counts in: a
/// glyph belongs to the word whose `[textStart, textEnd)` holds its index, with
/// no second way of counting characters.
class CaptionWord {
  const CaptionWord({
    required this.textStart,
    required this.textEnd,
    required this.start,
    required this.end,
  });

  /// UTF-16 offset of the word's first code unit, inclusive.
  final int textStart;

  /// UTF-16 offset just past the word, exclusive.
  final int textEnd;

  final Duration start;
  final Duration end;

  Map<String, dynamic> toJson() => {
        'from': textStart,
        'to': textEnd,
        'startMs': start.inMilliseconds,
        'endMs': end.inMilliseconds,
      };

  /// Null for an entry with nothing left to place once clamped into a text of
  /// [textLength] code units; otherwise non-negative, with an end never before
  /// its start. A hand-edited or damaged draft must open, not throw.
  static CaptionWord? fromJson(Object? json, int textLength) {
    if (json is! Map) return null;
    final from = _int(json['from']);
    final to = _int(json['to']);
    final startMs = _int(json['startMs']);
    final endMs = _int(json['endMs']);
    if (from == null || to == null || startMs == null || endMs == null) {
      return null;
    }
    final a = from.clamp(0, textLength);
    final b = to.clamp(a, textLength);
    if (b == a) return null;
    final s = math.max(0, startMs);
    return CaptionWord(
      textStart: a,
      textEnd: b,
      start: Duration(milliseconds: s),
      end: Duration(milliseconds: math.max(s, endMs)),
    );
  }

  /// The readable entries of [json], or null when it is not a list at all.
  static List<CaptionWord>? listFromJson(Object? json, int textLength) {
    if (json is! List) return null;
    return json
        .map((entry) => fromJson(entry, textLength))
        .whereType<CaptionWord>()
        .toList();
  }

  // Finite only: `1e400` decodes to infinity, and `toInt()` on it throws.
  static int? _int(Object? value) =>
      value is num && value.isFinite ? value.toInt() : null;

  @override
  bool operator ==(Object other) =>
      other is CaptionWord &&
      other.textStart == textStart &&
      other.textEnd == textEnd &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(textStart, textEnd, start, end);

  @override
  String toString() =>
      'CaptionWord([$textStart, $textEnd) ${start.inMilliseconds}–${end.inMilliseconds}ms)';
}
