import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/animation/clip_keyframes.dart';
import '../../logic/canvas_geometry.dart';
import '../../logic/timeline/timeline_geometry.dart';
import '../../models/media_asset.dart';
import '../../models/video_editor_state.dart';
import '../../services/native_timeline_preview_service.dart';
import '../../models/text_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import '../image_overlay/image_overlay_layer.dart';
import '../video_overlay/video_overlay_layer.dart';
import '../text_overlay/text_overlay_layer.dart';

enum CropDragMode { none, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight, center }

/// What the crop handles edit: the project's rect, a clip's own, or nothing.
enum _CropTarget { none, project, clip }

class VideoPreviewCanvas extends ConsumerStatefulWidget {
  /// The native engine's texture. The canvas draws this and nothing else —
  /// crop, zoom, grade and letterboxing are already in those pixels, which is
  /// why this widget must never re-apply them (it once wrapped the texture in
  /// a `Transform.scale` + `ColorFiltered` and double-graded every frame).
  final Widget videoSurface;

  final VoidCallback? onTogglePreview;
  final VoidCallback? onDeadZoneTapped;
  final ValueChanged<Size>? onCanvasSizeChanged;
  final void Function(TextOverlayModel, bool)? onShowTextEditor;

  const VideoPreviewCanvas({
    super.key,
    required this.videoSurface,
    this.onTogglePreview,
    this.onDeadZoneTapped,
    this.onCanvasSizeChanged,
    this.onShowTextEditor,
  });

  @override
  ConsumerState<VideoPreviewCanvas> createState() => _VideoPreviewCanvasState();
}

class _VideoPreviewCanvasState extends ConsumerState<VideoPreviewCanvas> {
  CropDragMode _cropDragMode = CropDragMode.none;
  double _baseVideoScale = 1.0;

  /// Talks to the native engine for the live clip-transform gesture. The
  /// method channel is stateless and the event stream is shared, so a second
  /// service instance here costs nothing.
  final _nativePreview = NativeTimelinePreviewService();

  // Pinch/drag on the selected clip. Anchored, not accumulated: the values at
  // finger-down plus the gesture's own deltas, so a clamped frame never leaves
  // the picture offset from the finger.
  double _clipGestureStartScale = 1.0;
  double _clipGestureStartOffsetX = 0.0;
  double _clipGestureStartOffsetY = 0.0;
  double _clipGesturePanX = 0.0;
  double _clipGesturePanY = 0.0;
  String? _clipGestureSegmentId;

  void _beginClipGesture(VideoEditorState state) {
    final segment = state.selectedSegment;
    if (segment == null) return;
    _clipGestureSegmentId = segment.id;
    // **Anchored to the value at the playhead, not to the base.** A drag is
    // `anchorValue + displacement`, and on a keyframed clip the value on screen
    // is the resolved one — anchoring to the base would make the picture jump
    // to a different scale the instant the finger moved.
    // `clipEditValue` is "what the write will target": the value at the
    // playhead on a keyframed clip, the base when the playhead is off the
    // clip — where the write goes to the base too, so anchor and write agree.
    _clipGestureStartScale =
        state.clipEditValue(segment, ClipProperty.canvasScale);
    _clipGestureStartOffsetX =
        state.clipEditValue(segment, ClipProperty.canvasOffsetX);
    _clipGestureStartOffsetY =
        state.clipEditValue(segment, ClipProperty.canvasOffsetY);
    _clipGesturePanX = 0.0;
    _clipGesturePanY = 0.0;
    ref.read(videoEditorProvider.notifier).beginClipCanvasTransform();
  }

  void _updateClipGesture(ScaleUpdateDetails details) {
    final segmentId = _clipGestureSegmentId;
    final canvas = _videoCanvasSize;
    if (segmentId == null || canvas == null || canvas.width <= 0) return;

    // Pan travels in canvas fractions so it means the same thing at any
    // preview size — and in the exported file.
    _clipGesturePanX += details.focalPointDelta.dx / canvas.width;
    _clipGesturePanY += details.focalPointDelta.dy / canvas.height;

    final scale = (_clipGestureStartScale * details.scale)
        .clamp(kMinClipCanvasScale, kMaxClipCanvasScale)
        .toDouble();
    final offsetX =
        (_clipGestureStartOffsetX + _clipGesturePanX).clamp(-1.5, 1.5).toDouble();
    final offsetY =
        (_clipGestureStartOffsetY + _clipGesturePanY).clamp(-1.5, 1.5).toDouble();

    // State for persistence and undo; the override channel for the live
    // picture. The full timeline push is gated until the gesture ends.
    ref.read(videoEditorProvider.notifier).updateClipCanvasTransform(
          scale: scale,
          offsetX: offsetX,
          offsetY: offsetY,
        );
    _nativePreview.setClipTransform(
      clipId: segmentId,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
    );
  }

