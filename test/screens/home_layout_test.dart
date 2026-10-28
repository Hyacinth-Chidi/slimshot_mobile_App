import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/screens/home_layout.dart';

/// Everything that gives up height, down the screen, the draft rows twice.
const _gives = [
  kHomeGapAboveHero,
  kHomeHeroHeight,
  kHomeGapAboveTools,
  kHomeToolsHeight,
  kHomeGapAboveTitle,
  kHomeGapAboveDrafts,
  kHomeDraftRowHeight,
  kHomeDraftRowHeight,
];

/// The room Home needs under its header with every part at [size].
double _room(double Function(HomeGive) size, double title, double nav) =>
    _gives.fold(0.0, (sum, g) => sum + size(g)) +
    title +
    kHomeDraftSpacing +
    kHomeDraftNavGap +
    nav;

double _fullRoom(double title, double nav) => _room((g) => g.full, title, nav);
double _leastRoom(double title, double nav) =>
    _room((g) => g.least, title, nav);

/// From under the header to the top of the drafts' box.
double _top(HomeLayout l) =>
    l.gapAboveHero +
    l.hero +
    l.gapAboveTools +
    l.tools +
    l.gapAboveTitle +
    l.title +
    l.gapAboveDrafts;

/// From under the header to the bottom of the nav: both rows, the gap
/// between them and the gap they keep above the nav.
double _sixDrafts(HomeLayout l, double nav) =>
    _top(l) + 2 * l.draftRow + kHomeDraftSpacing + kHomeDraftNavGap + nav;

List<double> _parts(HomeLayout l) => [
      l.gapAboveHero,
      l.hero,
      l.gapAboveTools,
      l.tools,
      l.gapAboveTitle,
      l.gapAboveDrafts,
      l.draftRow,
    ];

