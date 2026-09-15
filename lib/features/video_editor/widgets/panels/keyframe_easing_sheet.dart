import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/animatable_double.dart';

/// The easing sheet: four families, four cells each.
///
/// **It acts on the diamond under the playhead**, and places one if there is
/// none — the same rule the intensity slider and the pinch gesture follow, so
/// no two controls can disagree about what "here" means.
///
/// Deliberately small: it is a picker, not a panel, and a half-screen sheet for
/// sixteen cells would bury the canvas for no reason. The column is
/// `MainAxisSize.min`, so it takes the height its four groups need and no more.
Future<void> showKeyframeEasingSheet(
  BuildContext context, {
  required KeyframeInterpolation current,
  required ValueChanged<KeyframeInterpolation> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // **Scroll-controlled so the sheet can be as tall as its content needs.**
    // Without it `showModalBottomSheet` caps at roughly half the screen, and
    // four groups of four overflow that on a short viewport — which is a
    // clipped bottom row, not a scrollbar. It is still a *small* sheet: the
    // column below is `MainAxisSize.min`, so it takes only the height it uses.
    isScrollControlled: true,
    builder: (context) => _KeyframeEasingSheet(
      current: current,
      onSelected: onSelected,
    ),
  );
}

class _KeyframeEasingSheet extends StatelessWidget {
  const _KeyframeEasingSheet({
    required this.current,
    required this.onSelected,
  });

  final KeyframeInterpolation current;
  final ValueChanged<KeyframeInterpolation> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        // Scrollable as a last resort: on a very short viewport (a landscape
        // phone, a split screen) the groups still have somewhere to go rather
        // than being clipped.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              for (final group in kKeyframeEasingGroups)
                _group(context, group),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(BuildContext context, KeyframeEasingGroup group) {
    // The four cells, in the order the design names them.
    final cells = <(String, KeyframeInterpolation)>[
      ('None', group.none),
      ('Ease in', group.easeIn),
      ('Ease out', group.easeOut),
      ('Ease', group.easeInOut),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (label, easing) in cells)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _cell(context, label, easing),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    String label,
    KeyframeInterpolation easing,
  ) {
    final selected = easing == current;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onSelected(easing);
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryStart.withValues(alpha: 0.15) : null,
          border: Border.all(
            color: selected ? AppColors.primaryStart : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            // **The curve itself, drawn.** "Quadratic ease out" and "Cubic ease
            // out" are indistinguishable as words and obvious as shapes; a
            // text-only chip would make the user try each one to find out what
            // it does.
            SizedBox(
              width: 30,
              height: 20,
              child: CustomPaint(
                painter: _EasingCurvePainter(
                  easing: easing,
                  colour: selected
                      ? AppColors.primaryStart
                      : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color:
                    selected ? AppColors.primaryStart : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plots a curve from [applyKeyframeEasing] itself.
///
/// Never an approximation drawn by eye: the tile has to promise exactly the
/// motion the renderer will produce, which is the same three-consumer rule the
/// text animation tiles follow.
class _EasingCurvePainter extends CustomPainter {
  const _EasingCurvePainter({required this.easing, required this.colour});

  final KeyframeInterpolation easing;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    const steps = 24;
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

  @override
  bool shouldRepaint(_EasingCurvePainter old) =>
      old.easing != easing || old.colour != colour;
}
