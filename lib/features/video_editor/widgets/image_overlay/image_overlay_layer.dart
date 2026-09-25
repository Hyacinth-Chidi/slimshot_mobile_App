
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/lucide_icons.dart';


import '../../logic/animation/overlay_keyframes.dart';
import '../../models/image_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import '../overlay_content_box.dart';

class ImageOverlayLayer extends ConsumerStatefulWidget {
  final Size videoCanvasSize;
  final int? targetLaneIndex;

  const ImageOverlayLayer({
    super.key,
    required this.videoCanvasSize,
    this.targetLaneIndex,
  });

  @override
  ConsumerState<ImageOverlayLayer> createState() => _ImageOverlayLayerState();
}

class _ImageOverlayLayerState extends ConsumerState<ImageOverlayLayer> {
  /// The overlay whose body is being dragged, pinched or turned right now.
  ///
  /// Its frame, handles and action bar are hidden for the length of the
  /// gesture. They are Flutter widgets and the picture is drawn by GL — this
  /// frame's position reaches the engine over the channel, is drawn on the GL
  /// thread and composited a frame or two later — so on a fast drag the dashed
  /// box ran visibly ahead of the picture it surrounds (device-reported). Two
  /// drawings that cannot agree should not both be on screen; the frame comes
  /// back on release, where the picture rests.
  String? _movingId;

  Offset _imageBasePan = Offset.zero;
  Offset _imageBaseFocalPoint = Offset.zero;
  double _imageBaseScale = 1.0;
  double _imageBaseRotation = 0.0;

