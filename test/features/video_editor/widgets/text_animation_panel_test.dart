import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_animation_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_animation_tile.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_preview_tile.dart';

import '../../../support/test_fonts.dart';

/// The Animation tab's contract with the catalog.
///
/// The failure this whole stage exists to fix was a **hardcoded list**: the
/// engine could play thirty animations while the tab offered seven, and
/// nothing in the code said so. So the load-bearing assertion here is the
/// **count** — tiles must equal `selectableTextAnimations(category).length + 1`
/// — because that is the one check a new catalog entry cannot slip past.
///
/// The panel is pumped directly rather than through `showTextEditor`: it takes
/// its overlay and its writes as plain parameters, so nothing about a Riverpod
/// scope or a modal sheet is part of what these tests are about.
void main() {
  // A bundled font, not a Google one — see test/support/test_fonts.dart.
  TextOverlayModel overlayWith({
    String text = 'Hello',
    String inAnimation = 'none',
    String outAnimation = 'none',
    String loopAnimation = 'none',
    double inSpeed = kTextAnimationNaturalSpeed,
    double outSpeed = kTextAnimationNaturalSpeed,
    double loopSpeed = kTextAnimationNaturalSpeed,
  }) {
    return TextOverlayModel(
      id: 'overlay-1',
      text: text,
      fontFamily: kTestFontFamily,
      inAnimation: inAnimation,
      outAnimation: outAnimation,
      loopAnimation: loopAnimation,
      animationInDuration: inSpeed,
      animationOutDuration: outSpeed,
      loopSpeed: loopSpeed,
      referenceCanvasSize: const Size(400, 700),
    );
  }

  /// One pumped panel plus whatever it reported, so a test can tap and then
  /// read what the slot would have been written with.
  ({
    List<(TextAnimationCategory, String?)> selections,
    List<(TextAnimationCategory, double)> speeds,
    List<void> dragStarts,
  }) recorded() => (
        selections: <(TextAnimationCategory, String?)>[],
        speeds: <(TextAnimationCategory, double)>[],
        dragStarts: <void>[],
      );

  var pumpSeq = 0;

  Future<void> pumpPanel(
    WidgetTester tester, {
    required TextOverlayModel overlay,
    void Function(TextAnimationCategory, String?)? onSelect,
    void Function(TextAnimationCategory, double)? onSpeedChanged,
    VoidCallback? onSpeedChangeStart,
  }) async {
    // A fresh key per pump, so a test that pumps the panel several times gets
    // a genuinely new panel each time rather than the previous one's state
    // (its category, and its grid's scroll offset) carried over.
    pumpSeq++;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The sheet gives every tab a fixed panel height; the panel's grid
          // is `Expanded`, so it needs bounded height here too.
          body: SizedBox(
            height: 250,
            width: 400,
            child: TextAnimationPanel(
              key: ValueKey('panel-$pumpSeq'),
              overlay: overlay,
              onSelect: onSelect ?? (_, __) {},
              onSpeedChangeStart: onSpeedChangeStart ?? () {},
              onSpeedChanged: onSpeedChanged ?? (_, __) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Moves to a category tab by its label.
  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  testWidgets('lays its tiles out three to a row, as the templates do',
      (tester) async {
    // It was four to a row in taller tiles, beside a Templates tab of three —
    // two grids of the same kind of tile, sized differently. One layout,
    // shared, so the two tabs cannot drift apart again.
    await pumpPanel(tester, overlay: overlayWith());
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.gridDelegate, same(kTextPreviewGrid));
    expect(kTextPreviewGrid.crossAxisCount, 3);
  });

  testWidgets('the tiles hold still while the grid scrolls, and play again '
      'after', (tester) async {
    // The same load as the templates grid: once a text wears a shadowed
    // template, every tile here carries per-letter shadow layers too.
    await pumpPanel(
      tester,
      overlay: TextOverlayModel(
        id: 'overlay-1',
        text: 'Hello',
        fontFamily: kTestFontFamily,
        shadowColor: Colors.black,
        referenceCanvasSize: const Size(400, 700),
      ),
    );
    double playhead() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(TextAnimationTile).first,
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<TextOverlayPainter>()
        .first
        .positionSeconds;

    final before = playhead();
    await tester.pump(const Duration(milliseconds: 100));
    expect(playhead(), isNot(before), reason: 'the tiles play at rest');

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GridView)));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 50));
    final held = playhead();
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(playhead(), held, reason: 'held while the finger scrolls');

    await gesture.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final settled = playhead();
    await tester.pump(const Duration(milliseconds: 100));
    expect(playhead(), isNot(settled), reason: 'playing again once it stops');
  });

  testWidgets('switching category mid-scroll leaves the tiles playing',
      (tester) async {
    // The grid is keyed by category, so a switch replaces the scrollable —
    // and one that is disposed mid-scroll never reports the scroll's end,
    // which would leave the clock held and every tile frozen.
    await pumpPanel(tester, overlay: overlayWith());
    double playhead() => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(TextAnimationTile).first,
            matching: find.byType(CustomPaint),
          ),
        )
        .map((p) => p.painter)
        .whereType<TextOverlayPainter>()
        .first
        .positionSeconds;

    final scroll =
        await tester.startGesture(tester.getCenter(find.byType(GridView)));
    await scroll.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 50));
    await scroll.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 50));

    await openTab(tester, 'Out');
    await scroll.up();
    await tester.pump(const Duration(milliseconds: 100));
    final after = playhead();
    await tester.pump(const Duration(milliseconds: 100));
    expect(playhead(), isNot(after), reason: 'the new tab plays');
  });

  testWidgets('offers three categories', (tester) async {
    await pumpPanel(tester, overlay: overlayWith());

    // Loop is the new one: the tab had only In and Out, so a user could not
    // reach wave, pulse, shake or wiggle at all.
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    expect(find.text('Loop'), findsOneWidget);
  });

  testWidgets('shows every selectable animation for the active category',
      (tester) async {
    // **The assertion this stage exists for.** Counting against the catalog
    // rather than against a fixed number is what makes a new catalog entry
    // unable to silently miss the tab.
    for (final entry in <(String, TextAnimationCategory)>[
      ('In', TextAnimationCategory.inAnim),
      ('Out', TextAnimationCategory.outAnim),
      ('Loop', TextAnimationCategory.loop),
    ]) {
      await pumpPanel(tester, overlay: overlayWith());
      await openTab(tester, entry.$1);

      final expected = selectableTextAnimations(entry.$2);

      // Counted from the grid's own `itemCount` rather than from the tiles
      // that happen to be on screen: the grid is lazy, so a rendered count
      // measures the panel's height as much as its contract with the catalog
      // and would go green for the wrong reason on a taller sheet.
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
        (grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
        expected.length + 1,
        reason: '${entry.$1} must offer every selectable ${entry.$2.name} '
            'animation the catalog holds, plus None',
      );

      // None leads the grid, so it is on screen before anything is scrolled.
      expect(find.text('None'), findsOneWidget);

      // And every catalog entry really builds a tile with that label, so the
      // count above cannot be satisfied by padding the grid with blanks.
      for (final animation in expected) {
        await tester.scrollUntilVisible(
          find.text(animation.label),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(animation.label),
          findsOneWidget,
          reason: '${animation.id} is selectable but the tab does not show it',
        );
      }
    }
  });

  testWidgets('never offers an animation nothing draws', (tester) async {
    // `colour_fill` and `colour_cycle_loop` time correctly but no renderer
    // draws `fillProgress`, so offering them gives the user a control that
    // quietly does nothing — and then, on the flat-raster export path,
    // apologises for it.
    final gated =
        kTextAnimations.where((a) => !a.isSelectable).toList(growable: false);
    expect(gated, isNotEmpty, reason: 'the fixture assumes a gated entry');

    for (final entry in <(String, TextAnimationCategory)>[
      ('In', TextAnimationCategory.inAnim),
      ('Out', TextAnimationCategory.outAnim),
      ('Loop', TextAnimationCategory.loop),
    ]) {
      await pumpPanel(tester, overlay: overlayWith());
      await openTab(tester, entry.$1);

      // Checked against what the grid *would* build, not against what happens
      // to be on screen: a lazy grid off the bottom of the viewport would
      // otherwise make this pass for the wrong reason.
      final offered = selectableTextAnimations(entry.$2).map((a) => a.id);
      for (final animation in gated) {
        expect(
          offered,
          isNot(contains(animation.id)),
          reason:
              '${animation.id} is not selectable but ${entry.$1} offers it',
        );
        expect(
          find.text(animation.label),
          findsNothing,
          reason: '${animation.id} is drawn in ${entry.$1}',
        );
      }
    }
  });

  testWidgets('selecting an animation writes the slot it belongs to',
      (tester) async {
    final log = recorded();

    // In.
    await pumpPanel(
      tester,
      overlay: overlayWith(),
      onSelect: (c, id) => log.selections.add((c, id)),
    );
    await tester.tap(find.text('Typing'));
    await tester.pump();
    expect(log.selections.last, (TextAnimationCategory.inAnim, 'typing'));

    // Out — the same tap on a different tab must never reach the in-slot.
    await openTab(tester, 'Out');
    await tester.tap(find.text('Fade out'));
    await tester.pump();
    expect(log.selections.last, (TextAnimationCategory.outAnim, 'fade_out'));

    // Loop.
    await openTab(tester, 'Loop');
    await tester.tap(find.text('Pulse'));
    await tester.pump();
    expect(log.selections.last, (TextAnimationCategory.loop, 'pulse_loop'));

    // None clears the slot rather than writing a sentinel of the panel's own.
    await tester.tap(find.text('None'));
    await tester.pump();
    expect(log.selections.last, (TextAnimationCategory.loop, null));
  });

  testWidgets('a legacy stored id highlights its resolved tile',
      (tester) async {
    // `'fade'` meant `fadeIn()` in the in-slot and `fadeOut()` in the out-slot
    // in the old widget layer, so the highlight has to resolve **by slot**. A
    // bare string comparison would highlight nothing at all here.
    await pumpPanel(
      tester,
      overlay: overlayWith(inAnimation: 'fade', outAnimation: 'fade'),
    );

    TextAnimationTile tileFor(String label) => tester.widget<TextAnimationTile>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextAnimationTile),
          ),
        );

    expect(tileFor('Fade in').isSelected, isTrue);
    expect(tileFor('Typing').isSelected, isFalse);

    await openTab(tester, 'Out');
    expect(tileFor('Fade out').isSelected, isTrue);
    expect(tileFor('Untyping').isSelected, isFalse);
  });

  testWidgets('an empty slot highlights None', (tester) async {
    await pumpPanel(tester, overlay: overlayWith());

    for (final tile in tester.widgetList<TextAnimationTile>(
      find.byType(TextAnimationTile),
    )) {
      expect(tile.isSelected, isFalse);
    }
    // And a bare in-only id sitting in the out-slot plays nothing, so the out
    // tab must show None selected rather than a tile the file never draws.
    await pumpPanel(tester, overlay: overlayWith(outAnimation: 'slide_up'));
    await openTab(tester, 'Out');
    for (final tile in tester.widgetList<TextAnimationTile>(
      find.byType(TextAnimationTile),
    )) {
      expect(tile.isSelected, isFalse);
    }
  });

  testWidgets('the speed slider reads and writes the multiplier',
      (tester) async {
    // Not seconds. A slider showing "0.8s" over a model holding a speed is the
    // bug this stage inherited.
    final log = recorded();
    await pumpPanel(
      tester,
      overlay: overlayWith(inAnimation: 'typing', inSpeed: 1.4, outSpeed: 1.4),
      onSpeedChanged: (c, v) => log.speeds.add((c, v)),
      onSpeedChangeStart: () => log.dragStarts.add(null),
    );

    expect(find.text('1.4×'), findsOneWidget);
    expect(find.textContaining('s', findRichText: false), findsNothing);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(1.4, 1e-9));
    expect(slider.min, kMinTextAnimationSpeed);
    expect(slider.max, kMaxTextAnimationSpeed);

    // Drag it: one snapshot at the start, then a write per frame — so the
    // whole drag undoes as one step rather than a pixel at a time.
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pump();

    expect(log.dragStarts.length, 1);
    expect(log.speeds, isNotEmpty);
    expect(log.speeds.last.$1, TextAnimationCategory.inAnim);
    expect(log.speeds.last.$2, greaterThan(1.4));
    expect(log.speeds.last.$2, lessThanOrEqualTo(kMaxTextAnimationSpeed));
  });

  testWidgets('the loop tab writes the loop speed', (tester) async {
    final log = recorded();
    await pumpPanel(
      tester,
      overlay: overlayWith(loopAnimation: 'wave_loop', loopSpeed: 2.0),
      onSpeedChanged: (c, v) => log.speeds.add((c, v)),
    );
    await openTab(tester, 'Loop');

    // A loop's cycle length is no part of the in/out compression, so its speed
    // is its own field.
    expect(find.text('2.0×'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-60, 0));
    await tester.pump();

    expect(log.speeds, isNotEmpty);
    expect(log.speeds.last.$1, TextAnimationCategory.loop);
    expect(log.speeds.last.$2, lessThan(2.0));
  });

  testWidgets('the slider is hidden while the slot is empty', (tester) async {
    await pumpPanel(tester, overlay: overlayWith());
    // A slider that retimes an animation there isn't is a control that does
    // nothing.
    expect(find.byType(Slider), findsNothing);

    await pumpPanel(tester, overlay: overlayWith(inAnimation: 'typing'));
    expect(find.byType(Slider), findsOneWidget);
    // …and the Out tab's slot is still empty, so it goes away again.
    await openTab(tester, 'Out');
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('every visible tile shares the panel clock', (tester) async {
    // One `AnimationController` for the whole tab rather than a `Ticker` per
    // tile: a dozen tickers would compete for the same frames.
    await pumpPanel(tester, overlay: overlayWith());

    final tiles =
        tester.widgetList<TextAnimationTile>(find.byType(TextAnimationTile));
    expect(tiles, isNotEmpty);
    final clock = tiles.first.clock;
    expect(clock, isNotNull);
    for (final tile in tiles) {
      expect(identical(tile.clock, clock), isTrue);
    }

    // And it is running, so the tiles are live previews rather than stills.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs leaves no other category building tiles',
      (tester) async {
    await pumpPanel(tester, overlay: overlayWith());
    await openTab(tester, 'Loop');

    // The grid holds exactly the loop category and nothing else, so the
    // in-animations are not merely scrolled off — they are not built, and
    // therefore not running.
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
      selectableTextAnimations(TextAnimationCategory.loop).length + 1,
    );

    final loopLabels = selectableTextAnimations(TextAnimationCategory.loop)
        .map((a) => a.label)
        .toSet();
    for (final animation
        in selectableTextAnimations(TextAnimationCategory.inAnim)) {
      // A loop category that shares a label with an in-animation would make
      // this ambiguous; none does today, and the guard says so if one lands.
      if (loopLabels.contains(animation.label)) continue;
      expect(find.text(animation.label), findsNothing);
    }
  });

  testWidgets('the panel disposes its clock without complaint', (tester) async {
    await pumpPanel(tester, overlay: overlayWith());
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(tester.takeException(), isNull);
  });
}
