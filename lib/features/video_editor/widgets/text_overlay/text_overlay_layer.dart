import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../logic/text_overlay_geometry.dart';
import '../../models/text_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import 'text_overlay_painter.dart';

/// Text overlays on the preview canvas, with their selection frame.
///
/// Two things are drawn per overlay and they are deliberately separate:
///
/// - **The body** — the text box measured by [TextOverlayLayout], scaled and
///   rotated about its centre. It is laid out inside a square big enough to
///   hold the box at any scale and rotation, because every `RenderBox` gates
///   hit-testing on its own size: a `Transform.scale`d child is untouchable
///   outside its parent's unscaled rect, which is why the old layer's text
///   could not be grabbed once it was scaled up. The gesture detector sits
///   innermost, on the real box, so only the visible text catches a finger.
/// - **The frame** — a sibling drawn in *canvas* space from the body's
///   transformed corners. Handles keep one screen size whatever the text's
///   scale (CapCut's behaviour), and their drags are computed against the
///   box's centre and axes, so they feel the same on a rotated box.
///
/// Every drag is anchor-based (start value + total displacement), never a
/// running sum of deltas — a clamped frame would otherwise leave the handle
/// offset from the finger, the lesson the timeline's trim handles taught.
class TextOverlayLayer extends ConsumerStatefulWidget {
  final Size videoCanvasSize;
  final void Function(TextOverlayModel, bool) onShowTextEditor;
  final int? targetLaneIndex;

  const TextOverlayLayer({
    super.key,
    required this.videoCanvasSize,
    required this.onShowTextEditor,
    this.targetLaneIndex,
  });

  @override
  ConsumerState<TextOverlayLayer> createState() => _TextOverlayLayerState();
}

class _TextOverlayLayerState extends ConsumerState<TextOverlayLayer> {
  // Body gesture (one-finger move, pinch scale, two-finger rotate).
  Offset _bodyBasePosition = Offset.zero;
  Offset _bodyBaseFocal = Offset.zero;
  double _bodyBaseScale = 1.0;
  double _bodyBaseRotation = 0.0;

  // Corner rotate/scale handle.
  Offset _handleCenter = Offset.zero;
  Offset _handleStartVector = Offset.zero;
  double _handleBaseScale = 1.0;
  double _handleBaseRotation = 0.0;

  // Edge width handles.
  double _widthBase = 0.0;
  Offset _widthBasePosition = Offset.zero;
  Offset _widthStartLocal = Offset.zero;

  /// Rotations within this of a right angle snap to it — a box that is
  /// meant to be straight ends up exactly straight.
  static const double _kSnapRadians = 3 * math.pi / 180;

  static const double _kHandleHitSize = 44.0;

  VideoEditorNotifier get _notifier => ref.read(videoEditorProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final canvasSize = widget.videoCanvasSize;
    final currentPosMs = (editorState.currentPlaybackPosition * 1000).toInt();

    final children = <Widget>[];
    Widget? selectedFrame;

    for (final overlay in editorState.textOverlays) {
      if (widget.targetLaneIndex != null &&
          overlay.laneIndex != widget.targetLaneIndex) {
        continue;
      }
      final startMs = overlay.startTime.inMilliseconds;
      final endMs = overlay.endTime.inMilliseconds;
      if (currentPosMs < startMs || currentPosMs >= endMs) continue;

      final layout = TextOverlayLayout.measure(overlay, canvasSize);
      final center = textOverlayCenter(overlay, canvasSize, layout.renderScale);
      final isSelected = overlay.id == editorState.selectedTextId;

      children.add(
        _buildBody(
          overlay,
          layout,
          center,
          isSelected,
          editorState.currentPlaybackPosition,
        ),
      );
      if (isSelected) {
        // Built after the loop so it paints above every body, whichever lane
        // the selected text is on.
        selectedFrame = _buildFrame(overlay, layout, center);
      }
    }
    if (selectedFrame != null) children.add(selectedFrame);

    return Stack(clipBehavior: Clip.none, children: children);
  }

  // ---------------------------------------------------------------- body --

