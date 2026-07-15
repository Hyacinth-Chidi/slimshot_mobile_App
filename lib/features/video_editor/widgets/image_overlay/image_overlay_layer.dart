import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';


import '../../models/image_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';

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
        (editorState.currentPlaybackPosition * 1000).toInt(),
        editorState.imageOverlays,
        editorState.selectedImageId,
        notifier.selectImageOverlay,
        notifier.updateImageOverlay,
      ),
    );
  }

  List<Widget> _buildImageOverlays(
    Size canvasSize,
    int currentPosMs,
    List<ImageOverlayModel> imageOverlays,
    String? selectedImageId,
    void Function(String?) onImageTapped,
    void Function(String, ImageOverlayModel Function(ImageOverlayModel)) onUpdateImageOverlay,
  ) {
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

      final isSelected = overlay.id == selectedImageId;
      final padXY = isSelected ? 64.0 / overlay.scale : 0.0;
      
      final clampedPosition = _clampImagePosition(
        overlay,
        overlay.position,
        canvasSize: canvasSize,
      );

      final timeInOverlaySec = (currentPosMs - startMs) / 1000.0;
      final timeRemainingSec = (endMs - currentPosMs) / 1000.0;

      double animScale = 1.0;
      double animOpacity = overlay.opacity;
      Offset animOffset = Offset.zero;

      if (overlay.animationIn != null && timeInOverlaySec < overlay.animationInDuration) {
        final progress = (timeInOverlaySec / overlay.animationInDuration).clamp(0.0, 1.0);
        if (overlay.animationIn == 'fade_in') animOpacity *= progress;
        else if (overlay.animationIn == 'zoom_in') animScale *= progress;
        else if (overlay.animationIn == 'zoom_out') animScale *= (2.0 - progress);
        else if (overlay.animationIn == 'slide_up') animOffset = Offset(0, 200 * (1 - progress));
        else if (overlay.animationIn == 'slide_down') animOffset = Offset(0, -200 * (1 - progress));
        else if (overlay.animationIn == 'slide_left') animOffset = Offset(200 * (1 - progress), 0);
        else if (overlay.animationIn == 'slide_right') animOffset = Offset(-200 * (1 - progress), 0);
      }

      if (overlay.animationOut != null && timeRemainingSec < overlay.animationOutDuration) {
        final progress = (1.0 - (timeRemainingSec / overlay.animationOutDuration)).clamp(0.0, 1.0);
        if (overlay.animationOut == 'fade_out') animOpacity *= (1 - progress);
        else if (overlay.animationOut == 'zoom_in_out') animScale *= (1 + progress);
        else if (overlay.animationOut == 'zoom_out_out') animScale *= (1 - progress);
        else if (overlay.animationOut == 'slide_up_out') animOffset += Offset(0, -200 * progress);
        else if (overlay.animationOut == 'slide_down_out') animOffset += Offset(0, 200 * progress);
        else if (overlay.animationOut == 'slide_left_out') animOffset += Offset(-200 * progress, 0);
        else if (overlay.animationOut == 'slide_right_out') animOffset += Offset(200 * progress, 0);
      }

      Widget imageWidget = ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 200,
          maxHeight: 200,
        ),
        child: Image.file(
          File(overlay.imagePath),
          fit: BoxFit.contain,
          opacity: AlwaysStoppedAnimation(animOpacity),
        ),
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
                _imageBasePan = overlay.position;
                _imageBaseFocalPoint = details.focalPoint;
                _imageBaseScale = overlay.scale;
                _imageBaseRotation = overlay.rotation;
              },
              onScaleUpdate: (details) {
                if (!isSelected) return;
                final newScale = (_imageBaseScale * details.scale).clamp(0.1, 10.0);
                final newRotation = _imageBaseRotation + details.rotation;
                final movedPosition =
                    _imageBasePan + (details.focalPoint - _imageBaseFocalPoint);
                final updatedOverlay = overlay.copyWith(
                  scale: newScale,
                  rotation: newRotation,
                );
                final clamped = _clampImagePosition(
                  updatedOverlay,
                  movedPosition,
                  canvasSize: canvasSize,
                );

                onUpdateImageOverlay(
                  overlay.id,
                  (_) => updatedOverlay.copyWith(position: clamped),
                );
              },
              child: Transform.scale(
                scale: overlay.scale * animScale,
                child: Transform.rotate(
                  angle: overlay.rotation,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(padXY),
                        child: imageWidget,
                      ),
                      if (isSelected) ...[
                        Positioned(
                          top: padXY,
                          bottom: padXY,
                          left: padXY,
                          right: padXY,
                          child: CustomPaint(
                            painter: _DashedBorderPainter(
                              strokeWidth: 2 / overlay.scale,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        Positioned(top: padXY, left: padXY, child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, -1, onUpdateImageOverlay))))),
                        Positioned(top: padXY, right: padXY, child: FractionalTranslation(translation: const Offset(0.5, -0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, -1, onUpdateImageOverlay))))),
                        Positioned(bottom: padXY, left: padXY, child: FractionalTranslation(translation: const Offset(-0.5, 0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, 1, onUpdateImageOverlay))))),
                        Positioned(bottom: padXY, right: padXY, child: FractionalTranslation(translation: const Offset(0.5, 0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, 1, onUpdateImageOverlay))))),
                        
                        Positioned(
                          top: padXY,
                          left: padXY,
                          child: FractionalTranslation(
                            translation: const Offset(0, -1.0), 
                            child: Transform.translate(
                              offset: Offset(0, -16 / overlay.scale),
                              child: Transform.scale(
                                scale: 1 / overlay.scale,
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
    _resizeBaseScale = overlay.scale;
    _accumulatedResizeDx = 0.0;
    _accumulatedResizeDy = 0.0;
  }

  void _handleResizeUpdate(
    DragUpdateDetails details,
    ImageOverlayModel overlay,
    double dirX,
    double dirY,
    void Function(String, ImageOverlayModel Function(ImageOverlayModel)) onUpdate,
  ) {
    _accumulatedResizeDx += details.delta.dx * dirX;
    _accumulatedResizeDy += details.delta.dy * dirY;
    
    final expansion = (_accumulatedResizeDx + _accumulatedResizeDy) / 2.0;
    final newScale = (_resizeBaseScale + expansion * 0.02).clamp(0.1, 10.0);
    
    onUpdate(overlay.id, (o) => o.copyWith(scale: newScale));
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
