import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_animation_tile.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';

import '../../../support/test_fonts.dart';

/// A tile is a *live preview of the real painter*, so these tests assert the
/// things that make it one: that the painter it hands to `CustomPaint` is the
/// canvas's own `TextOverlayPainter`, that its clock actually moves the
/// playhead, and that the synthetic overlay it paints is the user's styling
/// rather than a generic sample.
///
/// Deliberately not goldens: a frame of a running animation is exactly the
/// kind of picture that changes for reasons unrelated to the tile.
void main() {
  // A bundled font, not a Google one — see test/support/test_fonts.dart.
  TextOverlayModel overlayWith({
    String text = 'Hello there',
    Color color = const Color(0xFFFF0000),
  }) {
    return TextOverlayModel(
      id: 'overlay-1',
      text: text,
      color: color,
      fontFamily: kTestFontFamily,
      // A pinch and a spin the tile must ignore: a tile is a fixed box.
      scale: 3.0,
      rotation: 0.8,
      position: const Offset(120, -90),
      referenceCanvasSize: const Size(400, 700),
    );
  }

  TextAnimation animationById(String id) =>
      kTextAnimations.firstWhere((a) => a.id == id);

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  /// The painter the tile actually handed to `CustomPaint` — which is what
  /// "drives the real painter" means in practice.
  TextOverlayPainter painterIn(WidgetTester tester) {
    final paints = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(TextAnimationTile),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((p) => p.painter is TextOverlayPainter);
    expect(
      paints,
      isNotEmpty,
      reason: 'the tile must paint through TextOverlayPainter, not its own '
          'approximation of the animation',
    );
    return paints.first.painter! as TextOverlayPainter;
  }

  testWidgets('the tile shows the animation label', (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Typing'), findsOneWidget);
  });

  testWidgets('the tile paints through the canvas painter', (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('fade_in'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final painter = painterIn(tester);
    // The animation goes in the slot its own category names, or the painter
    // resolves it to nothing and the tile previews a still frame.
    expect(painter.overlay.inAnimation, 'fade_in');
    expect(painter.overlay.outAnimation, 'none');
    expect(painter.overlay.loopAnimation, 'none');
  });

  testWidgets('every selectable animation resolves to a live window in a tile',
      (tester) async {
    // The slot, the span and the speeds a tile synthesises have to add up to a
    // window the painter will actually run. If any one of them is wrong the
    // tile still renders — it just renders the text standing still, which is a
    // tile that quietly lies about what the animation does.
    for (final animation in kSelectableTextAnimations) {
      await tester.pumpWidget(
        host(
          TextAnimationTile(
            key: ValueKey(animation.id),
            animation: animation,
            overlay: overlayWith(),
            isSelected: false,
            onTap: () {},
          ),
        ),
      );

      final overlay = painterIn(tester).overlay;
      final glyphCount =
          TextOverlayPainter.glyphBoxesFor(overlay, const Size(240, 240)).length;
      final timing = TextOverlayPainter.timingFor(overlay, glyphCount);
      expect(
        timing.isActive,
        isTrue,
        reason: '${animation.id} resolved to no live window in its tile',
      );
    }
  });

  testWidgets('the animation plays at its natural pace in a tile',
      (tester) async {
    // The tab's Speed slider retimes the *project's* text. A tile retimed with
    // it would make the slider look like it changed which animation is which.
    final animation = animationById('typing');
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animation,
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final overlay = painterIn(tester).overlay;
    expect(overlay.animationInDuration, kTextAnimationNaturalSpeed);
    expect(overlay.loopSpeed, kTextAnimationNaturalSpeed);

    // The span holds the whole animation, so nothing is compressed: the
    // catalog's own duration is what plays.
    final glyphCount =
        TextOverlayPainter.glyphBoxesFor(overlay, const Size(240, 240)).length;
    final timing = TextOverlayPainter.timingFor(overlay, glyphCount);
    expect(
      timing.inSeconds,
      closeTo(animation.naturalDuration(glyphCount), 1e-6),
    );
  });

  testWidgets('an out animation goes in the out slot', (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('fade_out'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final painter = painterIn(tester);
    expect(painter.overlay.outAnimation, 'fade_out');
    expect(painter.overlay.inAnimation, 'none');
  });

  testWidgets('a loop animation goes in the loop slot', (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('wave_loop'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final painter = painterIn(tester);
    expect(painter.overlay.loopAnimation, 'wave_loop');
    expect(painter.overlay.inAnimation, 'none');
    expect(painter.overlay.outAnimation, 'none');
  });

  testWidgets('the tile keeps the styling but drops scale and rotation',
      (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('fade_in'),
          overlay: overlayWith(color: const Color(0xFF00FF00)),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final synthetic = painterIn(tester).overlay;
    expect(synthetic.color, const Color(0xFF00FF00));
    expect(synthetic.fontFamily, kTestFontFamily);
    // A 3× caption would overflow a small fixed tile, and a rotated one would
    // read as a tile that is crooked rather than as the animation.
    expect(synthetic.scale, 1.0);
    expect(synthetic.rotation, 0.0);
    expect(synthetic.position, Offset.zero);
  });

  testWidgets('the tile keeps the shadow as the user tuned it',
      (tester) async {
    // The tile builds its own overlay field by field, so a shadow control it
    // does not copy would preview a different shadow from the canvas.
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('fade_in'),
          overlay: overlayWith().copyWith(
            shadowColor: const Color(0xFFFF0000),
            shadowBlurRadius: 3,
            shadowOpacity: 0.4,
            shadowDistance: 12,
            shadowAngle: 200,
          ),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final synthetic = painterIn(tester).overlay;
    expect(synthetic.shadowColor, const Color(0xFFFF0000));
    expect(synthetic.shadowBlurRadius, 3);
    expect(synthetic.shadowOpacity, 0.4);
    expect(synthetic.shadowDistance, 12);
    expect(synthetic.shadowAngle, 200);
  });

  testWidgets('the text is truncated by grapheme cluster, not by code unit',
      (tester) async {
    // A family emoji is several code units; `substring` would cut it in half
    // and the tile would show a broken glyph. That exact mistake made emoji
    // vanish from exports in an earlier stage.
    const emoji = '👨‍👩‍👧‍👦👍🏽🎉';
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('fade_in'),
          overlay: overlayWith(text: '$emoji abcdefghijkl'),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final shown = painterIn(tester).overlay.text;
    expect(shown.characters.length, lessThanOrEqualTo(kTextAnimationTileGlyphs));
    // Whole clusters survived: the first cluster is still the full family.
    expect(shown.characters.first, '👨‍👩‍👧‍👦');
    expect(shown, startsWith(emoji));
  });

  testWidgets('tapping reports the selection once', (tester) async {
    var taps = 0;
    final clock = ValueNotifier<double>(0);
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () => taps++,
          clock: clock,
        ),
      ),
    );

    await tester.tap(find.byType(TextAnimationTile));
    // Advancing the clock is an animation frame, not a second selection: a
    // tile that reported per frame would push an undo entry per frame.
    for (var i = 1; i <= 5; i++) {
      clock.value = i / 5;
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('a selected tile is visually distinct from an unselected one',
      (tester) async {
    Decoration decorationOf(WidgetTester tester) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(TextAnimationTile),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.decoration!;
    }

    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );
    final unselected = decorationOf(tester);

    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(),
          isSelected: true,
          onTap: () {},
        ),
      ),
    );
    final selected = decorationOf(tester);

    // The point is that a user can tell them apart, not which colour was used.
    expect(selected, isNot(equals(unselected)));
  });

  testWidgets('the tile repaints as its clock advances', (tester) async {
    final clock = ValueNotifier<double>(0);
    addTearDown(clock.dispose);

    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
          clock: clock,
        ),
      ),
    );

    final first = painterIn(tester);
    final startPosition = first.positionSeconds;

    clock.value = 0.5;
    await tester.pump();

    final second = painterIn(tester);
    // A new playhead is what makes this a live preview rather than a still.
    expect(second.positionSeconds, greaterThan(startPosition));
    // And the painter must agree there is something to redraw, or the
    // `CustomPaint` would keep the picture it already has.
    expect(second.shouldRepaint(first), isTrue);

    // One loop of the clock walks the animation from its start through to its
    // rest: the sweep has to cover the whole synthetic span, or the tile would
    // loop back before the user saw the text the animation animates *to*.
    clock.value = 0.999;
    await tester.pump();
    final last = painterIn(tester);
    final span = last.overlay.endTime.inMicroseconds / 1e6;
    expect(last.positionSeconds, closeTo(span, span * 0.01));

    final glyphCount =
        TextOverlayPainter.glyphBoxesFor(last.overlay, const Size(240, 240))
            .length;
    final timing = TextOverlayPainter.timingFor(last.overlay, glyphCount);
    // Rest, by the catalog's own definition of it.
    final rested = timing.stateAt(last.positionSeconds, 0, glyphCount);
    expect(rested.opacity, closeTo(1.0, 1e-6));
    expect(rested.scale, closeTo(1.0, 1e-6));
  });

  testWidgets('a null clock renders a static frame without throwing',
      (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // A tile with no clock still shows the text at rest rather than mid-
    // animation, so an off-screen tile reads as its own text.
    expect(painterIn(tester).positionSeconds, greaterThanOrEqualTo(0.0));
  });

  testWidgets('an empty overlay falls back to sample text', (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(text: ''),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    // Text overlays are created empty in this app; a tile showing nothing
    // teaches the user nothing about the animation.
    final shown = painterIn(tester).overlay.text;
    expect(shown, isNotEmpty);
    expect(shown, kTextAnimationTileSampleText);
  });

  testWidgets('whitespace-only text also falls back', (tester) async {
    await tester.pumpWidget(
      host(
        TextAnimationTile(
          animation: animationById('typing'),
          overlay: overlayWith(text: '   '),
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    expect(painterIn(tester).overlay.text, kTextAnimationTileSampleText);
  });
}
