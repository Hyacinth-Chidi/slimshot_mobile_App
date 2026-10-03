import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';

/// Everything about how a text looks, apart from its words, where and when it
/// is, how big, and how it moves on the canvas: typeface, fill, outline, box,
/// shadow, alignment, and its in, out and loop animations with their speeds.
///
/// **The one definition.** A template, a caption preset and "apply to all
/// captions" each restyle text; with a field list each, a look field added
/// later would reach one of them and not the others. `text_look_test.dart`
/// holds every serialised field of a text to one side or the other.
@immutable
class TextLook {
  const TextLook({
    required this.fontFamily,
    this.color = Colors.white,
    this.strokeColor = Colors.transparent,
    this.strokeWidth = 0,
    this.backgroundColor = Colors.transparent,
    this.borderRadius = 16,
    this.backgroundPadding = 16,
    this.shadowColor = Colors.transparent,
    this.shadowOpacity = kTextShadowDefaultOpacity,
    this.shadowBlur = kTextShadowDefaultBlur,
    this.shadowDistance = kTextShadowDefaultDistance,
    this.shadowAngle = kTextShadowDefaultAngle,
    this.textAlign = 'center',
    this.inAnimation = 'none',
    this.outAnimation = 'none',
    this.loopAnimation = 'none',
    this.inSpeed = kTextAnimationNaturalSpeed,
    this.outSpeed = kTextAnimationNaturalSpeed,
    this.loopSpeed = kTextAnimationNaturalSpeed,
  });

  factory TextLook.of(TextOverlayModel text) => TextLook(
        fontFamily: text.fontFamily,
        color: text.color,
        strokeColor: text.strokeColor,
        strokeWidth: text.strokeWidth,
        backgroundColor: text.backgroundColor,
        borderRadius: text.borderRadius,
        backgroundPadding: text.backgroundPadding,
        shadowColor: text.shadowColor,
        shadowOpacity: text.shadowOpacity,
        shadowBlur: text.shadowBlurRadius,
        shadowDistance: text.shadowDistance,
        shadowAngle: text.shadowAngle,
        textAlign: text.textAlign,
        inAnimation: text.inAnimation,
        outAnimation: text.outAnimation,
        loopAnimation: text.loopAnimation,
        inSpeed: text.animationInDuration,
        outSpeed: text.animationOutDuration,
        loopSpeed: text.loopSpeed,
      );

  final String fontFamily;
  final Color color;
  final Color strokeColor;
  final double strokeWidth;
  final Color backgroundColor;
  final double borderRadius;
  final double backgroundPadding;
  final Color shadowColor;
  final double shadowOpacity;
  final double shadowBlur;
  final double shadowDistance;
  final double shadowAngle;
  final String textAlign;

  /// `text_animation_catalog.dart` ids, each in its own slot, or 'none'.
  final String inAnimation;
  final String outAnimation;
  final String loopAnimation;

  /// Speed multipliers — `animationInDuration`, `animationOutDuration` and
  /// `loopSpeed` on the model, which hold speeds despite their names.
  final double inSpeed;
  final double outSpeed;
  final double loopSpeed;

  /// [text] wearing this look: every look field written, including the ones
  /// this look leaves empty, so nothing of the previous look is left behind;
  /// its words, timing, place, size, motion and caption untouched.
  TextOverlayModel applyTo(TextOverlayModel text) => text.copyWith(
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
        inAnimation: inAnimation,
        outAnimation: outAnimation,
        loopAnimation: loopAnimation,
        animationInDuration: inSpeed,
        animationOutDuration: outSpeed,
        loopSpeed: loopSpeed,
      );

  /// Whether [other] is this look at any pace. Speeds are left out: a motion
  /// tuned faster after a look was chosen is still that look.
  bool sameLookAs(TextLook other) =>
      fontFamily == other.fontFamily &&
      color == other.color &&
      strokeColor == other.strokeColor &&
      strokeWidth == other.strokeWidth &&
      backgroundColor == other.backgroundColor &&
      borderRadius == other.borderRadius &&
      backgroundPadding == other.backgroundPadding &&
      shadowColor == other.shadowColor &&
      shadowOpacity == other.shadowOpacity &&
      shadowBlur == other.shadowBlur &&
      shadowDistance == other.shadowDistance &&
      shadowAngle == other.shadowAngle &&
      textAlign == other.textAlign &&
      inAnimation == other.inAnimation &&
      outAnimation == other.outAnimation &&
      loopAnimation == other.loopAnimation;

  @override
  bool operator ==(Object other) =>
      other is TextLook &&
      sameLookAs(other) &&
      inSpeed == other.inSpeed &&
      outSpeed == other.outSpeed &&
      loopSpeed == other.loopSpeed;

  @override
  int get hashCode => Object.hashAll([
        fontFamily,
        color,
        strokeColor,
        strokeWidth,
        backgroundColor,
        borderRadius,
        backgroundPadding,
        shadowColor,
        shadowOpacity,
        shadowBlur,
        shadowDistance,
        shadowAngle,
        textAlign,
        inAnimation,
        outAnimation,
        loopAnimation,
        inSpeed,
        outSpeed,
        loopSpeed,
      ]);
}