  Widget _buildBody(
    TextOverlayModel overlay,
    TextOverlayLayout layout,
    Offset center,
    bool isSelected,
    double positionSeconds,
  ) {
    final box = layout.boxSize;
    final scale = overlay.scale;
    final scaledDiagonal =
        math.sqrt(box.width * box.width + box.height * box.height) * scale;
    // Holds the scaled box at any rotation *and* the unscaled box, which is
    // what the inverse transforms hand the hit test on the way in.
    final side = math.max(scaledDiagonal, math.max(box.width, box.height));

    final content = _textBox(overlay, layout, positionSeconds);

    return Positioned(
      left: center.dx - side / 2,
      top: center.dy - side / 2,
      width: side,
      height: side,
      child: Transform.rotate(
        angle: overlay.rotation,
        child: Transform.scale(
          scale: scale,
          child: Center(
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // First tap selects; a tap on the selected text opens the
                  // editor. Opening on every tap made a text impossible to
                  // move — the sheet is modal and took the canvas away.
                  if (!isSelected) {
                    _notifier.selectTextOverlay(overlay.id);
                  } else {
                    widget.onShowTextEditor(overlay, false);
                  }
                },
                onDoubleTap: () {
                  _notifier.selectTextOverlay(overlay.id);
                  widget.onShowTextEditor(overlay, true);
                },
                onScaleStart: (details) {
                  if (!isSelected) _notifier.selectTextOverlay(overlay.id);
                  _notifier.saveStateForUndo();
                  _bodyBasePosition = overlay.position;
                  _bodyBaseFocal = details.focalPoint;
                  _bodyBaseScale = overlay.scale;
                  _bodyBaseRotation = overlay.rotation;
                },
                onScaleUpdate: (details) {
                  final renderScale = layout.renderScale;
                  final moved = _bodyBasePosition +
                      (details.focalPoint - _bodyBaseFocal) / renderScale;
                  final newScale = (_bodyBaseScale * details.scale)
                      .clamp(kMinTextScale, kMaxTextScale);
                  final newRotation =
                      _snapRotation(_bodyBaseRotation + details.rotation);
                  _notifier.updateTextOverlayLive(
                    overlay.id,
                    (o) => o.copyWith(
                      position: clampTextOverlayPosition(
                        moved,
                        widget.videoCanvasSize,
                        renderScale,
                      ),
                      scale: newScale,
                      rotation: newRotation,
                    ),
                  );
                },
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The box exactly as [TextOverlayLayout] measured it, painted per glyph by
  /// [TextOverlayPainter] at [positionSeconds].
  ///
  /// **It is a painter and not a widget tree on purpose.** It used to be a
  /// `Text` (optionally under a stroking `Text`, optionally in a background
  /// `Container`) wrapped in a `flutter_animate` chain — which can only animate
  /// the whole box, on a fixed half second, from its own controller's clock.
  /// The export animates each character from the catalog on the playhead, so
  /// the two drew different pictures. The painter reads the same glyph boxes,
  /// the same windows and the same curves the export does, which makes them
  /// agree by construction rather than by two implementations happening to land
  /// on the same motion.
  Widget _textBox(
    TextOverlayModel overlay,
    TextOverlayLayout layout,
    double positionSeconds,
  ) {
    return CustomPaint(
      size: layout.boxSize,
      painter: TextOverlayPainter(
        overlay: overlay,
        layout: layout,
        canvasSize: widget.videoCanvasSize,
        positionSeconds: positionSeconds,
      ),
    );
  }

  // --------------------------------------------------------------- frame --

  Widget _buildFrame(
    TextOverlayModel overlay,
    TextOverlayLayout layout,
    Offset center,
  ) {
    final half = Offset(
      layout.boxSize.width * overlay.scale / 2,
      layout.boxSize.height * overlay.scale / 2,
    );
    Offset corner(double sx, double sy) =>
        center + _rotate(Offset(sx * half.dx, sy * half.dy), overlay.rotation);

    final topLeft = corner(-1, -1);
    final topRight = corner(1, -1);
    final bottomLeft = corner(-1, 1);
    final bottomRight = corner(1, 1);
    final leftMid = corner(-1, 0);
    final rightMid = corner(1, 0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SelectionFramePainter(
                corners: [topLeft, topRight, bottomRight, bottomLeft],
              ),
            ),
          ),
        ),
        _edgeHandle(leftMid, overlay, layout, direction: -1),
        _edgeHandle(rightMid, overlay, layout, direction: 1),
        _tapHandle(
          topLeft,
          icon: LucideIcons.x,
          onTap: () => _notifier.deleteTextOverlay(overlay.id),
        ),
        _tapHandle(
          topRight,
          icon: LucideIcons.pencil,
          onTap: () => widget.onShowTextEditor(overlay, false),
        ),
        _tapHandle(
          bottomLeft,
          icon: LucideIcons.copy,
          onTap: () => _notifier.duplicateTextOverlay(overlay.id),
        ),
        _rotateScaleHandle(bottomRight, overlay, center),
      ],
    );
  }

