import 'dart:ui';

import 'caption_highlight_catalog.dart';

export 'caption_highlight_catalog.dart'
    show CaptionHighlightStyle, kSelectableHighlightStyles, captionHighlightLabel;

/// The colour a highlight starts in.
const Color kCaptionHighlightDefaultColor = Color(0xFFFFD60A);

/// The colours the sheet offers for a highlight.
const List<Color> kCaptionHighlightColors = [
  Color(0xFFFFD60A),
  Color(0xFFFF9F0A),
  Color(0xFFFF375F),
  Color(0xFFBF5AF2),
  Color(0xFF0A84FF),
  Color(0xFF30D158),
  Color(0xFFFFFFFF),
  Color(0xFF000000),
];

/// A caption's word highlight: which style, in which colour.
///
/// **One colour.** It is what lights the word — the fill for Colour, Pop and
/// Karaoke, the box for Pill. Stage 4's presets pair text and box colours as
/// whole looks; a second field here would be a second control for one look.
class CaptionHighlight {
  const CaptionHighlight({
    required this.style,
    this.color = kCaptionHighlightDefaultColor,
  });

  static const CaptionHighlight none =
      CaptionHighlight(style: CaptionHighlightStyle.none);

  final CaptionHighlightStyle style;
  final Color color;

  bool get isNone => style == CaptionHighlightStyle.none;

  CaptionHighlight copyWith({CaptionHighlightStyle? style, Color? color}) =>
      CaptionHighlight(style: style ?? this.style, color: color ?? this.color);

  Map<String, dynamic> toJson() => {
        'style': style.name,
        'color': color.toARGB32(),
      };

  /// [none] for anything unreadable, so a damaged draft still opens.
  static CaptionHighlight fromJson(Object? json) {
    if (json is! Map) return none;
    final style = CaptionHighlightStyle.values.asNameMap()[json['style']];
    if (style == null) return none;
    final color = json['color'];
    return CaptionHighlight(
      style: style,
      color: color is int ? Color(color) : kCaptionHighlightDefaultColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionHighlight && other.style == style && other.color == color;

  @override
  int get hashCode => Object.hash(style, color);

  @override
  String toString() => 'CaptionHighlight(${style.name}, $color)';
}

/// The box behind a word, from the word's ink and its glyph height: room on
/// every side, more at the ends.
Rect captionPillRect(Rect wordInk, {required double glyphHeight}) =>
    Rect.fromLTRB(
      wordInk.left - glyphHeight * 0.3,
      wordInk.top - glyphHeight * 0.14,
      wordInk.right + glyphHeight * 0.3,
      wordInk.bottom + glyphHeight * 0.14,
    );

double captionPillRadius(double glyphHeight) => glyphHeight * 0.3;
