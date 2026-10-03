import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

/// A text's look has one definition, so templates and caption presets — and
/// whatever restyles text next — cannot each keep their own list of fields.
void main() {
  /// Every field set to something other than its default.
  final rich = TextOverlayModel(
    id: 'rich',
    text: 'Styled',
    color: const Color(0xFFFF0000),
    fontFamily: 'Oswald',
    backgroundColor: const Color(0x80000000),
    strokeColor: const Color(0xFF00FF00),
    strokeWidth: 3,
    shadowColor: const Color(0xFF0000FF),
    shadowBlurRadius: 12,
    shadowOpacity: 0.4,
    shadowDistance: 9,
    shadowAngle: 200,
    borderRadius: 7,
    backgroundPadding: 21,
    textAlign: 'left',
    position: const Offset(10, 20),
    scale: 2,
    rotation: 0.3,
    boxWidth: 180,
    startTime: const Duration(seconds: 1),
    endTime: const Duration(seconds: 3),
    inAnimation: 'typing',
    outAnimation: 'fade_out',
    loopAnimation: 'wave_loop',
    animationInDuration: 1.5,
    animationOutDuration: 1.5,
    loopSpeed: 2,
    laneIndex: 2,
    referenceCanvasSize: const Size(400, 700),
    opacity: 0.8,
    captionSetId: 's',
    captionWords: const [
      CaptionWord(textStart: 0, textEnd: 6, start: Duration.zero, end: Duration(milliseconds: 400)),
    ],
    highlight: const CaptionHighlight(style: CaptionHighlightStyle.pop),
  );

  final plain = TextOverlayModel(id: 'plain', text: 'Plain');

  /// The serialised fields that are a text's look.
  const lookKeys = {
    'color',
    'fontFamily',
    'backgroundColor',
    'strokeColor',
    'strokeWidth',
    'shadowColor',
    'shadowBlurRadius',
    'shadowOpacity',
    'shadowDistance',
    'shadowAngle',
    'borderRadius',
    'backgroundPadding',
    'textAlign',
    'inAnimation',
    'outAnimation',
    'loopAnimation',
    'animationInDuration',
    'animationOutDuration',
    'loopSpeed',
  };

  /// The serialised fields that are not: the words, when and where the text
  /// is, its size and motion, its lane, and what makes it a caption.
  const notLookKeys = {
    'id',
    'text',
    'positionX',
    'positionY',
    'scale',
    'rotation',
    'boxWidth',
    'startTimeMs',
    'endTimeMs',
    'animationSchema',
    'laneIndex',
    'refWidth',
    'refHeight',
    'opacity',
    'keyframes',
    'captionSetId',
    'captionWords',
    'highlight',
  };

  test('every field a text serialises is either part of its look or not', () {
    // A field added to the model and to its JSON fails here until it is
    // classified — and if it is a look field, `TextLook` has to carry it, or
    // a template or caption preset would leave it behind.
    final keys = rich.toJson().keys.toSet();
    expect(keys.difference(lookKeys.union(notLookKeys)), isEmpty,
        reason: 'classify the new field');
    expect(lookKeys.intersection(notLookKeys), isEmpty);
  });

  test("a look carries every look field across, and nothing else", () {
    final restyled = TextLook.of(rich).applyTo(plain).toJson();
    final source = rich.toJson();
    final before = plain.toJson();
    for (final key in source.keys) {
      if (lookKeys.contains(key)) {
        expect(restyled[key], source[key], reason: key);
      } else {
        expect(restyled[key], before[key], reason: key);
      }
    }
  });

  test('the same look ignores speeds, which are pace, not look', () {
    final look = TextLook.of(rich);
    final faster = TextLook.of(rich.copyWith(
      animationInDuration: 3,
      animationOutDuration: 3,
      loopSpeed: 0.5,
    ));
    expect(look.sameLookAs(faster), isTrue);
    expect(look == faster, isFalse);
    expect(look.sameLookAs(TextLook.of(rich.copyWith(color: Colors.white))), isFalse);
    expect(look.sameLookAs(TextLook.of(rich.copyWith(shadowAngle: 10))), isFalse);
    expect(look.sameLookAs(TextLook.of(rich.copyWith(loopAnimation: 'none'))), isFalse);
  });

  test('equal looks are equal and hash alike', () {
    expect(TextLook.of(rich), TextLook.of(rich.copyWith(text: 'Other', scale: 4)));
    expect(
      TextLook.of(rich).hashCode,
      TextLook.of(rich.copyWith(text: 'Other')).hashCode,
    );
  });
}