  Widget _tapHandle(
    Offset at, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return _positionedHandle(
      at,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(child: _HandleDisc(icon: icon)),
      ),
    );
  }

  /// Drag to rotate *and* scale about the box centre: the finger's distance
  /// from the centre sets the scale, its angle sets the rotation. One
  /// gesture, no modes, no accumulation.
  Widget _rotateScaleHandle(Offset at, TextOverlayModel overlay, Offset center) {
    return _positionedHandle(
      at,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _notifier.saveStateForUndo();
          _handleCenter = center;
          _handleStartVector = _toLocal(details.globalPosition) - center;
          _handleBaseScale = overlay.scale;
          _handleBaseRotation = overlay.rotation;
        },
        onPanUpdate: (details) {
          final vector = _toLocal(details.globalPosition) - _handleCenter;
          final startDistance = _handleStartVector.distance;
          if (startDistance < 1e-3) return;
          final newScale = (_handleBaseScale * vector.distance / startDistance)
              .clamp(kMinTextScale, kMaxTextScale);
          final newRotation = _snapRotation(
            _handleBaseRotation +
                math.atan2(vector.dy, vector.dx) -
                math.atan2(_handleStartVector.dy, _handleStartVector.dx),
          );
          _notifier.updateTextOverlayLive(
            overlay.id,
            (o) => o.copyWith(scale: newScale, rotation: newRotation),
          );
        },
        child: const Center(child: _HandleDisc(icon: LucideIcons.rotateCw, size: 30)),
      ),
    );
  }

  /// Drag an edge to change the box's width. The opposite edge stays where it
  /// is — the centre moves by half the change along the box's own x-axis — so
  /// the box grows toward the finger, as a resize is expected to.
  Widget _edgeHandle(
    Offset at,
    TextOverlayModel overlay,
    TextOverlayLayout layout, {
    required int direction,
  }) {
    return _positionedHandle(
      at,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _notifier.saveStateForUndo();
          _widthBase = layout.boxSize.width / layout.renderScale;
          _widthBasePosition = overlay.position;
          _widthStartLocal = _toLocal(details.globalPosition);
        },
        onPanUpdate: (details) {
          final renderScale = layout.renderScale;
          final axis = Offset(math.cos(overlay.rotation), math.sin(overlay.rotation));
          final travel = _toLocal(details.globalPosition) - _widthStartLocal;
          // Displacement along the box's x-axis, in render px on the canvas,
          // then into the box's own reference px (undo the pinch scale).
          final alongAxis = (travel.dx * axis.dx + travel.dy * axis.dy) * direction;
          final wanted = _widthBase + alongAxis / (renderScale * overlay.scale);
          final newWidth = wanted.clamp(kMinTextBoxWidth, kMaxTextBoxWidth);
          // Half the *applied* change, so a clamped width leaves the far edge
          // exactly where it was.
          final shift = (newWidth - _widthBase) * overlay.scale / 2 * direction;
          final newPosition = clampTextOverlayPosition(
            _widthBasePosition + axis * shift,
            widget.videoCanvasSize,
            renderScale,
          );
          _notifier.updateTextOverlayLive(
            overlay.id,
            (o) => o.copyWith(boxWidth: newWidth, position: newPosition),
          );
        },
        child: Center(
          child: Transform.rotate(
            angle: overlay.rotation,
            child: const _HandlePill(),
          ),
        ),
      ),
    );
  }

  Widget _positionedHandle(Offset at, {required Widget child}) {
    return Positioned(
      left: at.dx - _kHandleHitSize / 2,
      top: at.dy - _kHandleHitSize / 2,
      width: _kHandleHitSize,
      height: _kHandleHitSize,
      child: child,
    );
  }

  // ------------------------------------------------------------- helpers --

  Offset _toLocal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global) ?? global;
  }

  static Offset _rotate(Offset v, double radians) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  static double _snapRotation(double radians) {
    const quarter = math.pi / 2;
    final nearest = (radians / quarter).round() * quarter;
    return (radians - nearest).abs() <= _kSnapRadians ? nearest : radians;
  }
}

/// A round white handle with a dark glyph, as CapCut draws its corner
/// controls; the drop shadow keeps it legible over white text.
class _HandleDisc extends StatelessWidget {
  const _HandleDisc({required this.icon, this.size = 26});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(icon, size: size * 0.55, color: Colors.black87),
    );
  }
}

class _HandlePill extends StatelessWidget {
  const _HandlePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3.5),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// The selection rectangle through the body's four transformed corners: a
/// thin white line over a faint dark one, so it reads on light and dark
/// footage alike.
class _SelectionFramePainter extends CustomPainter {
  _SelectionFramePainter({required this.corners});

  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _SelectionFramePainter oldDelegate) {
    if (oldDelegate.corners.length != corners.length) return true;
    for (var i = 0; i < corners.length; i++) {
      if (oldDelegate.corners[i] != corners[i]) return true;
    }
    return false;
  }
}
