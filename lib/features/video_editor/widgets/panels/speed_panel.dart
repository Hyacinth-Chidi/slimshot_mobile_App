import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/speed/speed_curve.dart';
import 'value_ruler.dart';

/// A clip's flat playback speed.
///
/// **A ruler, not a slider**, for the reason the ruler exists: sensitivity is
/// per pixel rather than per widget width. That matters more here than
/// anywhere else in the editor, because the model's range is
/// [SpeedCurve.kMinSpeed]–[SpeedCurve.kMaxSpeed] — 0.1x to 10x — and a slider
/// spanning that would put 1x a tenth of the way along, making every ordinary
/// value a pixel-hunt while the interesting end got a sliver of track.
///
/// The slider this replaced dodged that by capping at **2x**, so 4x was not
/// reachable from the Speed tool at all even though the model, the engine and
/// the speed *curve* all support it.
///
/// Snaps to 1x, because normal speed is a value people return to exactly and
/// 0.98x is a mistake nobody meant.
class SpeedPanel extends StatelessWidget {
  const SpeedPanel({
    super.key,
    required this.displaySpeed,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onReset,
    this.emptyMessage,
  });

  final double displaySpeed;
  final ValueChanged<double> onChanged;

  /// One undo snapshot covers a whole drag; the frames between write live.
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  /// Tapping the readout returns to 1x. Null hides the affordance.
  final VoidCallback? onReset;

  final String? emptyMessage;

  /// Fine enough that 1.25x is reachable, coarse enough that the far end is a
  /// drag rather than an expedition: the full range is about four screens.
  static const double _unitsPerPixel = 0.01;

  @override
  Widget build(BuildContext context) {
    if (emptyMessage != null) {
      return Center(
        child: Text(
          emptyMessage!,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      );
    }

    return Center(
      child: ValueRuler(
        value: displaySpeed,
        min: SpeedCurve.kMinSpeed,
        max: SpeedCurve.kMaxSpeed,
        unitsPerPixel: _unitsPerPixel,
        snapPoints: const [1.0],
        // One decimal: "2.5x" is how a speed is written, where "2.50x"
        // reads as a measurement. The ruler still moves in hundredths, so a
        // value lands on the tenth it shows rather than near it.
        format: (v) => '${v.toStringAsFixed(1)}x',
        onChangeStart: onChangeStart,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        onReset: onReset,
      ),
    );
  }
}
