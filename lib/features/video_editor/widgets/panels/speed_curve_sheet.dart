import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/speed/speed_curve.dart';
import '../../models/video_segment.dart';
import '../../providers/video_editor_notifier.dart';
import 'editor_sheet.dart';

/// One edge inset, matching every other sheet's.
const double _kEdge = 16;

/// How tall the graph is. Enough to read a 0.1×–10× swing without crowding the
/// preset row above it inside the sheet's 45% cap.
const double _kGraphHeight = 150;

/// Touch radius for grabbing a point, in logical pixels. Generous: the points
/// are 6px dots and a finger is not.
const double _kGrabRadius = 28;

/// The Speed curve sheet — a clip's speed as a shape, not a number.
///
/// A ramp is what the plain Speed panel cannot express, and what the keyframe
/// system structurally cannot hold: every keyframable property is read *at* a
/// progress, while speed decides what progress *means*. `SpeedCurve` is the
/// model; this sheet is its face.
///
/// **Presets first, then the graph.** The seven named curves cover what people
/// actually reach for, and each is a starting point rather than a destination —
/// dragging any point makes the curve the clip's own (`presetId` goes null) and
/// the Custom tile stops being special. A tap is the whole interaction for most
/// users; the graph is there when the tap is not enough.
///
/// A sheet, not a panel, by the rule in CLAUDE.md: this is a set of choices
/// about the picture, not an edit made on the canvas or the timeline.
class SpeedCurveSheet extends ConsumerStatefulWidget {
  const SpeedCurveSheet({super.key});

  @override
  ConsumerState<SpeedCurveSheet> createState() => _SpeedCurveSheetState();
}

class _SpeedCurveSheetState extends ConsumerState<SpeedCurveSheet> {
  VideoEditorNotifier get _notifier => ref.read(videoEditorProvider.notifier);