/// Home's sizes come from the height a phone gives it, never from which
/// phone it is: every part gives up the same share of what it can, from its
/// full size down to its least, so the six recent edits sit above the nav on
/// every phone that has room for them at their least.
void main() {
  test('with room to spare everything is at its full size', () {
    final l = HomeLayout.fit(room: 900, title: 20, navClearance: 80);
    expect(l.scale, 1);
    expect(l.fits, isTrue);
    expect(_parts(l), [16, 156, 16, 120, 20, 12, 140]);
    // The rest of the room is the drafts', down to the bottom of the screen.
    expect(l.height, 900);
    expect(l.draftsBox, 900 - _top(l));
    // With no edits yet, the card standing in takes the two rows' place.
    expect(l.emptyCard, 2 * 140 + kHomeDraftSpacing);
  });

  test('with less room every part gives up the same share of what it can, '
      'and the second row ends at the gap above the nav', () {
    final room = (_fullRoom(20, 80) + _leastRoom(20, 80)) / 2;
    final l = HomeLayout.fit(room: room, title: 20, navClearance: 80);
    expect(l.scale, 0.5);
    expect(_parts(l), [12, 138, 12, 108, 16, 10, 124]);
    expect(_sixDrafts(l, 80), room);
    expect(l.height, room);
    expect(l.emptyCard, 2 * 124 + kHomeDraftSpacing);
  });

  test('at the least room the six still fit, every part at its least', () {
    final room = _leastRoom(20, 80);
    final l = HomeLayout.fit(room: room, title: 20, navClearance: 80);
    expect(l.scale, 0);
    expect(l.fits, isTrue);
    expect(_parts(l), [8, 120, 8, 96, 12, 8, 108]);
    expect(_sixDrafts(l, 80), room);
  });

  test('with less room than that nothing goes under its least: one row sits '
      'above the nav and the rest scrolls up from under it', () {
    final room = _leastRoom(20, 128) - 80;
    final l = HomeLayout.fit(room: room, title: 20, navClearance: 128);
    expect(l.fits, isFalse);
    expect(_parts(l), [8, 120, 8, 96, 12, 8, 108]);
    // The page itself does not scroll while one row fits above the nav.
    expect(l.height, room);
    expect(l.draftsBox,
        greaterThanOrEqualTo(l.draftRow + kHomeDraftNavGap + 128));
    // The card standing in for no edits is never under the nav: it takes
    // what room there is above it.
    expect(l.emptyCard, l.draftsBox - kHomeDraftNavGap - 128);
  });

  test('where not even one row fits above the nav, the page grows to hold one',
      () {
    final l = HomeLayout.fit(room: 300, title: 20, navClearance: 128);
    expect(l.fits, isFalse);
    // The empty card at its least is the taller of the two.
    expect(l.draftsBox, kHomeEmptyCardLeast + kHomeDraftNavGap + 128);
    expect(l.emptyCard, kHomeEmptyCardLeast);
    expect(l.height, _top(l) + l.draftsBox);
  });

  test('a taller title takes its room from the parts that give, not from '
      'the rows above the nav', () {
    final room = _leastRoom(20, 80) + 60;
    final small = HomeLayout.fit(room: room, title: 20, navClearance: 80);
    final large = HomeLayout.fit(room: room, title: 26, navClearance: 80);
    expect(large.title, 26);
    expect(large.scale, lessThan(small.scale));
    expect(large.fits, isTrue);
    expect(_sixDrafts(large, 80), lessThanOrEqualTo(room));
  });

  test('the title is its line at the phone\'s text size', () {
    expect(homeTitleHeight(TextScaler.noScaling),
        kHomeTitleFontSize * kHomeTitleLineHeight);
    expect(homeTitleHeight(const TextScaler.linear(1.3)),
        kHomeTitleFontSize * 1.3 * kHomeTitleLineHeight);
  });

  test('across every room, text size and nav, nothing breaks the rules', () {
    for (final title in [20.0, 22.0, 26.0, 40.0]) {
      for (final nav in [80.0, 96.0, 104.0, 128.0]) {
        final least = _leastRoom(title, nav);
        HomeLayout? before;
        for (var room = 250.0; room <= 1250; room += 0.5) {
          final l = HomeLayout.fit(room: room, title: title, navClearance: nav);
          final what = 'room $room, title $title, nav $nav';
          final gives = [
            (l.gapAboveHero, kHomeGapAboveHero),
            (l.hero, kHomeHeroHeight),
            (l.gapAboveTools, kHomeGapAboveTools),
            (l.tools, kHomeToolsHeight),
            (l.gapAboveTitle, kHomeGapAboveTitle),
            (l.gapAboveDrafts, kHomeGapAboveDrafts),
            (l.draftRow, kHomeDraftRowHeight),
          ];
          for (final (size, give) in gives) {
            expect(size, inInclusiveRange(give.least, give.full), reason: what);
          }
          expect(l.title, title, reason: what);
          expect(l.draftRow, l.draftRow.roundToDouble(),
              reason: '$what: a card is a whole number of dp tall');
          expect(l.fits, room >= least, reason: what);
          expect(l.height, closeTo(_top(l) + l.draftsBox, 1e-6), reason: what);
          // The card standing in for no edits: never under the nav, never
          // under its least, never past the two rows it stands in for.
          expect(l.emptyCard,
              lessThanOrEqualTo(l.draftsBox - kHomeDraftNavGap - nav + 1e-6),
              reason: what);
          expect(
            l.emptyCard,
            inInclusiveRange(
                kHomeEmptyCardLeast, 2 * l.draftRow + kHomeDraftSpacing),
            reason: what,
          );
          if (l.fits) {
            // Both rows above the nav, and the page does not scroll.
            expect(_sixDrafts(l, nav), lessThanOrEqualTo(room + 1e-6),
                reason: what);
            expect(l.height, room, reason: what);
            expect(l.emptyCard, 2 * l.draftRow + kHomeDraftSpacing,
                reason: '$what: the empty card is the two rows');
            // While the cards are short of full size, nothing is left over
            // but the rounding to whole dp.
            if (l.draftRow < kHomeDraftRowHeight.full) {
              expect(room - _sixDrafts(l, nav), lessThan(2), reason: what);
            }
          } else {
            expect(l.scale, 0, reason: what);
            expect(l.draftRow, kHomeDraftRowHeight.least, reason: what);
            expect(
              l.draftsBox,
              greaterThanOrEqualTo(
                math.max(l.draftRow, kHomeEmptyCardLeast) +
                    kHomeDraftNavGap +
                    nav -
                    1e-6,
              ),
              reason: '$what: one row above the nav',
            );
            expect(l.height, greaterThanOrEqualTo(room), reason: what);
          }
          // More room never makes anything smaller.
          if (before != null) {
            final was = _parts(before);
            final now = _parts(l);
            for (var i = 0; i < now.length; i++) {
              expect(now[i], greaterThanOrEqualTo(was[i] - 1e-9),
                  reason: '$what, part $i');
            }
          }
          before = l;
        }
      }
    }
  });
}
