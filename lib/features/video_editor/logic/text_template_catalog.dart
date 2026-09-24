import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';

/// A complete look for a text — typeface, colours, outline or box, shadow,
/// alignment, size and animations, chosen together so they read as one.
///
/// **Two ways in.** The Text submenu's Templates makes a new text wearing one
/// ([apply]) and opens the keyboard: choose, then type. The text's own
/// Templates tab puts one on a text that already has words ([restyle]), and
/// swaps it for another as often as the user likes: type, then choose. Both
/// are the same operation — [apply] is [restyle] on an empty text.
///
/// **Not a preset.** The Style tab's presets restyle colours and leave the
/// font alone; a template is the whole look, font and motion included.
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
    this.shadowOpacity = kTextShadowDefaultOpacity,
    this.shadowBlur = kTextShadowDefaultBlur,
    this.shadowDistance = kTextShadowDefaultDistance,
    this.shadowAngle = kTextShadowDefaultAngle,
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

  /// The shadow's colour. The rest of the shadow — opacity, blur, distance,
  /// angle — starts at the defaults every new shadow has, so the Style tab
  /// takes it from there.
  final Color shadowColor;

  /// The rest of the shadow, as the Style tab's controls would set it.
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowDistance;
  final double shadowAngle;

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
    return restyle(
      TextOverlayModel(
        id: id,
        // Empty on purpose — see the class comment.
        text: '',
        position: canvasSize == null
            ? Offset.zero
            : Offset(
                placement.dx * canvasSize.width,
                placement.dy * canvasSize.height,
              ),
        startTime: startTime,
        endTime: endTime,
        referenceCanvasSize: canvasSize,
      ),
    );
  }

  /// [text] wearing this template: its words, timing, place, rotation, box
  /// width and lane kept; **every** part of the look replaced.
  ///
  /// Every look field is written, including the ones this template leaves
  /// empty — no outline, no box, no shadow — so changing from one template to
  /// another leaves nothing of the first behind. Animations restart at their
  /// natural pace: a speed the user tuned for the old motion means nothing to
  /// the new one. The size is the template's, because a title and a caption
  /// differ in size as much as in anything; the place is the user's.
  TextOverlayModel restyle(TextOverlayModel text) => text.copyWith(
        fontFamily: fontFamily,
        color: color,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        backgroundColor: backgroundColor,
        borderRadius: borderRadius,
        backgroundPadding: backgroundPadding,
        shadowColor: shadowColor,
        shadowOpacity: shadowOpacity,
        shadowBlurRadius: shadowBlur,
        shadowDistance: shadowDistance,
        shadowAngle: shadowAngle,
        textAlign: textAlign,
        scale: scale,
        inAnimation: inAnimation,
        outAnimation: outAnimation,
        loopAnimation: loopAnimation,
        animationInDuration: kTextAnimationNaturalSpeed,
        animationOutDuration: kTextAnimationNaturalSpeed,
        loopSpeed: kTextAnimationNaturalSpeed,
      );

  /// Whether [text] is wearing this template — what the Templates tab
  /// highlights.
  ///
  /// The look only. Size is left out because it is also placement: a text
  /// pinched bigger after choosing a template is still wearing it. Speeds are
  /// left out for the same reason. Any hand edit to the look — a colour, the
  /// font, an animation — means it is no longer this template.
  bool isAppliedTo(TextOverlayModel text) =>
      text.fontFamily == fontFamily &&
      text.color == color &&
      text.strokeColor == strokeColor &&
      text.strokeWidth == strokeWidth &&
      text.backgroundColor == backgroundColor &&
      text.borderRadius == borderRadius &&
      text.backgroundPadding == backgroundPadding &&
      text.shadowColor == shadowColor &&
      text.shadowOpacity == shadowOpacity &&
      text.shadowBlurRadius == shadowBlur &&
      text.shadowDistance == shadowDistance &&
      text.shadowAngle == shadowAngle &&
      text.textAlign == textAlign &&
      text.inAnimation == inAnimation &&
      text.outAnimation == outAnimation &&
      text.loopAnimation == loopAnimation;
}

