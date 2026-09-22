import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'value_ruler.dart';

/// How far the canvas is zoomed into the project's frame.
///
/// **A ruler, not a slider**, for the reason the ruler exists: a pixel is
/// always the same amount of zoom, so 1.4x is as reachable on a small phone as
/// on a tablet. On a slider the whole 1x–5x range is squeezed into whatever
/// width the panel gets, and a tenth of a step — a visible difference in the
/// picture — lands inside a couple of pixels.
///
/// Snaps to 1x: "all the way back out" is a value people return to exactly.
class ZoomPanel extends StatelessWidget {
  const ZoomPanel({
    super.key,
    required this.currentScale,
    required this.onChanged,
    required this.onReset,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double currentScale;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  /// One undo snapshot covers a whole drag; the frames between write live.
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;

  /// The full range in roughly one screen's drag — zoom is explored, not
  /// dialled in, and the pinch on the canvas is the coarse control.
  static const double _unitsPerPixel = 0.01;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueRuler(
          value: currentScale,
          min: _minScale,
          max: _maxScale,
          unitsPerPixel: _unitsPerPixel,
          snapPoints: const [_minScale],
          format: (v) => '${(v * 100).round()}%',
          onChangeStart: onChangeStart,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          // Tapping the readout is the ruler's own reset affordance, which is
          // what makes exploring a value safe. The chip below stays because it
          // is discoverable without knowing that.
          onReset: currentScale > _minScale ? onReset : null,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // **Flexible, because the chip beside it is not.** The hint and
            // the Reset chip overflowed the row by 78px at 360dp — a
            // yellow-black stripe on a narrow phone. The hint is the part
            // that can give, so it ellipsises and the chip keeps its size.
            const Flexible(
              child: Text(
                'Pinch to adjust • Drag to pan',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (currentScale > _minScale)
              GestureDetector(
                onTap: onReset,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    // Was `Colors.deepOrange`, a hue that appears nowhere else
                    // in the editor's chrome — it read as a warning about an
                    // action that merely returns to the default.
                    color: AppColors.highlight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primaryStart),
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
