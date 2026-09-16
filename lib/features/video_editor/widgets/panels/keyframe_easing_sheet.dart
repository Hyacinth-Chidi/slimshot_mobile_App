import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/animatable_double.dart';
import 'editor_sheet.dart';

/// The curve sheet: four families across the top, four cells each.
///
/// One family at a time rather than four stacked rows. Sixteen cells at once is
/// a wall — and the families are alternatives, not a list to scan: a user picks
/// *a* curve, not one from each group. It also gives each cell room to draw its
/// curve large enough to tell apart, which is the whole reason the cells are
/// graphs rather than words.
///
/// **Styled from the effects sheet, not from Material.** Same background and
/// corner radius, same grab handle, the same pill row for the families, and the
/// same purple selection language for the cells. A picker that invented its own
/// look — a white highlight, an underlined tab bar — reads as a different app
/// even when every individual choice is defensible.
///
/// **It shapes travel that already exists and never places a diamond.** The
/// plus button is the one control that creates instants. With nothing to ease
/// the icon that opens this is disabled, so the sheet should not be reachable
/// in that state at all.
Future<void> showKeyframeEasingSheet(
  BuildContext context, {
  required KeyframeInterpolation current,
  required ValueChanged<KeyframeInterpolation> onSelected,
}) {
  return showEditorSheet<void>(
    context,
    // The content is short enough to fit, but a landscape phone or a split
    // screen is not — and a clipped row of curves is worse than a scroll.
    builder: (context) => _KeyframeEasingSheet(
      current: current,
      onSelected: onSelected,
    ),
  );
}

/// **One edge inset for the whole sheet.** The family row, the cell row and the
/// ✓ all align to it, so nothing is a few pixels out from its neighbour. 16 is
/// what the effects sheet's category row already uses.
const double _kEdge = 16;

/// The gap between two cells. Each cell adds half of it per side.
const double _kCellGap = 10;

/// The family row's height, matching the effects sheet's category row.
const double _kFamilyRowHeight = 36;

class _KeyframeEasingSheet extends StatefulWidget {
  const _KeyframeEasingSheet({
    required this.current,
    required this.onSelected,
  });

  final KeyframeInterpolation current;
  final ValueChanged<KeyframeInterpolation> onSelected;

  @override
  State<_KeyframeEasingSheet> createState() => _KeyframeEasingSheetState();
}

class _KeyframeEasingSheetState extends State<_KeyframeEasingSheet> {
  /// Which family is showing.
  ///
  /// A plain index rather than a `TabController`: the row above is four pills,
  /// not a Material tab bar, and one row of four cells needs no swipe gesture
  /// or animated page view to switch between.
  late int _family = _familyOf(widget.current);

  /// The curve chosen so far, applied live.
  ///
  /// **Every tap applies immediately** and the ✓ only dismisses. A sheet that
  /// held the choice until confirmed would make the user commit to a curve they
  /// have not seen move; applying live means they scrub and watch. Undo is one
  /// step per tap, which is the right granularity for a picker.
  late KeyframeInterpolation _chosen = widget.current;

