import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';

/// A complete starting look for a new text — the Text submenu's Templates.
///
/// **Not a preset.** The editor sheet's presets restyle a text that already
/// exists and deliberately leave its font alone. A template is where a text
/// *begins*: typeface, colours, stroke or box, alignment, size, its place on
/// the canvas and its animations, chosen together so they read as one look.
///
/// **A template makes an empty text.** [sampleText] is what its tile shows so
/// the look can be judged before it is chosen; it never reaches the project.
/// New text is created empty everywhere in this app, and one still empty when
/// the editor closes is deleted — so a sample word can never ride into an
/// export as a placeholder the user forgot to replace.
///
/// Every rule a template could break silently — a font the app cannot load,
/// an animation the user could not pick, a per-character animation over a
/// box that export would have to flatten — is pinned across the whole catalog
/// by `text_template_catalog_test.dart`.
class TextTemplate {
  const TextTemplate({
    required this.id,
    required this.name,
    required this.sampleText,
    required this.fontFamily,
    this.color = Colors.white,
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 0,
    this.backgroundColor = Colors.transparent,
    this.shadowColor = Colors.transparent,
    this.borderRadius = 16,
    this.backgroundPadding = 16,
    this.textAlign = 'center',
    this.scale = 1.0,
    this.placement = Offset.zero,
    this.inAnimation = 'none',
    this.outAnimation = 'none',
    this.loopAnimation = 'none',
  });

  final String id;

  /// What the tile is called.
  final String name;

  /// What the tile shows — never inserted. See the class comment.
  final String sampleText;

  /// One of `allFonts`, or the app cannot load it.
  final String fontFamily;

  final Color color;
  final Color strokeColor;
  final double strokeWidth;
  final Color backgroundColor;

  /// The shadow's colour. Its blur is not the template's to choose: it is
  /// [kTextShadowBlurRadius] whenever there is a shadow, as in the editor.
  final Color shadowColor;

  final double borderRadius;
  final double backgroundPadding;
  final String textAlign;
  final double scale;

  /// Where the text's centre sits, as a **fraction of the canvas** from its
  /// centre — `Offset(0, 0.3)` is three tenths of the canvas height below
  /// the middle. Fractions, not pixels, so a template lands in the same place
  /// on a phone and a tablet.
  final Offset placement;

  /// `text_animation_catalog.dart` ids, each in its own slot, or 'none'.
  final String inAnimation;
  final String outAnimation;
  final String loopAnimation;

  /// A new, **empty** text wearing this template, placed on [canvasSize].
  ///
  /// With no canvas known yet the text is centred; the canvas is also stored
  /// as the text's `referenceCanvasSize`, which is what makes its position a
  /// device-independent fraction thereafter.
  TextOverlayModel apply({
    required String id,
    required Duration startTime,
    required Duration endTime,
    Size? canvasSize,
  }) {
    return TextOverlayModel(
      id: id,
      // Empty on purpose — see the class comment.
      text: '',
      fontFamily: fontFamily,
      color: color,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      backgroundColor: backgroundColor,
      shadowColor: shadowColor,
      shadowBlurRadius:
          shadowColor == Colors.transparent ? 0.0 : kTextShadowBlurRadius,
      borderRadius: borderRadius,
      backgroundPadding: backgroundPadding,
      textAlign: textAlign,
      scale: scale,
      position: canvasSize == null
          ? Offset.zero
          : Offset(
              placement.dx * canvasSize.width,
              placement.dy * canvasSize.height,
            ),
      startTime: startTime,
      endTime: endTime,
      inAnimation: inAnimation,
      outAnimation: outAnimation,
      loopAnimation: loopAnimation,
      referenceCanvasSize: canvasSize,
    );
  }
}

/// The templates the Text submenu offers, in the order its sheet shows them.
///
/// **A boxed template only uses whole-block animations** (fade, zoom, slide,
/// pulse). Per-character animation cannot run over a background box — the
/// glyph pass draws letters only — so export would flatten it and warn on
/// every use. The rest are free to animate letter by letter.
const List<TextTemplate> kTextTemplates = [
  TextTemplate(
    id: 'title',
    name: 'Title',
    sampleText: 'TITLE',
    fontFamily: 'Bebas Neue',
    shadowColor: Colors.black,
    scale: 1.8,
    placement: Offset(0, -0.25),
    inAnimation: 'pop_in',
    outAnimation: 'fade_out',
  ),
  TextTemplate(
    id: 'subtitle',
    name: 'Subtitle',
    sampleText: 'Subtitle',
    fontFamily: 'Inter',
    strokeColor: Colors.black,
    strokeWidth: 3,
    scale: 0.9,
    placement: Offset(0, 0.33),
    inAnimation: 'fade_in',
    outAnimation: 'fade_out',
  ),
  TextTemplate(
    id: 'lower_third',
    name: 'Lower third',
    sampleText: 'Your name',
    fontFamily: 'Montserrat',
    backgroundColor: Colors.black87,
    borderRadius: 4,
    backgroundPadding: 8,
    textAlign: 'left',
    scale: 0.9,
    placement: Offset(-0.12, 0.27),
    inAnimation: 'slide_right',
    outAnimation: 'fade_out',
  ),
  TextTemplate(
    id: 'headline',
    name: 'Headline',
    sampleText: 'HEADLINE',
    fontFamily: 'Oswald',
    color: Colors.black,
    backgroundColor: Colors.white,
    borderRadius: 12,
    backgroundPadding: 10,
    scale: 1.2,
    placement: Offset(0, -0.3),
    inAnimation: 'slide_up',
    outAnimation: 'slide_down_out',
  ),
  TextTemplate(
    id: 'neon',
    name: 'Neon',
    sampleText: 'NEON',
    fontFamily: 'Righteous',
    color: Colors.cyanAccent,
    shadowColor: Colors.cyanAccent,
    scale: 1.4,
    inAnimation: 'fade_in',
    outAnimation: 'fade_out',
    loopAnimation: 'pulse_loop',
  ),
  TextTemplate(
    id: 'typewriter',
    name: 'Typewriter',
    sampleText: 'type...',
    fontFamily: 'Press Start 2P',
    shadowColor: Colors.black,
    scale: 0.8,
    inAnimation: 'typing',
    outAnimation: 'untyping',
  ),
  TextTemplate(
    id: 'handwritten',
    name: 'Handwritten',
    sampleText: 'Hello',
    fontFamily: 'Pacifico',
    shadowColor: Colors.black,
    scale: 1.3,
    placement: Offset(0, -0.1),
    inAnimation: 'wave_in',
    outAnimation: 'fade_out',
  ),
  TextTemplate(
    id: 'breaking',
    name: 'Breaking',
    sampleText: 'BREAKING',
    fontFamily: 'Poppins',
    backgroundColor: Colors.deepOrange,
    borderRadius: 6,
    backgroundPadding: 10,
    scale: 1.2,
    placement: Offset(0, 0.3),
    inAnimation: 'zoom_in',
    outAnimation: 'fade_out',
  ),
  TextTemplate(
    id: 'bounce',
    name: 'Bounce',
    sampleText: 'Wow!',
    fontFamily: 'Lobster',
    color: Colors.amber,
    strokeColor: Colors.black,
    strokeWidth: 3,
    scale: 1.5,
    inAnimation: 'bounce_in',
    outAnimation: 'pop_out',
  ),
];
