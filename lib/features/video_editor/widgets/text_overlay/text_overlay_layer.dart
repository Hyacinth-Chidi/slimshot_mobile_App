import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';


import '../../models/text_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import 'package:google_fonts/google_fonts.dart';

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
  Offset _textBasePan = Offset.zero;
  Offset _textBaseFocalPoint = Offset.zero;
  double _textBaseScale = 1.0;
  double _textBaseRotation = 0.0;

  // Track absolute gesture drag state for resizing handles to prevent jitter
  double _resizeBaseScale = 1.0;
  double _resizeBaseWidth = 0.0;
  double _accumulatedResizeDx = 0.0;
  double _accumulatedResizeDy = 0.0;

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: _buildTextOverlays(
        widget.videoCanvasSize,
        (editorState.currentPlaybackPosition * 1000).toInt(),
        editorState.textOverlays,
        editorState.selectedTextId,
        notifier.selectTextOverlay,
        notifier.updateTextOverlay,
        widget.onShowTextEditor,
      ),
    );
  }

  List<Widget> _buildTextOverlays(
    Size canvasSize,
    int currentPosMs,
    List<TextOverlayModel> textOverlays,
    String? selectedTextId,
    void Function(String?) onTextTapped,
    void Function(String, TextOverlayModel Function(TextOverlayModel)) onUpdateTextOverlay,
    void Function(TextOverlayModel, bool) onShowTextEditor,
  ) {
    var filteredOverlays = textOverlays;
    if (widget.targetLaneIndex != null) {
      filteredOverlays = filteredOverlays.where((o) => o.laneIndex == widget.targetLaneIndex).toList();
    }

    final List<Widget> children = [];
    for (final overlay in filteredOverlays) {
      final startMs = overlay.startTime.inMilliseconds;
      final endMs = overlay.endTime.inMilliseconds;
      
      // Only show if within time bounds
      if (currentPosMs < startMs || currentPosMs >= endMs) {
        continue;
      }

      final refSize = overlay.referenceCanvasSize;
      final scaleX = refSize != null && refSize.width > 0 ? canvasSize.width / refSize.width : 1.0;
      final scaleY = refSize != null && refSize.height > 0 ? canvasSize.height / refSize.height : 1.0;
      final renderScale = math.min(scaleX, scaleY);

      final isSelected = overlay.id == selectedTextId;
      final padX = isSelected ? 24.0 / overlay.scale : 0.0;
      final padY = isSelected ? 64.0 / overlay.scale : 0.0;
      
      final clampedPosition = _clampTextPosition(
        overlay,
        overlay.position,
        canvasSize: canvasSize,
        renderScale: renderScale,
      );
      final textSize = _measureTextOverlaySize(overlay, canvasSize, renderScale);
      final left = ((canvasSize.width - textSize.width) / 2) + (clampedPosition.dx * renderScale) - padX;
      final top = ((canvasSize.height - textSize.height) / 2) + (clampedPosition.dy * renderScale) - padY;

      final shadows = overlay.shadowColor != Colors.transparent && overlay.shadowBlurRadius > 0
          ? [Shadow(color: overlay.shadowColor, blurRadius: overlay.shadowBlurRadius * renderScale, offset: Offset((overlay.shadowBlurRadius * renderScale) / 2, (overlay.shadowBlurRadius * renderScale) / 2))]
          : <Shadow>[];

      Widget textFill = Text(
        overlay.text,
        style: GoogleFonts.getFont(
          overlay.fontFamily,
          fontSize: 32 * renderScale,
          color: overlay.color,
          height: 1.15,
          shadows: shadows,
        ),
        textAlign: overlay.textAlign == 'left' ? TextAlign.left : overlay.textAlign == 'right' ? TextAlign.right : overlay.textAlign == 'justify' ? TextAlign.justify : TextAlign.center,
      );

      Widget textWidget = textFill;

      // Add stroke if needed
      if (overlay.strokeColor != Colors.transparent && overlay.strokeWidth > 0) {
        Widget textStroke = Text(
          overlay.text,
          style: GoogleFonts.getFont(
            overlay.fontFamily,
            fontSize: 32 * renderScale,
            height: 1.15,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = overlay.strokeWidth * renderScale
              ..color = overlay.strokeColor,
            shadows: shadows,
          ),
          textAlign: overlay.textAlign == 'left' ? TextAlign.left : overlay.textAlign == 'right' ? TextAlign.right : overlay.textAlign == 'justify' ? TextAlign.justify : TextAlign.center,
        );
        textWidget = Stack(
          alignment: Alignment.center,
          children: [textStroke, textFill],
        );
      }

      // Add background if needed
      if (overlay.backgroundColor != Colors.transparent) {
        textWidget = Container(
          decoration: BoxDecoration(
            color: overlay.backgroundColor,
            borderRadius: BorderRadius.circular(overlay.borderRadius * renderScale),
          ),
          padding: EdgeInsets.symmetric(horizontal: overlay.backgroundPadding * renderScale, vertical: (overlay.backgroundPadding / 2) * renderScale),
          child: textWidget,
        );
      }

      // Apply Animations
      if (overlay.inAnimation != 'none') {
        final anim = textWidget.animate();
        switch (overlay.inAnimation) {
          case 'fade_in': textWidget = anim.fadeIn(); break;
          case 'zoom_in': textWidget = anim.scaleXY(begin: 0); break;
          case 'zoom_out': textWidget = anim.scaleXY(begin: 2.0, end: 1.0); break;
          case 'slide_up': textWidget = anim.slideY(begin: 1); break;
          case 'slide_down': textWidget = anim.slideY(begin: -1); break;
          case 'slide_left': textWidget = anim.slideX(begin: 1); break;
          case 'slide_right': textWidget = anim.slideX(begin: -1); break;
          // Legacy compat
          case 'fade': textWidget = anim.fadeIn(); break;
          case 'scale': textWidget = anim.scaleXY(begin: 0); break;
        }
      }

      // We could add outAnimation logic here using .delay() based on (endMs - startMs - 500)
      if (overlay.outAnimation != 'none') {
        final outDelay = Duration(milliseconds: (endMs - startMs) - 500);
        if (outDelay.isNegative) {
           // Skip out animation if clip is too short
        } else {
           var anim = textWidget.animate(delay: outDelay);
           switch (overlay.outAnimation) {
             case 'fade_out': textWidget = anim.fadeOut(); break;
             case 'zoom_in_out': textWidget = anim.scaleXY(end: 0); break;
             case 'zoom_out_out': textWidget = anim.scaleXY(end: 2.0); break;
             case 'slide_up_out': textWidget = anim.slideY(end: -1); break;
             case 'slide_down_out': textWidget = anim.slideY(end: 1); break;
             case 'slide_left_out': textWidget = anim.slideX(end: -1); break;
             case 'slide_right_out': textWidget = anim.slideX(end: 1); break;
             // Legacy compat
             case 'fade': textWidget = anim.fadeOut(); break;
             case 'scale': textWidget = anim.scaleXY(end: 0); break;
           }
        }
      }

      // Key wraps the ENTIRE animated widget so changing animation type
      // forces Flutter to tear down old Animate controller and rebuild fresh
      textWidget = KeyedSubtree(
        key: ValueKey('${overlay.id}_${overlay.inAnimation}_${overlay.outAnimation}'),
        child: textWidget,
      );

      children.add(Positioned(
        left: left,
        top: top,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            onTextTapped(overlay.id);
            onShowTextEditor(overlay, false);
          },
          onDoubleTap: () {
            onTextTapped(overlay.id);
            onShowTextEditor(overlay, true);
          },
          onScaleStart: (details) {
            if (!isSelected) return;
            _textBasePan = overlay.position;
            _textBaseFocalPoint = details.focalPoint;
            _textBaseScale = overlay.scale;
            _textBaseRotation = overlay.rotation;
          },
          onScaleUpdate: (details) {
            if (!isSelected) return;
            final newScale = (_textBaseScale * details.scale).clamp(0.2, 5.0);
            final newRotation = _textBaseRotation + details.rotation;
            final movedPosition =
                _textBasePan + ((details.focalPoint - _textBaseFocalPoint) / renderScale);
            final updatedOverlay = overlay.copyWith(
              scale: newScale,
              rotation: newRotation,
            );
            final clamped = _clampTextPosition(
              updatedOverlay,
              movedPosition,
              canvasSize: canvasSize,
              renderScale: renderScale,
            );

            onUpdateTextOverlay(
              overlay.id,
              (_) => updatedOverlay.copyWith(position: clamped),
            );
          },
          child: Transform.scale(
            scale: overlay.scale,
            child: Transform.rotate(
              angle: overlay.rotation,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padX, vertical: padY),
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: math.max(120.0 * renderScale, ((overlay.boxWidth ?? (overlay.referenceCanvasSize?.width ?? canvasSize.width)) - 32) * renderScale),
                        minWidth: overlay.boxWidth != null ? math.max(120.0 * renderScale, (overlay.boxWidth! - 32) * renderScale) : 0,
                      ),
                      padding: EdgeInsets.all(8 * renderScale),
                      child: textWidget,
                    ),
                  ),
                  if (isSelected) ...[
                    Positioned(
                      top: padY,
                      bottom: padY,
                      left: padX,
                      right: padX,
                      child: CustomPaint(
                        painter: _DashedBorderPainter(
                          strokeWidth: 2 / overlay.scale,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    Positioned(top: padY, left: padX, child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, -1, renderScale, onUpdateTextOverlay))))),
                    Positioned(top: padY, right: padX, child: FractionalTranslation(translation: const Offset(0.5, -0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, -1, renderScale, onUpdateTextOverlay))))),
                    Positioned(bottom: padY, left: padX, child: FractionalTranslation(translation: const Offset(-0.5, 0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, 1, renderScale, onUpdateTextOverlay))))),
                    Positioned(bottom: padY, right: padX, child: FractionalTranslation(translation: const Offset(0.5, 0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildFreeformResizeDot((_) => _handleFreeformResizeStart(overlay, renderScale), (d) => _handleFreeformResizeUpdate(d, overlay, 1, 1, renderScale, onUpdateTextOverlay))))),
                    
                    Positioned(
                      top: padY,
                      bottom: padY,
                      left: padX,
                      child: FractionalTranslation(translation: const Offset(-0.5, 0), child: Transform.scale(scale: 1 / overlay.scale, child: _buildSideDot((_) => _handleFreeformResizeStart(overlay, renderScale), (d) => _handleFreeformResizeUpdate(d, overlay, -1, 0, renderScale, onUpdateTextOverlay))))
                    ),
                    Positioned(
                      top: padY,
                      bottom: padY,
                      right: padX,
                      child: FractionalTranslation(translation: const Offset(0.5, 0), child: Transform.scale(scale: 1 / overlay.scale, child: _buildSideDot((_) => _handleFreeformResizeStart(overlay, renderScale), (d) => _handleFreeformResizeUpdate(d, overlay, 1, 0, renderScale, onUpdateTextOverlay))))
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ));
    }
    return children;
  }

  Size _measureTextOverlaySize(TextOverlayModel overlay, Size canvasSize, double renderScale) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: overlay.text,
        style: GoogleFonts.getFont(
          overlay.fontFamily,
          color: overlay.color,
          fontSize: 32 * renderScale,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: overlay.textAlign == 'left' ? TextAlign.left : overlay.textAlign == 'right' ? TextAlign.right : overlay.textAlign == 'justify' ? TextAlign.justify : TextAlign.center,
    );
    final maxWidth = overlay.referenceCanvasSize?.width ?? (canvasSize.width == 0 ? double.infinity : canvasSize.width);
    final outerMaxWidth = math.max(120.0, (overlay.boxWidth ?? maxWidth) - 32.0) * renderScale;
    final hasBg = overlay.backgroundColor != Colors.transparent;
    final totalPaddingH = (16.0 + (hasBg ? overlay.backgroundPadding * 2 : 0.0)) * renderScale;
    final totalPaddingV = (16.0 + (hasBg ? overlay.backgroundPadding : 0.0)) * renderScale;
    final innerMaxWidth = math.max(0.0, outerMaxWidth - totalPaddingH);

    textPainter.layout(minWidth: 0, maxWidth: innerMaxWidth);
    return Size(textPainter.width + totalPaddingH, textPainter.height + totalPaddingV);
  }



  Offset _clampTextPosition(
    TextOverlayModel overlay,
    Offset position, {
    Size? canvasSize,
    double renderScale = 1.0,
  }) {
    final size = canvasSize ?? widget.videoCanvasSize;
    // Allow the center of the text to reach the edges of the canvas
    final maxDx = size.width / 2;
    final maxDy = size.height / 2;
    
    // Convert current position (which is in reference coords) to render coords for clamping,
    // then back to reference coords.
    final renderPos = position * renderScale;
    final clampedRenderPos = Offset(
      renderPos.dx.clamp(-maxDx, maxDx).toDouble(),
      renderPos.dy.clamp(-maxDy, maxDy).toDouble(),
    );

    return clampedRenderPos / renderScale;
  }

  void _handleResizeStart(TextOverlayModel overlay) {
    _resizeBaseScale = overlay.scale;
    _accumulatedResizeDx = 0.0;
    _accumulatedResizeDy = 0.0;
  }

  void _handleResizeUpdate(
    DragUpdateDetails details,
    TextOverlayModel overlay,
    double dirX,
    double dirY,
    double renderScale,
    void Function(String, TextOverlayModel Function(TextOverlayModel)) onUpdate,
  ) {
    _accumulatedResizeDx += details.delta.dx * dirX;
    _accumulatedResizeDy += details.delta.dy * dirY;
    
    final expansion = (_accumulatedResizeDx + _accumulatedResizeDy) / 2.0;
    // apply renderScale to make resize feeling consistent regardless of canvas size
    final newScale = (_resizeBaseScale + (expansion / renderScale) * 0.02).clamp(0.2, 5.0);
    
    onUpdate(overlay.id, (o) => o.copyWith(scale: newScale));
  }

  Widget _buildCornerDot(GestureDragStartCallback onPanStart, GestureDragUpdateCallback onPanUpdate) {
    return GestureDetector(
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44, // Larger hit area
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

  Widget _buildFreeformResizeDot(GestureDragStartCallback onPanStart, GestureDragUpdateCallback onPanUpdate) {
    return GestureDetector(
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1),
            ],
          ),
          child: Transform.rotate(
            angle: -math.pi / 4,
            child: const Icon(
              LucideIcons.moveVertical,
              size: 12,
              color: Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  void _handleFreeformResizeStart(TextOverlayModel overlay, double renderScale) {
    _resizeBaseWidth = overlay.boxWidth ?? _measureTextOverlaySize(overlay, Size.zero, renderScale).width / renderScale;
    _resizeBaseScale = overlay.scale;
    _accumulatedResizeDx = 0.0;
    _accumulatedResizeDy = 0.0;
  }

  void _handleFreeformResizeUpdate(
    DragUpdateDetails details,
    TextOverlayModel overlay,
    double dirX,
    double dirY,
    double renderScale,
    void Function(String, TextOverlayModel Function(TextOverlayModel)) onUpdate,
  ) {
    _accumulatedResizeDx += details.delta.dx * dirX;
    _accumulatedResizeDy += details.delta.dy * dirY;
    
    // Horizontal changes box width (convert delta to reference coords)
    final expansionX = (_accumulatedResizeDx / renderScale) / overlay.scale * 2.0; 
    final newWidth = math.max(120.0, _resizeBaseWidth + expansionX);
    
    // Vertical changes text scale
    final expansionY = _accumulatedResizeDy / renderScale;
    final newScale = (_resizeBaseScale + expansionY * 0.01).clamp(0.2, 5.0);
    
    onUpdate(overlay.id, (o) => o.copyWith(
      boxWidth: newWidth,
      scale: newScale,
    ));
  }

  Widget _buildSideDot(GestureDragStartCallback onDragStart, GestureDragUpdateCallback onDragUpdate) {
    return GestureDetector(
      onHorizontalDragStart: onDragStart,
      onHorizontalDragUpdate: onDragUpdate,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 64, // Larger hit area width to easily grab
        height: 84, // Larger hit area height
        alignment: Alignment.center,
        child: Container(
          width: 8,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1),
            ],
          ),
        ),
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
