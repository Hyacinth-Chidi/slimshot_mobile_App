import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A part of Home that gives up height on a shorter phone: its [full] size,
/// and the [least] it goes down to.
@immutable
class HomeGive {
  const HomeGive(this.full, this.least);

  final double full;
  final double least;

  /// Its size at [scale]: [least] at 0, [full] at 1.
  double at(double scale) => least + (full - least) * scale;
}

/// Above the header, the one gap that stays whatever the phone.
const double kHomeTopPadding = 12;

const HomeGive kHomeGapAboveHero = HomeGive(16, 8);
const HomeGive kHomeHeroHeight = HomeGive(156, 120);
const HomeGive kHomeGapAboveTools = HomeGive(16, 8);
const HomeGive kHomeToolsHeight = HomeGive(120, 96);
const HomeGive kHomeGapAboveTitle = HomeGive(20, 12);
const HomeGive kHomeGapAboveDrafts = HomeGive(12, 8);
const HomeGive kHomeDraftRowHeight = HomeGive(140, 108);

/// Between the draft cards both ways, and what the last row keeps above
/// the nav.
const double kHomeDraftSpacing = 12;
const double kHomeDraftNavGap = 8;

/// The least the card standing in for no edits is: it takes the two rows'
/// place, and this much where there is not that room above the nav.
const double kHomeEmptyCardLeast = 120;

/// "Recent Edits": its size, and a line height of its own, so the line is
/// the same height whatever the theme's text style says.
const double kHomeTitleFontSize = 16;
const double kHomeTitleLineHeight = 1.25;

/// How tall the "Recent Edits" line is at the phone's text size.
double homeTitleHeight(TextScaler scaler) =>
    scaler.scale(kHomeTitleFontSize) * kHomeTitleLineHeight;

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

/// Home's heights, worked out from the room a phone gives it — never from
/// which phone it is.
///
/// Everything under the header gives up the same share of what it can, from
/// its full size down to its least, as far as it takes for the six recent
/// edits to sit above the nav in two rows: the gaps, New Video, the tool
/// cards and the draft cards together, so a shorter phone shows the same
/// page smaller rather than one part squeezed. A tall phone shows it all at
/// full size, the drafts' box running on below the rows. Where even every
/// part at its least will not hold both rows, nothing goes under its least:
/// one row sits above the nav, the second runs on under it, and the drafts
/// scroll up from under it inside their own box; the page itself scrolls
/// only where not even one row fits above the nav (a phone on its side).
@immutable
class HomeLayout {
  const HomeLayout._({
    required this.scale,
    required this.fits,
    required this.gapAboveHero,
    required this.hero,
    required this.gapAboveTools,
    required this.tools,
    required this.gapAboveTitle,
    required this.title,
    required this.gapAboveDrafts,
    required this.draftRow,
    required this.emptyCard,
    required this.height,
  });

  /// Lays Home out in [room] — the height from under the header to the
  /// bottom of the screen — with [title] the "Recent Edits" line
  /// ([homeTitleHeight]) and [navClearance] how far the floating nav's top
  /// edge is up from the bottom of the screen.
  factory HomeLayout.fit({
    required double room,
    required double title,
    required double navClearance,
  }) {
    double sum(double Function(HomeGive) size) =>
        _gives.fold(0.0, (total, g) => total + size(g));
    final fixed =
        title + kHomeDraftSpacing + kHomeDraftNavGap + navClearance;
    final least = sum((g) => g.least) + fixed;
    final range = sum((g) => g.full) + fixed - least;
    final scale = ((room - least) / range).clamp(0.0, 1.0);

    final gapAboveHero = kHomeGapAboveHero.at(scale);
    final hero = kHomeHeroHeight.at(scale);
    final gapAboveTools = kHomeGapAboveTools.at(scale);
    final tools = kHomeToolsHeight.at(scale);
    final gapAboveTitle = kHomeGapAboveTitle.at(scale);
    final gapAboveDrafts = kHomeGapAboveDrafts.at(scale);
    final top = gapAboveHero +
        hero +
        gapAboveTools +
        tools +
        gapAboveTitle +
        title +
        gapAboveDrafts;

    // The rows take what the rest leaves, in whole dp: the rounding is all
    // that can go unused, and it goes under the rows, never past the nav.
    final twoRows =
        room - top - navClearance - kHomeDraftNavGap - kHomeDraftSpacing;
    final row = (twoRows / 2 + 1e-6).floorToDouble();
    final fits = row >= kHomeDraftRowHeight.least;
    final draftRow = fits
        ? math.min(row, kHomeDraftRowHeight.full)
        : kHomeDraftRowHeight.least;

    // At the least, one row — or the empty card — above the nav.
    final oneRow = math.max(draftRow, kHomeEmptyCardLeast) +
        kHomeDraftNavGap +
        navClearance;
    final height = math.max(room, top + oneRow);

    // Before any edit, a card takes the six's place: exactly the two rows
    // where they fit, else what room there is above the nav.
    final twoRowsTall = 2 * draftRow + kHomeDraftSpacing;
    final aboveNav = height - top - kHomeDraftNavGap - navClearance;
    final emptyCard = fits
        ? twoRowsTall
        : math.max(kHomeEmptyCardLeast, math.min(twoRowsTall, aboveNav));
    return HomeLayout._(
      scale: scale,
      fits: fits,
      gapAboveHero: gapAboveHero,
      hero: hero,
      gapAboveTools: gapAboveTools,
      tools: tools,
      gapAboveTitle: gapAboveTitle,
      title: title,
      gapAboveDrafts: gapAboveDrafts,
      draftRow: draftRow,
      emptyCard: emptyCard,
      height: height,
    );
  }

  /// 1 where everything is at its full size, 0 at its least.
  final double scale;

  /// Whether both rows of drafts sit above the nav.
  final bool fits;

  final double gapAboveHero;
  final double hero;
  final double gapAboveTools;
  final double tools;
  final double gapAboveTitle;
  final double title;
  final double gapAboveDrafts;

  /// A draft card's height.
  final double draftRow;

  /// The card standing in before any edit: the two rows' height wherever
  /// they fit, never under the nav, never under [kHomeEmptyCardLeast].
  final double emptyCard;

  /// From under the header to the bottom of the page: the room, unless the
  /// page must be taller to hold one row above the nav.
  final double height;

  /// From under the drafts' title gap to the bottom of the page.
  double get draftsBox =>
      height -
      (gapAboveHero +
          hero +
          gapAboveTools +
          tools +
          gapAboveTitle +
          title +
          gapAboveDrafts);
}