  void _endClipGesture() {
    _clipGestureSegmentId = null;
    ref.read(videoEditorProvider.notifier).endClipCanvasTransform();
  }
  Offset _baseVideoPan = Offset.zero;
  Size? _videoCanvasSize;

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final previewSurface = widget.videoSurface;

    final videoDuration = videoTimelineDuration(editorState.segments);
    final totalEditedDuration = ref.watch(totalEditedDurationProvider);
    final isAudioTail =
        totalEditedDuration > videoDuration + 0.05 &&
        editorState.currentPlaybackPosition >= videoDuration - 0.02;

    return GestureDetector(
      onTap: widget.onDeadZoneTapped,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: AspectRatio(
              // The project canvas decides the frame, and **this box is the
              // texture's shape, nothing else**. Under a custom crop the box
              // used to be reshaped by the rect while the texture stayed 9:16
              // — which un-stretched the picture on screen and left the export,
              // which has no box, stretched. The reshaping now lives in
              // `projectAspectRatio`, where the texture and the file read it.
              aspectRatio: editorState.projectAspectRatio,
              child: LayoutBuilder(
                builder: (context, canvasConstraints) {
                  final newSize = Size(canvasConstraints.maxWidth, canvasConstraints.maxHeight);
                  if (_videoCanvasSize != newSize) {
                    _videoCanvasSize = newSize;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        widget.onCanvasSizeChanged?.call(newSize);
                      }
                    });
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTogglePreview,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          // Square corners: the canvas is the output frame,
                          // and the exported file has no rounded corners.
                          child: ClipRect(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Background Layer. The audio/overlay tail
                                // past the last clip shows this too — the
                                // project background, not forced black — so
                                // the tail looks the same here as in the
                                // exported file.
                                Positioned.fill(
                                  child: Container(
                                    color: editorState.backgroundType == EditorBackgroundType.color
                                        ? editorState.backgroundColor
                                        : Colors.black,
                                  ),
                                ),

                                // The picture. The native renderer has already
                                // applied crop, zoom, pan, the letterbox and
                                // both colour grades, so this draws the
                                // texture and nothing else — re-applying any
                                // of them here doubled them (the grade twice
                                // over, a zoom that magnified the bars).
                                //
                                // With a clip selected, pinch scales it and a
                                // one-finger drag moves it on the canvas; the
                                // scale recogniser handles both. With nothing
                                // selected there are no recognisers at all,
                                // so taps and the other tools are unaffected.
                                if (!isAudioTail)
                                  Builder(
                                    builder: (context) {
                                      final canTransform =
                                          editorState.selectedSegmentId != null;
                                      return SizedBox.expand(
                                        child: GestureDetector(
                                          onScaleStart: canTransform
                                              ? (_) =>
                                                  _beginClipGesture(editorState)
                                              : null,
                                          onScaleUpdate: canTransform
                                              ? _updateClipGesture
                                              : null,
                                          onScaleEnd: canTransform
                                              ? (_) => _endClipGesture()
                                              : null,
                                          onDoubleTap: canTransform
                                              ? () => ref
                                                  .read(videoEditorProvider
                                                      .notifier)
                                                  .resetClipCanvasTransform()
                                              : null,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              previewSurface,
                                              // The canvas edge lights up while
                                              // a clip is selected, so it reads
                                              // as "this clip is being placed"
                                              // — yellow, because purple is the
                                              // timeline's selection colour.
                                              if (canTransform)
                                                IgnorePointer(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color:
                                                            AppColors.warning,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                ...List.generate(
                                  _getMaxLane(editorState) + 1,
                                  (lane) => Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: false,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          ImageOverlayLayer(
                                            videoCanvasSize: _videoCanvasSize!,
                                            targetLaneIndex: lane,
                                          ),
                                          VideoOverlayLayer(
                                            videoCanvasSize: _videoCanvasSize!,
                                            targetLaneIndex: lane,
                                          ),
                                          TextOverlayLayer(
                                            videoCanvasSize: _videoCanvasSize!,
                                            onShowTextEditor: widget.onShowTextEditor ?? (_, __) {},
                                            targetLaneIndex: lane,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                // Zoom Overlay (only show when zoom tool is active)
                                if (editorState.activeToolId == 'zoom')
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: AppColors.primaryStart, width: 3),
                                      ),
                                      child: GestureDetector(
                                        onScaleStart: (details) {
                                          _baseVideoScale =
                                              editorState.previewVideoScale ??
                                                  editorState.videoScale;
                                          _baseVideoPan =
                                              editorState.previewVideoPan ??
                                                  editorState.videoPan;
                                        },
                                        onScaleUpdate: (details) {
                                          ref.read(videoEditorProvider.notifier).setPreviewVideoTransform(
                                            previewVideoScale: (_baseVideoScale * details.scale)
                                                .clamp(1.0, 5.0),
                                            previewVideoPan:
                                                _baseVideoPan + details.focalPointDelta,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Crop overlay: the project crop tool, or a clip's own.
                        // **One editor, two targets.** The clip-crop tool reuses
                        // the project crop's handles and painter rather than
                        // growing a second editor that would drift from the
                        // first — only which rect is read and written differs,
                        // and `_cropTarget` decides that in one place.
                        if (_cropTarget(editorState) != _CropTarget.none)
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GestureDetector(
                                  onPanStart: (details) => _handleCropPanStart(details, constraints),
                                  onPanUpdate: (details) => _handleCropPanUpdate(details, constraints),
                                  onPanEnd: _handleCropPanEnd,
                                  child: CustomPaint(
                                    painter: _CropBoundsPainter(
                                      cropRect: _editingCropRect(editorState),
                                      frame: _cropFrame(
                                          editorState, constraints.biggest),
                                      // A clip crop is always freehand — there
                                      // is no ratio to lock it to.
                                      isCustom: _cropIsFreehand(editorState),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleCropPanStart(DragStartDetails details, BoxConstraints constraints) {
    final editorState = ref.read(videoEditorProvider);
    if (!_cropIsFreehand(editorState)) return;

    final frame = _cropFrame(editorState, constraints.biggest);

    final dx = details.localPosition.dx;
    final dy = details.localPosition.dy;

    final editing = _editingCropRect(editorState);
    final rect = Rect.fromLTRB(
      frame.left + editing.left * frame.width,
      frame.top + editing.top * frame.height,
      frame.left + editing.right * frame.width,
      frame.top + editing.bottom * frame.height,
    );

    const hit = 40.0;

    if ((dx - rect.left).abs() < hit && (dy - rect.top).abs() < hit) {
      _cropDragMode = CropDragMode.topLeft;
    } else if ((dx - rect.right).abs() < hit && (dy - rect.top).abs() < hit) {
      _cropDragMode = CropDragMode.topRight;
    } else if ((dx - rect.left).abs() < hit && (dy - rect.bottom).abs() < hit) {
      _cropDragMode = CropDragMode.bottomLeft;
    } else if ((dx - rect.right).abs() < hit && (dy - rect.bottom).abs() < hit) {
      _cropDragMode = CropDragMode.bottomRight;
    } else if ((dx - rect.left).abs() < hit && dy >= rect.top && dy <= rect.bottom) {
      _cropDragMode = CropDragMode.left;
    } else if ((dx - rect.right).abs() < hit && dy >= rect.top && dy <= rect.bottom) {
      _cropDragMode = CropDragMode.right;
    } else if ((dy - rect.top).abs() < hit && dx >= rect.left && dx <= rect.right) {
      _cropDragMode = CropDragMode.top;
    } else if ((dy - rect.bottom).abs() < hit && dx >= rect.left && dx <= rect.right) {
      _cropDragMode = CropDragMode.bottom;
    } else if (rect.contains(Offset(dx, dy))) {
      _cropDragMode = CropDragMode.center;
    } else {
      _cropDragMode = CropDragMode.none;
    }

    // **One undo step per drag**, the rule every gesture here follows. Taken
    // at the start and never per frame — the frames below write live.
    if (_cropDragMode != CropDragMode.none) {
      ref.read(videoEditorProvider.notifier).saveStateForUndo();
    }
  }

  void _handleCropPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final editorState = ref.read(videoEditorProvider);
    if (_cropDragMode == CropDragMode.none) return;

    // Deltas are fractions of the *picture*, not of the box — see [_cropFrame].
    final frame = _cropFrame(editorState, constraints.biggest);
    final dx = details.delta.dx / frame.width;
    final dy = details.delta.dy / frame.height;

    final editing = _editingCropRect(editorState);
    double left = editing.left;
    double top = editing.top;
    double right = editing.right;
    double bottom = editing.bottom;

    if (_cropDragMode == CropDragMode.center) {
      if (left + dx >= 0 && right + dx <= 1.0) { left += dx; right += dx; }
      if (top + dy >= 0 && bottom + dy <= 1.0) { top += dy; bottom += dy; }
    } else {
      if (_cropDragMode == CropDragMode.left || _cropDragMode == CropDragMode.topLeft || _cropDragMode == CropDragMode.bottomLeft) {
        left = (left + dx).clamp(0.0, right - 0.1);
      }
      if (_cropDragMode == CropDragMode.right || _cropDragMode == CropDragMode.topRight || _cropDragMode == CropDragMode.bottomRight) {
        right = (right + dx).clamp(left + 0.1, 1.0);
      }
      if (_cropDragMode == CropDragMode.top || _cropDragMode == CropDragMode.topLeft || _cropDragMode == CropDragMode.topRight) {
        top = (top + dy).clamp(0.0, bottom - 0.1);
      }
      if (_cropDragMode == CropDragMode.bottom || _cropDragMode == CropDragMode.bottomLeft || _cropDragMode == CropDragMode.bottomRight) {
        bottom = (bottom + dy).clamp(top + 0.1, 1.0);
      }
    }

    _writeCropRect(editorState, Rect.fromLTRB(left, top, right, bottom));
  }

  void _handleCropPanEnd(DragEndDetails details) {
    _cropDragMode = CropDragMode.none;
  }

  /// Where the picture the handles edit sits inside the canvas box, in pixels.
  ///
  /// The project's crop is a fraction of every clip's frame and its handles
  /// cover the whole box. A clip's crop is a fraction of **that clip's**
  /// picture, which sits contain-fitted inside the canvas with bars around it
  /// — so its handles cover the fitted picture. Drawn over the whole box they
  /// agreed with the source only for a clip that happened to fill the canvas;
  /// on a letterboxed clip a rectangle drawn over the bars cropped a region the
  /// user never pointed at.
  ///
  /// The composer shows the edited clip *plain* — the project's crop and
  /// nothing else — so the fit is the only transform between this rect and
  /// the source, and [fittedFrameRect] is the same contain rule the engine
  /// applies. An unprobed asset falls back to the whole box, as the engine
  /// does.
  Rect _cropFrame(VideoEditorState state, Size box) {
    final whole = Offset.zero & box;
    if (_cropTarget(state) != _CropTarget.clip) return whole;
    final segment = state.selectedSegment;
    final asset = segment == null ? null : state.assetFor(segment);
    if (asset == null) return whole;
    return fittedFrameRect(
      contentAspect: contentAspectRatio(
        state.projectCropRect,
        Size(asset.width, asset.height),
      ),
      canvasSize: box,
    );
  }

  /// Which rect the crop editor is pointed at, from the open tool.
  _CropTarget _cropTarget(VideoEditorState state) {
    switch (state.activeToolId) {
      case 'crop':
        return _CropTarget.project;
      case 'clip_crop':
        return state.selectedSegment == null
            ? _CropTarget.none
            : _CropTarget.clip;
      default:
        return _CropTarget.none;
    }
  }

  /// The rect under the handles: the project's, or the selected clip's own.
  Rect _editingCropRect(VideoEditorState state) {
    switch (_cropTarget(state)) {
      case _CropTarget.clip:
        return state.selectedSegment!.cropRect;
      case _CropTarget.project:
      case _CropTarget.none:
        return state.customCropRect;
    }
  }

  /// Whether the handles can be dragged freely. The project crop only under
  /// its Custom ratio; a clip crop always — it has no ratio to lock to.
  bool _cropIsFreehand(VideoEditorState state) {
    switch (_cropTarget(state)) {
      case _CropTarget.clip:
        return true;
      case _CropTarget.project:
        return state.selectedRatio == EditorCropRatio.custom;
      case _CropTarget.none:
        return false;
    }
  }

  void _writeCropRect(VideoEditorState state, Rect rect) {
    final notifier = ref.read(videoEditorProvider.notifier);
    switch (_cropTarget(state)) {
      case _CropTarget.clip:
        notifier.setClipCropRect(rect);
      case _CropTarget.project:
        notifier.setCustomCropRect(rect);
      case _CropTarget.none:
        break;
    }
  }

  int _getMaxLane(dynamic editorState) {
    int maxLane = 0;
    for (final o in editorState.textOverlays) {
      if (o.laneIndex > maxLane) maxLane = o.laneIndex;
    }
    for (final o in editorState.imageOverlays) {
      if (o.laneIndex > maxLane) maxLane = o.laneIndex;
    }
    for (final o in editorState.videoOverlays) {
      if (o.laneIndex > maxLane) maxLane = o.laneIndex;
    }
    return maxLane;
  }
}

class _CropBoundsPainter extends CustomPainter {
  final Rect cropRect;

  /// The picture the rect is a fraction of, in the same pixels as the paint
  /// size — the whole box for the project's crop, the fitted picture for a
  /// clip's. See `_cropFrame`.
  final Rect frame;
  final bool isCustom;

  _CropBoundsPainter({
    required this.cropRect,
    required this.frame,
    required this.isCustom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    Rect drawRect;
    if (isCustom) {
      drawRect = Rect.fromLTRB(
        frame.left + cropRect.left * frame.width,
        frame.top + cropRect.top * frame.height,
        frame.left + cropRect.right * frame.width,
        frame.top + cropRect.bottom * frame.height,
      );

      // Dim everything outside the crop — bars included, so the kept region
      // reads as the one bright thing on the canvas.
      final overlayPath = Path()
        ..addRect(Rect.fromLTWH(0, 0, width, height))
        ..addRect(drawRect)
        ..fillType = PathFillType.evenOdd;

      canvas.drawPath(overlayPath, Paint()..color = Colors.black.withOpacity(0.6));
    } else {
      drawRect = frame;
    }
    
    drawRect = drawRect.deflate(1.5);

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    const double len = 20;

    // Top-left
    canvas.drawLine(drawRect.topLeft, drawRect.topLeft + const Offset(len, 0), paint);
    canvas.drawLine(drawRect.topLeft, drawRect.topLeft + const Offset(0, len), paint);

    // Top-right
    canvas.drawLine(drawRect.topRight, drawRect.topRight + const Offset(-len, 0), paint);
    canvas.drawLine(drawRect.topRight, drawRect.topRight + const Offset(0, len), paint);

    // Bottom-left
    canvas.drawLine(drawRect.bottomLeft, drawRect.bottomLeft + const Offset(len, 0), paint);
    canvas.drawLine(drawRect.bottomLeft, drawRect.bottomLeft + const Offset(0, -len), paint);

    // Bottom-right
    canvas.drawLine(drawRect.bottomRight, drawRect.bottomRight + const Offset(-len, 0), paint);
    canvas.drawLine(drawRect.bottomRight, drawRect.bottomRight + const Offset(0, -len), paint);

    // Draw rule of thirds grid (faint)
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final dw = drawRect.width;
    final dh = drawRect.height;

    canvas.drawLine(Offset(drawRect.left + dw / 3, drawRect.top), Offset(drawRect.left + dw / 3, drawRect.bottom), gridPaint);
    canvas.drawLine(Offset(drawRect.left + 2 * dw / 3, drawRect.top), Offset(drawRect.left + 2 * dw / 3, drawRect.bottom), gridPaint);
    canvas.drawLine(Offset(drawRect.left, drawRect.top + dh / 3), Offset(drawRect.right, drawRect.top + dh / 3), gridPaint);
    canvas.drawLine(Offset(drawRect.left, drawRect.top + 2 * dh / 3), Offset(drawRect.right, drawRect.top + 2 * dh / 3), gridPaint);

    // Draw outer boundary
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(drawRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CropBoundsPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.frame != frame ||
        oldDelegate.isCustom != isCustom;
  }
}
