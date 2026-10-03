import 'package:flutter/material.dart';

import '../../models/text_overlay_model.dart';
import '../text_look.dart';
import 'caption_highlight.dart';

/// A caption style: a whole look and a word highlight, chosen as one.
///
/// **No place and no size.** A preset that moved the set would undo the
/// user's own placement every time they tried a style, and a caption's size is
/// its Size ([kCaptionTextSize] until the user changes it), not a look.
class CaptionPreset {
  const CaptionPreset({
    required this.id,
    required this.name,
    required this.look,
    this.highlight = CaptionHighlight.none,
    this.sampleText = 'Say it loud',
  });

  final String id;

  /// What the tile is called.
  final String name;

  final TextLook look;
  final CaptionHighlight highlight;

  /// The words its tile plays the highlight over — never inserted.
  final String sampleText;

  /// Whether [caption] is wearing this preset: its look at any pace, and its
  /// highlight. Found, not remembered, so a hand edit makes no preset current.
  bool isAppliedTo(TextOverlayModel caption) =>
      look.sameLookAs(TextLook.of(caption)) && caption.highlight == highlight;
}

/// The look of the Classic style: bold white type with a black outline and a
/// soft shadow — the look the first device run approved. Bundled Montserrat
/// Bold, so a caption looks the same offline and on any phone.
const TextLook kCaptionClassicLook = TextLook(
  fontFamily: 'Montserrat Bold',
  strokeColor: Color(0xFF000000),
  strokeWidth: 4,
  shadowColor: Color(0xFF000000),
  shadowOpacity: 0.6,
  shadowBlur: 6,
  shadowDistance: 2,
  shadowAngle: 90,
);

const Color _yellow = Color(0xFFFFD60A);
const Color _green = Color(0xFF30D158);
const Color _purple = Color(0xFFBF5AF2);
const Color _blue = Color(0xFF0A84FF);
const Color _black = Color(0xFF000000);
const Color _white = Color(0xFFFFFFFF);

/// The look of the default style, Bubble: bold white type over a soft shadow.
const TextLook kDefaultCaptionLook = TextLook(
  fontFamily: 'Montserrat Bold',
  shadowColor: _black,
  shadowOpacity: 0.5,
  shadowBlur: 8,
  shadowDistance: 2,
  shadowAngle: 90,
);

/// The default style's highlight: a purple pill behind the word being spoken.
const CaptionHighlight kDefaultCaptionHighlight =
    CaptionHighlight(style: CaptionHighlightStyle.pill, color: _purple);

/// The style a project's first caption set is generated in — Bubble, chosen
/// on the device because it shows the highlight off from the first moment.
/// It is the grid's first tile, so "the first one" and "what I got" agree.
const CaptionPreset kDefaultCaptionPreset = CaptionPreset(
  id: 'bubble',
  name: 'Bubble',
  look: kDefaultCaptionLook,
  highlight: kDefaultCaptionHighlight,
);

/// The Size a caption set is generated at: letters a tenth of the frame —
/// a three-word phrase on one line, a full line wrapping to two. Device-
/// approved, when it was still a scale.
const double kCaptionTextSize = 100;

/// The style a new set is generated in, and its Size.
///
/// **The current set's, when there is one**: regenerating for a better
/// transcript must not undo the user's styling, hand tuning included. Read
/// from the **earliest** caption — splits and merges reorder the list, time
/// does not move. With no set, the default style at [kCaptionTextSize].
({TextLook look, CaptionHighlight highlight, double fontSize})
    captionStyleForNewSet(
  Iterable<TextOverlayModel> texts,
) {
  TextOverlayModel? earliest;
  for (final t in texts) {
    if (!t.isCaption) continue;
    if (earliest == null || t.startTime < earliest.startTime) earliest = t;
  }
  if (earliest == null) {
    return (
      look: kDefaultCaptionLook,
      highlight: kDefaultCaptionHighlight,
      fontSize: kCaptionTextSize,
    );
  }
  return (
    look: TextLook.of(earliest),
    highlight: earliest.highlight,
    fontSize: earliest.fontSize ?? kCaptionTextSize,
  );
}

/// The presets, in the order the grid shows them. The first is the default.
///
/// Captions carry no in or out animation: a half-second fade is most of a
/// one-second caption's life. The highlight is their motion.
const List<CaptionPreset> kCaptionPresets = [
  kDefaultCaptionPreset,
  CaptionPreset(id: 'classic', name: 'Classic', look: kCaptionClassicLook),
  CaptionPreset(
    id: 'karaoke',
    name: 'Karaoke',
    look: kCaptionClassicLook,
    highlight: CaptionHighlight(
      style: CaptionHighlightStyle.karaoke,
      color: _yellow,
    ),
  ),
  CaptionPreset(
    id: 'pop',
    name: 'Pop',
    look: TextLook(
      fontFamily: 'Montserrat Bold',
      strokeColor: _black,
      strokeWidth: 5,
      shadowColor: _black,
      shadowOpacity: 0.6,
      shadowBlur: 6,
      shadowDistance: 2,
      shadowAngle: 90,
    ),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.pop, color: _green),
  ),
  CaptionPreset(
    id: 'boxed',
    name: 'Boxed',
    look: TextLook(
      fontFamily: 'Montserrat Bold',
      backgroundColor: Color(0xBF000000),
      borderRadius: 10,
      backgroundPadding: 12,
    ),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.colour, color: _yellow),
  ),
  CaptionPreset(
    id: 'impact',
    name: 'Impact',
    sampleText: 'BIG NEWS TODAY',
    look: TextLook(
      fontFamily: 'Bebas Neue',
      color: _yellow,
      strokeColor: _black,
      strokeWidth: 4,
      shadowColor: _black,
      shadowOpacity: 0.8,
      shadowBlur: 0,
      shadowDistance: 4,
      shadowAngle: 90,
    ),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.colour, color: _white),
  ),
  CaptionPreset(
    id: 'neon',
    name: 'Neon',
    look: TextLook(
      fontFamily: 'Righteous',
      shadowColor: _blue,
      shadowOpacity: 1,
      shadowBlur: 12,
      shadowDistance: 0,
      shadowAngle: 90,
    ),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.colour, color: _blue),
  ),
  CaptionPreset(
    id: 'reveal',
    name: 'Reveal',
    look: TextLook(
      fontFamily: 'Poppins',
      shadowColor: _black,
      shadowOpacity: 0.7,
      shadowBlur: 10,
      shadowDistance: 2,
      shadowAngle: 90,
    ),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.reveal),
  ),
  CaptionPreset(
    id: 'focus',
    name: 'Focus',
    look: kCaptionClassicLook,
    highlight: CaptionHighlight(style: CaptionHighlightStyle.focus),
  ),
];