  double _resizeBaseScale = 1.0;
  double _accumulatedResizeDx = 0.0;
  double _accumulatedResizeDy = 0.0;

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: _buildImageOverlays(
        widget.videoCanvasSize,
        editorState.currentPlaybackPosition,
        editorState.imageOverlays,
        editorState.selectedImageId,
        notifier.selectImageOverlay,
      ),
    );
  }

  List<Widget> _buildImageOverlays(
    Size canvasSize,
    double positionSeconds,
    List<ImageOverlayModel> imageOverlays,
    String? selectedImageId,
    void Function(String?) onImageTapped,
  ) {
    final currentPosMs = (positionSeconds * 1000).toInt();
    var filteredOverlays = imageOverlays;
    if (widget.targetLaneIndex != null) {
      filteredOverlays = filteredOverlays.where((o) => o.laneIndex == widget.targetLaneIndex).toList();
    }

    final List<Widget> children = [];
    for (final overlay in filteredOverlays) {
      final startMs = overlay.startTime.inMilliseconds;
      final endMs = overlay.endTime.inMilliseconds;
      
      if (currentPosMs < startMs || currentPosMs >= endMs) {
        continue;
      }

      // Where its keyframes put it at the playhead — the overlay itself when
      // it has none. The box, frame and handles all follow the picture, which
      // the engine draws from the same keyframes.
      final shown = overlay.shownAt(positionSeconds);
      final isSelected = overlay.id == selectedImageId;
      final padXY = isSelected ? 64.0 / shown.scale : 0.0;

      final clampedPosition = _clampImagePosition(
        shown,
        shown.position,
        canvasSize: canvasSize,
      );

      final timeInOverlaySec = (currentPosMs - startMs) / 1000.0;
      final timeRemainingSec = (endMs - currentPosMs) / 1000.0;

      // Scale and offset still matter here: they place the selection frame
      // and its handles, which have to follow an overlay that is animating.
      // Opacity does not — GL fades the picture, and fading the handles with
      // it would make them vanish exactly when the user needs to grab them.
      double animScale = 1.0;
      Offset animOffset = Offset.zero;

      if (overlay.animationIn != null && timeInOverlaySec < overlay.animationInDuration) {
        final progress = (timeInOverlaySec / overlay.animationInDuration).clamp(0.0, 1.0);
        if (overlay.animationIn == 'zoom_in') {
          animScale *= progress;
        } else if (overlay.animationIn == 'zoom_out') {
          animScale *= (2.0 - progress);
        } else if (overlay.animationIn == 'slide_up') {
          animOffset = Offset(0, 200 * (1 - progress));
        } else if (overlay.animationIn == 'slide_down') {
          animOffset = Offset(0, -200 * (1 - progress));
        } else if (overlay.animationIn == 'slide_left') {
          animOffset = Offset(200 * (1 - progress), 0);
        } else if (overlay.animationIn == 'slide_right') {
          animOffset = Offset(-200 * (1 - progress), 0);
        }
      }

      if (overlay.animationOut != null && timeRemainingSec < overlay.animationOutDuration) {
        final progress = (1.0 - (timeRemainingSec / overlay.animationOutDuration)).clamp(0.0, 1.0);
        if (overlay.animationOut == 'zoom_in_out') {
          animScale *= (1 + progress);
        } else if (overlay.animationOut == 'zoom_out_out') {
          animScale *= (1 - progress);
        } else if (overlay.animationOut == 'slide_up_out') {
          animOffset += Offset(0, -200 * progress);
        } else if (overlay.animationOut == 'slide_down_out') {
          animOffset += Offset(0, 200 * progress);
        } else if (overlay.animationOut == 'slide_left_out') {
          animOffset += Offset(-200 * progress, 0);
        } else if (overlay.animationOut == 'slide_right_out') {
          animOffset += Offset(200 * progress, 0);
        }
      }

      // **The picture is drawn by GL, not here.** The engine composites this
      // overlay with the same renderer the export uses, so drawing it again
      // in Flutter would show every overlay twice — and would put back the
      // approximations that came with a widget: a hard-edged mask where the
      // shader feathers, and no way to key a colour at all.
      //
      // What stays is the box: the gesture target, and the frame and handles
      // that hang off it. It is laid out from the same geometry the composer
      // sends the engine, so the handles and the picture agree.
      // The picture's own shape, not the 200px square it is fitted into, or
      // the dotted frame stands off a wide photo with empty bands.
      Widget imageWidget = OverlayContentBox(
        path: overlay.imagePath,
        isVideo: false,
        box: 200,
      );

      final centerX = (canvasSize.width / 2) + clampedPosition.dx + animOffset.dx;
      final centerY = (canvasSize.height / 2) + clampedPosition.dy + animOffset.dy;

      children.add(Positioned(
        left: centerX,
        top: centerY,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => onImageTapped(overlay.id),
              onScaleStart: (details) {
                if (!isSelected) return;
                // Pauses and takes the one undo snapshot the whole gesture
                // shares; the frames in between write with none.
                ref.read(videoEditorProvider.notifier).beginOverlayEdit();
                // Anchored on where the overlay is drawn — the value the write
                // will land on — never on its stored base, which a keyframed
                // overlay is not at.
                final state = ref.read(videoEditorProvider);
                _imageBasePan = Offset(
                  state.overlayEditValue(OverlayProperty.x),
                  state.overlayEditValue(OverlayProperty.y),
                );
                _imageBaseFocalPoint = details.focalPoint;
                _imageBaseScale = state.overlayEditValue(OverlayProperty.scale);
                _imageBaseRotation = state.overlayEditValue(OverlayProperty.rotation);
                setState(() => _movingId = overlay.id);
              },
              onScaleEnd: (_) {
                if (_movingId != null) setState(() => _movingId = null);
              },
              onScaleUpdate: (details) {
                if (!isSelected) return;
                final movedPosition =
                    _imageBasePan + (details.focalPoint - _imageBaseFocalPoint);
                // Scale and rotation only when a second finger gives them; a
                // one-finger move has nothing to say about either.
                final pinching = details.pointerCount > 1;
                // Through the edit rule: a base value on an overlay with no
                // diamonds, the diamond under the playhead on one with them.
                ref.read(videoEditorProvider.notifier).setOverlayMotionLive(
                  id: overlay.id,
                  position: _clampImagePosition(
                    overlay,
                    movedPosition,
                    canvasSize: canvasSize,
                  ),
                  scale: pinching
                      ? (_imageBaseScale * details.scale).clamp(0.1, 10.0).toDouble()
                      : null,
                  rotation: pinching ? _imageBaseRotation + details.rotation : null,
                );
              },
              child: Transform.scale(
                scale: shown.scale * animScale,
                child: Transform.rotate(
                  angle: shown.rotation,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(padXY),
                        child: imageWidget,
                      ),
                      if (isSelected && _movingId != overlay.id) ...[
                        Positioned(
                          top: padXY,
                          bottom: padXY,
                          left: padXY,
                          right: padXY,
                          child: CustomPaint(
                            painter: _DashedBorderPainter(
                              strokeWidth: 2 / shown.scale,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        Positioned(top: padXY, left: padXY, child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: Transform.scale(scale: 1 / shown.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, -1))))),
                        Positioned(top: padXY, right: padXY, child: FractionalTranslation(translation: const Offset(0.5, -0.5), child: Transform.scale(scale: 1 / shown.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, -1))))),
                        Positioned(bottom: padXY, left: padXY, child: FractionalTranslation(translation: const Offset(-0.5, 0.5), child: Transform.scale(scale: 1 / shown.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, 1))))),
                        Positioned(bottom: padXY, right: padXY, child: FractionalTranslation(translation: const Offset(0.5, 0.5), child: Transform.scale(scale: 1 / shown.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, 1))))),
                        
                        Positioned(
                          top: padXY,
                          left: padXY,
                          child: FractionalTranslation(
                            translation: const Offset(0, -1.0), 
                            child: Transform.translate(
                              offset: Offset(0, -16 / shown.scale),
                              child: Transform.scale(
                                scale: 1 / shown.scale,
                                alignment: Alignment.bottomLeft,
                                child: _buildImageFloatingActionBar(overlay),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ),
            ),
          ),
        ),
      ));
    }
    return children;
  }

  Offset _clampImagePosition(
    ImageOverlayModel overlay,
    Offset position, {
    Size? canvasSize,
  }) {
    final size = canvasSize ?? widget.videoCanvasSize;

    final maxDx = size.width / 2;
    final maxDy = size.height / 2;

    return Offset(
      position.dx.clamp(-maxDx, maxDx).toDouble(),
      position.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _handleResizeStart(ImageOverlayModel overlay) {
    ref.read(videoEditorProvider.notifier).beginOverlayEdit();
    // From the drawn size, as the body's own gesture anchors.
    _resizeBaseScale =
        ref.read(videoEditorProvider).overlayEditValue(OverlayProperty.scale);
    _accumulatedResizeDx = 0.0;
    _accumulatedResizeDy = 0.0;
  }

  void _handleResizeUpdate(
    DragUpdateDetails details,
    ImageOverlayModel overlay,
    double dirX,
    double dirY,
  ) {
    _accumulatedResizeDx += details.delta.dx * dirX;
    _accumulatedResizeDy += details.delta.dy * dirY;
    
    final expansion = (_accumulatedResizeDx + _accumulatedResizeDy) / 2.0;
    final newScale = (_resizeBaseScale + expansion * 0.02).clamp(0.1, 10.0);
    
    ref.read(videoEditorProvider.notifier).setOverlayMotionLive(
      id: overlay.id,
      scale: newScale.toDouble(),
    );
  }

  Widget _buildCornerDot(GestureDragStartCallback onPanStart, GestureDragUpdateCallback onPanUpdate) {
    return GestureDetector(
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            color: Color(0xFFE0E0E0),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageFloatingActionBar(ImageOverlayModel overlay) {
    final notifier = ref.read(videoEditorProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => notifier.deleteImageOverlay(overlay.id),
            child: const Icon(LucideIcons.trash2, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => notifier.duplicateImageOverlay(overlay.id),
            child: const Icon(LucideIcons.copy, color: Colors.black87, size: 20),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;

  _DashedBorderPainter({this.strokeWidth = 2.0, this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    
    _drawDashedLine(canvas, const Offset(0, 0), Offset(size.width, 0), paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, Offset(size.width, 0), Offset(size.width, size.height), paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, Offset(size.width, size.height), Offset(0, size.height), paint, dashWidth, dashSpace);
    _drawDashedLine(canvas, Offset(0, size.height), const Offset(0, 0), paint, dashWidth, dashSpace);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace) {
    var distance = (p2 - p1).distance;
    var direction = (p2 - p1) / distance;
    var start = p1;
    var currentDistance = 0.0;

    while (currentDistance < distance) {
      var drawLength = dashWidth;
      if (currentDistance + drawLength > distance) {
        drawLength = distance - currentDistance;
      }
      canvas.drawLine(start, start + direction * drawLength, paint);
      currentDistance += drawLength + dashSpace;
      start = p1 + direction * currentDistance;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth || oldDelegate.color != color;
  }
}