  /// The family [curve] belongs to, so the sheet opens showing the highlighted
  /// cell rather than hiding it behind a pill the user has to find.
  ///
  /// `linear` (None) belongs to every family equally, so it answers 0 and the
  /// sheet opens on Default.
  static int _familyOf(KeyframeInterpolation curve) {
    final index = kKeyframeEasingGroups.indexWhere(
      (g) =>
          g.easeIn == curve || g.easeOut == curve || g.easeInOut == curve,
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            _familyRow(),
            const SizedBox(height: 14),
            _cells(kKeyframeEasingGroups[_family]),
            // The sheet's own bottom inset, matching the side edge so the row
            // sits in an even box rather than pressed against the bottom.
            const SizedBox(height: _kEdge),
          ],
        ),
      ),
    );
  }

  /// The grab handle, drawn exactly as every other sheet in the app draws it.
  Widget _handle() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// The family row, in the **same pill shape the effects sheet uses** for its
  /// categories — a filled capsule for the active one, plain text otherwise.
  ///
  /// Not a Material `TabBar`: its underline indicator and ripple belong to a
  /// different visual language than the rest of this app's sheets, and a second
  /// idiom for "pick a category" is a tax on someone who has already learned
  /// the first.
  Widget _familyRow() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: _kFamilyRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _kEdge),
              itemCount: kKeyframeEasingGroups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final group = kKeyframeEasingGroups[index];
                final isActive = index == _family;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _family = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      group.label,
                      style: TextStyle(
                        color: isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        GestureDetector(
          key: const Key('keyframe_easing_done'),
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: _kEdge, vertical: 8),
            child: Icon(
              LucideIcons.check,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cells(KeyframeEasingGroup group) {
    final cells = <(String, KeyframeInterpolation)>[
      ('None', group.none),
      ('Ease in', group.easeIn),
      ('Ease out', group.easeOut),
      ('Ease', group.easeInOut),
    ];

    return Padding(
      // **Half a gap of side padding**, because each cell already carries the
      // other half. That makes the outer margin equal to the gap between
      // cells, so the row reads as evenly spaced rather than tight at the
      // edges — which is what the uneven version looked like.
      padding: const EdgeInsets.symmetric(horizontal: _kEdge - _kCellGap / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, easing) in cells)
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: _kCellGap / 2),
                child: _cell(label, easing),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String label, KeyframeInterpolation easing) {
    final selected = easing == _chosen;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _chosen = easing);
        widget.onSelected(easing);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              // **The app's selection language**, the same one the effect
              // tiles use: a purple-tinted fill inside a purple border. The
              // white border this replaced was a second idiom for "selected"
              // and read as a different app.
              decoration: BoxDecoration(
                color: selected ? AppColors.highlight : AppColors.surface,
                border: Border.all(
                  color: selected ? AppColors.primaryStart : AppColors.border,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: easing == KeyframeInterpolation.linear
                    // **None is not a straight line drawn in the graph box.**
                    // A diagonal reads as "linear", a curve among curves; the
                    // crossed circle reads as "no curve at all", which is what
                    // choosing it means.
                    ? Center(
                        child: Icon(
                          LucideIcons.ban,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          size: 26,
                        ),
                      )
                    : CustomPaint(
                        painter: _EasingCurvePainter(
                          easing: easing,
                          colour: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          gridColour: AppColors.border,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plots a curve from [applyKeyframeEasing] itself, over a dashed grid.
///
/// Never an approximation drawn by eye: the tile has to promise exactly the
/// motion the renderer will produce, which is the same three-consumer rule the
/// text animation tiles follow. The grid is what makes a shape readable as a
/// *curve* — without it a lone arc gives the eye nothing to judge its bend
/// against.
class _EasingCurvePainter extends CustomPainter {
  const _EasingCurvePainter({
    required this.easing,
    required this.colour,
    required this.gridColour,
  });

  final KeyframeInterpolation easing;
  final Color colour;
  final Color gridColour;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    final paint = Paint()
      ..color = colour
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Dense enough that the bounce family's corners land on their real
    // positions rather than being cut by a chord.
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final v = applyKeyframeEasing(easing, t);
      final x = t * size.width;
      // y is inverted: a curve that *rises* has to read as rising on screen.
      final y = size.height - v * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColour
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Thirds, dashed — the quarters a curve is actually read against.
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      _dashedLine(canvas, Offset(x, 0), Offset(x, size.height), grid);
      _dashedLine(canvas, Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawRect(Offset.zero & size, grid);
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 3.0;
    const gap = 3.0;
    final total = (to - from).distance;
    if (total <= 0) return;
    final step = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total).toDouble();
      canvas.drawLine(from + step * travelled, from + step * end, paint);
      travelled = end + gap;
    }
  }

  @override
  bool shouldRepaint(_EasingCurvePainter old) =>
      old.easing != easing ||
      old.colour != colour ||
      old.gridColour != gridColour;
}
