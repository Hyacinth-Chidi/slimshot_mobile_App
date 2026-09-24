import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

/// A text's shadow: colour, opacity, blur, distance and angle.
///
/// Only the colour used to be the user's; the rest was fixed — blur 8, offset
/// half the blur down and to the right, fully opaque. Those fixed values are
/// now the defaults, so a draft saved before the controls opens exactly as
/// it looked, and a new shadow starts as every shadow always did.
void main() {
  Offset offsetOf(TextOverlayModel o) =>
      TextOverlayLayout.shadowOffsetFor(o, 1);

  void expectOffset(Offset actual, Offset expected) {
    expect(actual.dx, closeTo(expected.dx, 1e-9));
    expect(actual.dy, closeTo(expected.dy, 1e-9));
  }

  group('a draft saved before the controls', () {
    test('opens with the shadow it always had', () {
      final o = TextOverlayModel.fromJson(const {
        'id': 't',
        'text': 'a',
        'shadowColor': 0xFF000000,
        'shadowBlurRadius': 8.0,
      });
      expect(o.shadowBlurRadius, 8.0);
      expect(o.shadowOpacity, 1.0);
      // The old rule: offset (blur / 2, blur / 2).
      expectOffset(offsetOf(o), const Offset(4, 4));
    });

    test('with no shadow, holds the defaults — so turning one on shows it', () {
      // It stored blur 0 alongside the transparent colour. Read literally,
      // picking a shadow colour later would give a shadow with no blur and no
      // distance: hidden exactly under the letters.
      final o = TextOverlayModel.fromJson(const {
        'id': 't',
        'text': 'a',
        'shadowColor': 0x00000000,
        'shadowBlurRadius': 0.0,
      });
      expect(o.shadowBlurRadius, kTextShadowDefaultBlur);
      expect(o.shadowDistance, kTextShadowDefaultDistance);
      expect(o.shadowAngle, kTextShadowDefaultAngle);
      expect(o.shadowOpacity, kTextShadowDefaultOpacity);
    });
  });

  test("a new shadow starts as shadows always looked", () {
    final o = TextOverlayModel(id: 't', text: 'a', shadowColor: Colors.black);
    expect(TextOverlayLayout.hasShadow(o), isTrue);
    expect(o.shadowBlurRadius, 8.0);
    expect(o.shadowOpacity, 1.0);
    expectOffset(offsetOf(o), const Offset(4, 4));
  });

  test('round-trips the controls through a draft', () {
    final o = TextOverlayModel(
      id: 't',
      text: 'a',
      shadowColor: Colors.red,
      shadowBlurRadius: 3,
      shadowOpacity: 0.4,
      shadowDistance: 12,
      shadowAngle: 200,
    );
    final back = TextOverlayModel.fromJson(o.toJson());
    expect(back.shadowBlurRadius, 3);
    expect(back.shadowOpacity, 0.4);
    expect(back.shadowDistance, 12);
    expect(back.shadowAngle, 200);
  });

  test('copyWith carries them — a split or a duplicate keeps the shadow', () {
    final o = TextOverlayModel(
      id: 't',
      text: 'a',
      shadowColor: Colors.red,
      shadowOpacity: 0.4,
      shadowDistance: 12,
      shadowAngle: 200,
    ).copyWith(id: 'u');
    expect(o.shadowOpacity, 0.4);
    expect(o.shadowDistance, 12);
    expect(o.shadowAngle, 200);
  });

  test('reads a hand-edited draft defensively', () {
    final o = TextOverlayModel.fromJson(const {
      'id': 't',
      'text': 'a',
      'shadowColor': 0xFF000000,
      'shadowBlurRadius': 99.0,
      'shadowOpacity': 3.0,
      'shadowDistance': -5.0,
      'shadowAngle': 405.0,
    });
    expect(o.shadowBlurRadius, kTextShadowMaxBlur);
    expect(o.shadowOpacity, 1.0);
    expect(o.shadowDistance, 0.0);
    expect(o.shadowAngle, 45.0);
    expect(
      TextOverlayModel.fromJson(const {
        'id': 't',
        'text': 'a',
        'shadowAngle': -90.0,
      }).shadowAngle,
      270.0,
    );
  });

  group('the angle is the direction the shadow falls', () {
    // Clockwise from pointing right, in screen space: 90° is straight down.
    TextOverlayModel at(double angle) => TextOverlayModel(
          id: 't',
          text: 'a',
          shadowColor: Colors.black,
          shadowDistance: 10,
          shadowAngle: angle,
        );

    test('0° right, 90° down, 180° left, 270° up', () {
      expectOffset(offsetOf(at(0)), const Offset(10, 0));
      expectOffset(offsetOf(at(90)), const Offset(0, 10));
      expectOffset(offsetOf(at(180)), const Offset(-10, 0));
      expectOffset(offsetOf(at(270)), const Offset(0, -10));
    });

    test('the distance scales with the text, like everything else', () {
      expect(
        TextOverlayLayout.shadowOffsetFor(at(0), 2.5).distance,
        closeTo(25, 1e-9),
      );
    });
  });

  group('whether there is a shadow', () {
    TextOverlayModel shadow({
      Color color = Colors.black,
      double opacity = 1,
      double blur = 8,
      double distance = 5,
    }) =>
        TextOverlayModel(
          id: 't',
          text: 'a',
          shadowColor: color,
          shadowOpacity: opacity,
          shadowBlurRadius: blur,
          shadowDistance: distance,
        );

    test('none without a colour, or at zero opacity', () {
      expect(TextOverlayLayout.hasShadow(shadow(color: Colors.transparent)),
          isFalse);
      expect(TextOverlayLayout.hasShadow(shadow(opacity: 0)), isFalse);
    });

    test('none when it would sit hidden exactly under the letters', () {
      expect(TextOverlayLayout.hasShadow(shadow(blur: 0, distance: 0)),
          isFalse);
    });

    test('a hard shadow — no blur, some distance — is a shadow', () {
      // Blur 0 used to mean "no shadow"; now it is the crisp offset look.
      expect(TextOverlayLayout.hasShadow(shadow(blur: 0)), isTrue);
    });
  });

  test('opacity fades the shadow colour, leaving its geometry alone', () {
    final full = TextOverlayModel(
      id: 't',
      text: 'a',
      shadowColor: const Color(0xFFFF0000),
    );
    final half = full.copyWith(shadowOpacity: 0.5);
    expect(TextOverlayLayout.shadowColorFor(half).a, closeTo(0.5, 1e-6));
    expect(TextOverlayLayout.shadowColorFor(half).r, 1.0);
    expect(TextOverlayLayout.shadowReachFor(half, 1),
        TextOverlayLayout.shadowReachFor(full, 1));
  });

  test('the defaults are the old fixed shadow, as numbers', () {
    expect(kTextShadowDefaultBlur, 8.0);
    expect(kTextShadowDefaultAngle, 45.0);
    expect(kTextShadowDefaultDistance, closeTo(4 * math.sqrt2, 1e-12));
    expect(kTextShadowDefaultOpacity, 1.0);
  });
}