/// The templates, in the order their grids show them.
///
/// Built from everything a text can do: a **glow** is a shadow at distance 0
/// with a wide blur in the text's own hue, a **retro** or **comic** drop is a
/// hard shadow — blur 0 — pushed well clear of the letters, and a caption box
/// carries the words over busy footage.
///
/// **A boxed template only uses whole-block animations** (fade, zoom, slide,
/// pulse). Per-character animation cannot run over a background box — the
/// glyph pass draws letters only — so export would flatten it and warn on
/// every use. The rest are free to animate letter by letter.
///
/// Room to grow: when text gains a feature, a template that shows it off is
/// one more entry here. Every rule an entry could break is pinned by
/// `text_template_catalog_test.dart`.
const List<TextTemplate> kTextTemplates = [
  // A big title over anything: tall condensed caps, a soft shadow beneath.
  TextTemplate(
    id: 'title',
    name: 'Title',
    sampleText: 'TITLE',
    fontFamily: 'Bebas Neue',
    shadowColor: Color(0xFF000000),
    shadowOpacity: 0.55,
    shadowBlur: 12,
    shadowDistance: 6,
    shadowAngle: 90,
    scale: 1.8,
    placement: Offset(0, -0.28),
    inAnimation: 'pop_in',
    outAnimation: 'fade_out',
  ),
  // A neon tube: a pale core, the colour carried entirely by the glow.
  TextTemplate(
    id: 'neon',
    name: 'Neon',
    sampleText: 'NEON',
    fontFamily: 'Righteous',
    color: Color(0xFFE9FDFF),
    shadowColor: Color(0xFF00E5FF),
    shadowOpacity: 1,
    shadowBlur: 18,
    shadowDistance: 0,
    scale: 1.5,
    inAnimation: 'fade_in',
    outAnimation: 'fade_out',
    loopAnimation: 'pulse_loop',
  ),
  // A sticker that pops: fat outline and a hard drop in the same ink.
  TextTemplate(
    id: 'comic',
    name: 'Comic',
    sampleText: 'BOOM!',
    fontFamily: 'Permanent Marker',
    strokeColor: Color(0xFF111111),
    strokeWidth: 6,
    shadowColor: Color(0xFF111111),
    shadowOpacity: 1,
    shadowBlur: 0,
    shadowDistance: 7,
    shadowAngle: 60,
    scale: 1.4,
    inAnimation: 'pop_in',
    outAnimation: 'bounce_out',
  ),
  // Social caption: rounded type on a soft, translucent pill.
  TextTemplate(
    id: 'caption',
    name: 'Caption',
    sampleText: 'Caption',
    fontFamily: 'Nunito',
    backgroundColor: Color(0x99000000),
    borderRadius: 12,
    backgroundPadding: 10,
    scale: 0.9,
    placement: Offset(0, 0.33),
    inAnimation: 'fade_in',
    outAnimation: 'fade_out',
  ),
  // Classic subtitle: an outline that reads on any footage, a shadow to lift it.
  TextTemplate(
    id: 'subtitle',
    name: 'Subtitle',
    sampleText: 'Subtitle',
    fontFamily: 'Inter',
    strokeColor: Color(0xFF000000),
    strokeWidth: 3,
    shadowColor: Color(0xFF000000),
    shadowOpacity: 0.6,
    shadowBlur: 6,
    shadowDistance: 2,
    shadowAngle: 90,
    scale: 0.9,
    placement: Offset(0, 0.36),
    inAnimation: 'fade_in',
    outAnimation: 'fade_out',
  ),
  // A name on screen: a dark bar sliding in from the left.
  TextTemplate(
    id: 'lower_third',
    name: 'Lower third',
    sampleText: 'Your name',
    fontFamily: 'Montserrat',
    backgroundColor: Color(0xE6111111),
    borderRadius: 4,
    backgroundPadding: 10,
    textAlign: 'left',
    scale: 0.9,
    placement: Offset(-0.12, 0.28),
    inAnimation: 'slide_right',
    outAnimation: 'slide_left_out',
  ),
  // A headline on a bold yellow block.
  TextTemplate(
    id: 'headline',
    name: 'Headline',
    sampleText: 'HEADLINE',
    fontFamily: 'Oswald',
    color: Color(0xFF111111),
    backgroundColor: Color(0xFFFFD60A),
    borderRadius: 2,
    backgroundPadding: 12,
    scale: 1.2,
    placement: Offset(0, -0.3),
    inAnimation: 'slide_down',
    outAnimation: 'slide_up_out',
  ),
  // News banner: white on red, zooming in and out.
  TextTemplate(
    id: 'breaking',
    name: 'Breaking',
    sampleText: 'BREAKING',
    fontFamily: 'Poppins',
    backgroundColor: Color(0xFFE63946),
    borderRadius: 6,
    backgroundPadding: 10,
    scale: 1.1,
    placement: Offset(0, 0.3),
    inAnimation: 'zoom_in',
    outAnimation: 'zoom_out_out',
  ),
  // Seventies poster: warm display type with a hard raspberry drop.
  TextTemplate(
    id: 'retro',
    name: 'Retro',
    sampleText: 'Retro',
    fontFamily: 'Abril Fatface',
    color: Color(0xFFFFD23F),
    shadowColor: Color(0xFFEE4266),
    shadowOpacity: 1,
    shadowBlur: 0,
    shadowDistance: 6,
    shadowAngle: 45,
    scale: 1.5,
    inAnimation: 'bounce_in',
    outAnimation: 'pop_out',
  ),
  // A neon sign in handwriting: a thin script lit pink.
  TextTemplate(
    id: 'glow',
    name: 'Glow',
    sampleText: 'Glow',
    fontFamily: 'Sacramento',
    color: Color(0xFFFFF0FA),
    shadowColor: Color(0xFFFF2BD6),
    shadowOpacity: 1,
    shadowBlur: 14,
    shadowDistance: 0,
    scale: 2.0,
    inAnimation: 'rise_in',
    outAnimation: 'fade_out',
  ),
  // Quiet and refined: a serif in ivory on a long, soft shadow.
  TextTemplate(
    id: 'elegant',
    name: 'Elegant',
    sampleText: 'Elegant',
    fontFamily: 'Playfair Display',
    color: Color(0xFFFFF6E5),
    shadowColor: Color(0xFF000000),
    shadowOpacity: 0.5,
    shadowBlur: 14,
    shadowDistance: 4,
    shadowAngle: 90,
    scale: 1.3,
    inAnimation: 'fade_in',
    outAnimation: 'fade_out',
  ),
  // A terminal typing itself out, phosphor green.
  TextTemplate(
    id: 'typewriter',
    name: 'Typewriter',
    sampleText: 'type...',
    fontFamily: 'Press Start 2P',
    color: Color(0xFF39FF14),
    shadowColor: Color(0xFF39FF14),
    shadowOpacity: 0.8,
    shadowBlur: 10,
    shadowDistance: 0,
    scale: 0.8,
    inAnimation: 'typing',
    outAnimation: 'untyping',
  ),
];
