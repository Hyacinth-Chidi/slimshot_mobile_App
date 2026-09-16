import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/animatable_double.dart';

/// The curve sheet: four families as **tabs**, four cells each.
///
/// Tabs rather than four stacked rows. Sixteen cells at once is a wall — and
/// the families are alternatives, not a list to scan: a user picks *a* curve,
/// not one from each group. Tabs also give each cell room to draw its curve
/// large enough to tell apart, which is the whole reason the cells are graphs
/// rather than words.
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
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // The content is short enough to fit, but a landscape phone or a split
    // screen is not — and a clipped row of curves is worse than a scroll.
    isScrollControlled: true,
    builder: (context) => _KeyframeEasingSheet(
      current: current,
      onSelected: onSelected,
    ),
  );
}

/// The cell row's own side padding, and the gutter each cell adds per side.
const double _kRowPadding = 16;
const double _kGutter = 6;

/// The label under a cell: its 8px top gap, one 12px text line (17px measured),
/// and the row's 16/8 vertical padding — 49px, rounded up for breathing room.
/// A few spare pixels read as air; a few short are an overflow stripe.
const double _kLabelBlock = 52;

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

class _KeyframeEasingSheetState extends State<_KeyframeEasingSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// The curve chosen so far, applied live.
  ///
  /// **Every tap applies immediately** and the ✓ only dismisses. A sheet that
  /// held the choice until confirmed would make the user commit to a curve they
  /// have not seen move; applying live means they scrub and watch. Undo is one
  /// step per tap, which is the right granularity for a picker.
  late KeyframeInterpolation _chosen = widget.current;

  @override
  void initState() {
    super.initState();
    // Opens on the family the current curve belongs to, so the highlighted
    // cell is visible rather than hidden behind a tab the user has to find.
    final index = kKeyframeEasingGroups.indexWhere(
      (g) =>
          g.easeIn == widget.current ||
          g.easeOut == widget.current ||
          g.easeInOut == widget.current,
    );
    _tabs = TabController(
      length: kKeyframeEasingGroups.length,
      vsync: this,
      initialIndex: index < 0 ? 0 : index,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(),
            const Divider(height: 1, color: AppColors.border),
            // **Sized from the width, because that is what the height
            // actually depends on.** The cells are squares in a four-column
            // row, so their side is a quarter of the usable width; the label
            // below adds a fixed line. A `TabBarView` needs a bounded height
            // and refuses to be measured intrinsically (it is a viewport), so
            // the arithmetic happens here — and since every tab holds the same
            // four shapes, they all measure identically and switching tabs
            // never resizes the sheet.
            LayoutBuilder(
              builder: (context, constraints) {
                // Each of the four columns gets a quarter of what is left
                // after the row's side padding, minus its own gutters. The
                // square aims to match that width; if the label needs more of
                // the box than expected the `Expanded` above simply gives the
                // graph less, so the cell shrinks rather than overflowing.
                final share = (constraints.maxWidth - _kRowPadding * 2) / 4;
                final cell = (share - _kGutter * 2).clamp(32.0, 120.0).toDouble();
                return SizedBox(
                  height: cell + _kLabelBlock,
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      for (final group in kKeyframeEasingGroups) _cells(group),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.textPrimary,
            indicatorSize: TabBarIndicatorSize.label,
            indicatorWeight: 2,
            dividerColor: Colors.transparent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              for (final group in kKeyframeEasingGroups) Tab(text: group.label),
            ],
          ),
        ),
        GestureDetector(
          key: const Key('keyframe_easing_done'),
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      padding: const EdgeInsets.fromLTRB(
        _kRowPadding,
        16,
        _kRowPadding,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, easing) in cells)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kGutter),
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
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _chosen = easing);
        widget.onSelected(easing);
      },
      child: Column(
        children: [
          // **The graph takes what is left, rather than demanding a square.**
          // The label's line is whatever the text scale makes it, so a column
          // that sized the square first could always be a few pixels over —
          // which is an overflow stripe, not a layout. Giving the square the
          // remainder makes the cell fit at any height by construction.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(
                  color: selected ? AppColors.textPrimary : AppColors.border,
                  width: selected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: easing == KeyframeInterpolation.linear
                    // **None is not a straight line drawn in the graph box.**
                    // A diagonal reads as "linear", a curve among curves; the
                    // crossed circle reads as "no curve at all", which is what
                    // choosing it means.
                    ? const Center(
                        child: Icon(
                          LucideIcons.ban,
                          color: AppColors.textSecondary,
                          size: 30,
                        ),
                      )
                    : CustomPaint(
                        painter: _EasingCurvePainter(
                          easing: easing,
                          colour: AppColors.textPrimary,
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
              fontWeight: FontWeight.w500,
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