  void _applyPreset(SpeedCurvePreset? preset) {
    HapticFeedback.selectionClick();
    _notifier.setClipSpeedCurve(preset?.curve);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoEditorProvider);
    final segment = state.selectedSegment;
    final curve = segment?.speedCurve;
    final maxHeight =
        MediaQuery.sizeOf(context).height * kEditorSheetPreviewFraction;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _handle(),
              _header(segment),
              // Loose, so the body takes only the height it needs on a tall
              // screen and scrolls under the cap on a short one.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _presetRow(curve),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
                        child: SpeedCurveEditor(
                          // With no curve the graph shows the flat 1× line, so
                          // the sheet reads the same whether or not one is set
                          // and a first drag starts from Normal.
                          curve: curve ?? SpeedCurve.constant(1.0),
                          enabled: segment != null,
                          onChangeStart: _notifier.beginClipSpeedCurve,
                          onChanged: _notifier.setClipSpeedCurveLive,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(VideoSegment? segment) {
    // The curved length, which is the number the user is actually shaping.
    final label =
        segment == null ? '' : '${segment.duration.toStringAsFixed(1)}s';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kEdge),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Speed curve',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          GestureDetector(
            key: const Key('speed_curve_done'),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
            },
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                LucideIcons.check,
                color: AppColors.primaryStart,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetRow(SpeedCurve? current) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _kEdge),
        children: [
          _presetTile(
            id: 'none',
            label: 'Normal',
            selected: current == null,
            onTap: () => _applyPreset(null),
          ),
          for (final p in kSpeedCurvePresets)
            _presetTile(
              id: p.id,
              label: p.label,
              // A curve that has been dragged carries no preset id, so nothing
              // is highlighted — which is the truth about what it is.
              selected: current?.presetId == p.id,
              onTap: () => _applyPreset(p),
            ),
        ],
      ),
    );
  }

  Widget _presetTile({
    required String id,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        key: Key('speed_preset_$id'),
        onTap: onTap,
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(AppColors.highlight, AppColors.surface)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryStart : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 22,
                width: 56,
                child: CustomPaint(
                  painter: _PresetGlyphPainter(
                    curve: speedCurvePresetById(id)?.curve,
                    color: selected
                        ? AppColors.primaryStart
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color:
                      selected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
}

/// The curve as a draggable graph: source across, speed up.
///
/// **Only the speed moves.** A point's `x` is where on the footage it sits, and
/// dragging that sideways would slide the moment being shaped out from under
/// the user's finger — the same reason the curve is parametrised over the
/// source in the first place. Vertical drag alone keeps one gesture meaning one
/// thing.
///
/// Speed maps to height **logarithmically**, because the range is 0.1×–10× and
/// linearly 1× would sit at a tenth of the height with nine tenths given to
/// speeds nobody uses. On a log scale 1× is the exact middle and a halving
/// looks like a doubling upside down, which is what the ear and eye expect.
class SpeedCurveEditor extends StatefulWidget {
  const SpeedCurveEditor({
    super.key,
    required this.curve,
    required this.onChanged,
    this.onChangeStart,
    this.enabled = true,
  });

  final SpeedCurve curve;

  /// Called per drag frame with the whole new curve.
  final ValueChanged<SpeedCurve> onChanged;

  /// Called once when a drag begins, for the undo snapshot.
  final VoidCallback? onChangeStart;

  final bool enabled;

  @override
  State<SpeedCurveEditor> createState() => _SpeedCurveEditorState();
}

class _SpeedCurveEditorState extends State<SpeedCurveEditor> {
  /// Which point the finger has hold of, or null between drags.
  int? _dragIndex;

  /// The speed that point had when the drag began, so the move is anchored
  /// rather than accumulated — a dropped frame must not leave the point
  /// offset from the finger for good. The same rule as the trim handles.
  double _anchorSpeed = 1.0;
  double _anchorY = 0.0;

  static double _speedToUnit(double speed) {
    final lo = math.log(SpeedCurve.kMinSpeed);
    final hi = math.log(SpeedCurve.kMaxSpeed);
    return ((math.log(speed) - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  static double _unitToSpeed(double unit) {
    final lo = math.log(SpeedCurve.kMinSpeed);
    final hi = math.log(SpeedCurve.kMaxSpeed);
    return math.exp(lo + (hi - lo) * unit.clamp(0.0, 1.0));
  }

  Offset _pointOffset(int index, Size size) {
    final p = widget.curve.points[index];
    return Offset(
      p.x * size.width,
      (1 - _speedToUnit(p.speed)) * size.height,
    );
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (!widget.enabled) return;
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < widget.curve.points.length; i++) {
      final d = (_pointOffset(i, size) - details.localPosition).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    if (best < 0 || bestDistance > _kGrabRadius) return;
    _dragIndex = best;
    _anchorSpeed = widget.curve.points[best].speed;
    _anchorY = details.localPosition.dy;
    widget.onChangeStart?.call();
    HapticFeedback.selectionClick();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final index = _dragIndex;
    if (index == null || size.height <= 0) return;
    final travel = (_anchorY - details.localPosition.dy) / size.height;
    final unit = _speedToUnit(_anchorSpeed) + travel;
    widget.onChanged(widget.curve.withPointSpeed(index, _unitToSpeed(unit)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, _kGraphHeight);
        // **The graph must claim the pointer on down.** It lives inside the
        // sheet's `SingleChildScrollView`, and a vertical drag there is the
        // scroll view's by default — the arena does not resolve until the
        // finger has travelled `kTouchSlop`, and with a *vertical* competitor
        // the scroll view simply wins. The same fault the trim handles and the
        // `ValueRuler` each hit, and the same fix: accept immediately, and
        // take the drag from pointer-down so no travel is lost.
        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _ImmediateVerticalDragRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    _ImmediateVerticalDragRecognizer>(
              () => _ImmediateVerticalDragRecognizer(debugOwner: this),
              (recognizer) {
                recognizer.onStart = (d) => _onPanStart(d, size);
                recognizer.onUpdate = (d) => _onPanUpdate(d, size);
                recognizer.onEnd = (_) {
                  _dragIndex = null;
                };
                recognizer.onCancel = () {
                  _dragIndex = null;
                };
              },
            ),
          },
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CustomPaint(
              painter: _SpeedCurvePainter(
                curve: widget.curve,
                enabled: widget.enabled,
                activeIndex: _dragIndex,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A vertical drag that takes the pointer the moment it lands.
///
/// See the note at its use: inside a scroll view a plain vertical drag never
/// reaches this widget at all.
class _ImmediateVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  _ImmediateVerticalDragRecognizer({super.debugOwner}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Draws the graph: a 1× reference line, the curve, and a dot per point.
class _SpeedCurvePainter extends CustomPainter {
  _SpeedCurvePainter({
    required this.curve,
    required this.enabled,
    this.activeIndex,
  });

  final SpeedCurve curve;
  final bool enabled;
  final int? activeIndex;

  double _y(double speed, Size size) =>
      (1 - _SpeedCurveEditorState._speedToUnit(speed)) * size.height;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()
      ..color = AppColors.surface
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      frame,
    );

    // The 1× line: the reference every reading is against.
    final unity = _y(1.0, size);
    final guide = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, unity), Offset(size.width, unity), guide);

    // The curve, sampled rather than drawn segment by segment, so the eye sees
    // the speed it will actually get at every moment.
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final point = Offset(x * size.width, _y(curve.speedAtSource(x), size));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = enabled ? AppColors.primaryStart : AppColors.textTertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < curve.points.length; i++) {
      final p = curve.points[i];
      final centre = Offset(p.x * size.width, _y(p.speed, size));
      final active = i == activeIndex;
      canvas.drawCircle(
        centre,
        active ? 9 : 6,
        Paint()..color = AppColors.background,
      );
      canvas.drawCircle(
        centre,
        active ? 9 : 6,
        Paint()
          ..color = enabled ? AppColors.primaryStart : AppColors.textTertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeedCurvePainter old) =>
      old.curve != curve ||
      old.enabled != enabled ||
      old.activeIndex != activeIndex;
}

/// The little curve drawn on a preset tile — the shape itself, because
/// "Montage" and "Bullet" are words for pictures.
class _PresetGlyphPainter extends CustomPainter {
  _PresetGlyphPainter({required this.curve, required this.color});

  final SpeedCurve? curve;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;

    final c = curve;
    if (c == null) {
      // Normal: a flat line, which is exactly what no curve means.
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final path = Path();
    const steps = 32;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      final unit = _SpeedCurveEditorState._speedToUnit(c.speedAtSource(x));
      final point = Offset(x * size.width, (1 - unit) * size.height);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PresetGlyphPainter old) =>
      old.curve != curve || old.color != color;
}
