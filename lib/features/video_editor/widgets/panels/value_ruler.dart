import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// A value set by sliding a strip of ticks under a fixed centre indicator.
///
/// The control every Transform tab is built from. Two things make it a ruler
/// rather than a slider, and both are deliberate:
///
/// - **Sensitivity is per pixel, not per widget width.** A slider spreads its
///   whole range across whatever width it gets, so precision depends on the
///   phone; here a pixel is always the same amount ([unitsPerPixel]), and a
///   large range is reached by dragging more than once. That is what makes a
///   scale of 0.1–8× settable to two decimal places on any screen.
/// - **The ticks travel with the finger and the number rises as the finger
///   goes right.** The ticks carry no labels, so there is nothing for that to
///   contradict — they are the texture of motion, and the readout is the
///   value. Labelled ticks would have to run backwards to keep "right is up",
///   which is why they are absent.
///
/// **Anchor-based, never accumulated.** The value is
/// `anchor + (fingerX - anchorX) * unitsPerPixel`, clamped. A running sum of
/// deltas loses whatever a clamp swallows, and the ruler then sits offset from
/// the finger by the overshoot — the fault the trim handles fixed once already.
///
/// Reports [onChangeStart] and [onChangeEnd] so the caller can take **one** undo
/// snapshot per drag, the rule every gesture in this codebase follows.
class ValueRuler extends StatefulWidget {
  const ValueRuler({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.unitsPerPixel,
    required this.onChanged,
    required this.format,
    this.onChangeStart,
    this.onChangeEnd,
    this.onReset,
    this.snapPoints = const [],
    this.snapRadius,
  });

  final double value;
  final double min;
  final double max;

  /// How much the value changes per pixel of drag.
  final double unitsPerPixel;

  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  /// Tapping the readout. Null hides the affordance.
  ///
  /// The default is one tap away, which is what makes exploring a value safe.
  final VoidCallback? onReset;

  /// Values the ruler lands on exactly when the finger is close.
  ///
  /// A rotation reading 89.6° is a mistake nobody meant; 90° is what they were
  /// reaching for. Snapping is *not* a detent the finger has to push through —
  /// past the radius the value moves freely again.
  final List<double> snapPoints;

  /// How close counts as close, in value units. Defaults to what a finger can
  /// plausibly aim for: eight pixels' worth of travel.
  final double? snapRadius;

  /// The readout text for a value — `1.4×`, `-12°`, `0.20`.
  final String Function(double value) format;

  @override
  State<ValueRuler> createState() => _ValueRulerState();
}

class _ValueRulerState extends State<ValueRuler> {
  /// The value and finger position when the drag began.
  double _anchorValue = 0;
  double _anchorX = 0;

  /// Whether the last reported value sat on a snap point, so the haptic fires
  /// on *arriving* at one rather than on every frame inside its radius.
  bool _wasSnapped = false;

  /// The value most recently handed to [ValueRuler.onChanged].
  ///
  /// **Compared against this, never against `widget.value`.** The parent may
  /// not have rebuilt between two drag frames — a test harness never does, and
  /// a busy frame in the app may not either — so `widget.value` can lag what
  /// this ruler already said. Guarding on it would swallow the report that
  /// brings the value *back* to where it started, leaving the caller holding a
  /// stale extreme. Caught by the anchor test.
  double _lastReported = 0;

  double get _snapRadius => widget.snapRadius ?? widget.unitsPerPixel * 8;

  void _start(DragStartDetails d) {
    _anchorValue = widget.value;
    _anchorX = d.globalPosition.dx;
    _lastReported = widget.value;
    _wasSnapped = false;
    widget.onChangeStart?.call();
  }

  void _update(DragUpdateDetails d) {
    // Right is up. The ticks below travel with the finger, so the motion and
    // the readout agree.
    final raw = _anchorValue + (d.globalPosition.dx - _anchorX) * widget.unitsPerPixel;
    var next = raw.clamp(widget.min, widget.max).toDouble();

    var snapped = false;
    for (final point in widget.snapPoints) {
      if ((next - point).abs() <= _snapRadius) {
        next = point;
        snapped = true;
        break;
      }
    }
    if (snapped && !_wasSnapped) HapticFeedback.selectionClick();
    _wasSnapped = snapped;

    if (next != _lastReported) {
      _lastReported = next;
      widget.onChanged(next);
    }
  }

  void _end(DragEndDetails _) => widget.onChangeEnd?.call();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const Key('value_ruler_readout'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onReset == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  widget.onReset!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              widget.format(widget.value),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                // Tabular figures so the readout does not jitter in width as
                // digits change under the finger.
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Anchored on pointer-down, not on arena acceptance. Alone, a
          // horizontal recogniser is accepted on its first move; beside a
          // scrolling sheet's vertical recogniser it has to win the arena
          // first, and with the default behaviour the travel spent winning it
          // — a touch slop's worth — was silently dropped from the drag. The
          // trim handles follow the same rule for the same reason.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          child: SizedBox(
            height: _kTapeHeight,
            width: double.infinity,
            child: CustomPaint(
              painter: _TapePainter(
                // The tape's phase in pixels: the value expressed as distance,
                // so ticks slide right as the value rises — with the finger.
                phasePx: widget.value / widget.unitsPerPixel,
                tickColour: AppColors.border,
                majorTickColour: AppColors.textSecondary,
                indicatorColour: AppColors.primaryStart,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const double _kTapeHeight = 44;

/// Ticks every 8px, a taller one every fifth, and a fixed centre indicator.
class _TapePainter extends CustomPainter {
  const _TapePainter({
    required this.phasePx,
    required this.tickColour,
    required this.majorTickColour,
    required this.indicatorColour,
  });

  final double phasePx;
  final Color tickColour;
  final Color majorTickColour;
  final Color indicatorColour;

  static const double _spacing = 8;
  static const int _majorEvery = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = tickColour
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final major = Paint()
      ..color = majorTickColour
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final centre = size.width / 2;
    final midY = size.height / 2;

    // Ticks are indexed from the value's own origin, so a major tick stays
    // attached to the same value as the tape slides rather than to a screen
    // position. Tick `i` sits at `centre + i*spacing + phasePx`, and `phasePx`
    // grows with the value — so as a rightward drag raises the value, the
    // ticks move right too, with the finger.
    final first = ((-centre - phasePx) / _spacing).floor();
    final last = ((size.width - centre - phasePx) / _spacing).ceil();
    for (var i = first; i <= last; i++) {
      final x = centre + i * _spacing + phasePx;
      if (x < 0 || x > size.width) continue;
      final isMajor = i % _majorEvery == 0;
      final half = isMajor ? 10.0 : 5.0;
      canvas.drawLine(
        Offset(x, midY - half),
        Offset(x, midY + half),
        isMajor ? major : minor,
      );
    }

    // Fade the tape out toward both edges so it reads as continuing past the
    // widget rather than stopping at a wall.
    final fade = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.background,
          AppColors.background.withValues(alpha: 0),
          AppColors.background.withValues(alpha: 0),
          AppColors.background,
        ],
        stops: const [0, 0.15, 0.85, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fade);

    // The indicator, last, so it sits over the fade.
    final indicator = Paint()
      ..color = indicatorColour
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(centre, 2), Offset(centre, size.height - 2), indicator);
  }

  @override
  bool shouldRepaint(_TapePainter old) =>
      old.phasePx != phasePx ||
      old.tickColour != tickColour ||
      old.majorTickColour != majorTickColour ||
      old.indicatorColour != indicatorColour;
}
