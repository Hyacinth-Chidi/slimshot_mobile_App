import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/video_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';

class VideoOverlayLayer extends ConsumerStatefulWidget {
  final Player? mainPlayer;
  final Size videoCanvasSize;
  final int? targetLaneIndex;

  const VideoOverlayLayer({
    super.key,
    required this.mainPlayer,
    required this.videoCanvasSize,
    this.targetLaneIndex,
  });

  @override
  ConsumerState<VideoOverlayLayer> createState() => _VideoOverlayLayerState();
}

class _VideoOverlayLayerState extends ConsumerState<VideoOverlayLayer> {
  final Map<String, Player> _players = {};
  final Map<String, VideoController> _videoControllers = {};
  
  Offset _basePan = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;

  double _resizeBaseScale = 1.0;
  double _accumulatedResizeDx = 0.0;
  double _accumulatedResizeDy = 0.0;

  StreamSubscription? _positionSub;

  @override
  void initState() {
    super.initState();
    _positionSub = widget.mainPlayer?.stream.position.listen((_) => _syncPlayback());
  }

  @override
  void didUpdateWidget(covariant VideoOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mainPlayer != widget.mainPlayer) {
      _positionSub?.cancel();
      _positionSub = widget.mainPlayer?.stream.position.listen((_) => _syncPlayback());
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    for (var player in _players.values) {
      player.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeController(VideoOverlayModel overlay) async {
    if (_players.containsKey(overlay.id)) return;
    
    final player = Player();
    final controller = VideoController(player);
    _players[overlay.id] = player;
    _videoControllers[overlay.id] = controller;
    
    await player.open(Media(overlay.videoPath), play: false);
    await player.setPlaylistMode(PlaylistMode.none);
    await player.setVolume(overlay.volume * 100);
    
    if (mounted) {
      setState(() {});
    }
  }

  void _syncPlayback() {
    if (!mounted || widget.mainPlayer == null) return;
    
    final mainPos = widget.mainPlayer!.state.position;
    final isPlaying = widget.mainPlayer!.state.playing;
    
    final editorState = ref.read(videoEditorProvider);
    
    for (final overlay in editorState.videoOverlays) {
      final player = _players[overlay.id];
      if (player == null) continue;

      if (mainPos >= overlay.timelineStart && mainPos < overlay.timelineEnd) {
        // We are within the active window
        final targetPosition = mainPos - overlay.timelineStart + Duration(milliseconds: (overlay.sourceStart * 1000).round());
        
        // Sync volume (in case it changed)
        final expectedVol = overlay.volume * 100;
        if ((player.state.volume - expectedVol).abs() > 1.0) {
          player.setVolume(expectedVol);
        }

        if (isPlaying) {
          // Only snap if we drift significantly (e.g., due to main video seek)
          // A tight threshold like 300ms causes constant micro-stutters.
          if ((player.state.position - targetPosition).abs() > const Duration(milliseconds: 1000)) {
            player.seek(targetPosition);
          }
          if (!player.state.playing) {
            player.play();
          }
        } else {
          if (player.state.playing) {
            player.pause();
          }
          // Only seek if we're off by a reasonable amount to avoid stutter during scrub
          if ((player.state.position - targetPosition).abs() > const Duration(milliseconds: 150)) {
            player.seek(targetPosition);
          }
        }
      } else {
        // Outside the active window
        if (player.state.playing) {
          player.pause();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    // Clean up players for deleted overlays
    final currentOverlayIds = editorState.videoOverlays.map((e) => e.id).toSet();
    _players.keys.where((id) => !currentOverlayIds.contains(id)).toList().forEach((id) {
      _players[id]?.dispose();
      _players.remove(id);
      _videoControllers.remove(id);
    });

    // Initialize new players
    for (final overlay in editorState.videoOverlays) {
      if (!_players.containsKey(overlay.id)) {
        _initializeController(overlay);
      }
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: _buildVideoOverlays(
        widget.videoCanvasSize,
        (editorState.currentPlaybackPosition * 1000).toInt(),
        editorState.videoOverlays,
        editorState.selectedVideoOverlayId,
        notifier.selectVideoOverlay,
        notifier.updateVideoOverlay,
      ),
    );
  }

  List<Widget> _buildVideoOverlays(
    Size canvasSize,
    int currentPosMs,
    List<VideoOverlayModel> videoOverlays,
    String? selectedOverlayId,
    void Function(String?) onOverlayTapped,
    void Function(String, VideoOverlayModel Function(VideoOverlayModel)) onUpdateOverlay,
  ) {
    var filteredOverlays = videoOverlays;
    if (widget.targetLaneIndex != null) {
      filteredOverlays = filteredOverlays.where((o) => o.laneIndex == widget.targetLaneIndex).toList();
    }

    final List<Widget> children = [];
    for (final overlay in filteredOverlays) {
      final startMs = overlay.timelineStart.inMilliseconds;
      final endMs = overlay.timelineEnd.inMilliseconds;
      
      if (currentPosMs < startMs || currentPosMs >= endMs) {
        continue;
      }

      final player = _players[overlay.id];
      final videoController = _videoControllers[overlay.id];
      if (player == null || videoController == null) {
        continue;
      }

      final isSelected = overlay.id == selectedOverlayId;
      final padXY = isSelected ? 64.0 / overlay.scale : 0.0;
      
      final clampedPosition = _clampPosition(
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

      final videoRatio = (player.state.width ?? 16) / (player.state.height ?? 9);

      Widget videoWidget = ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 240,
          maxHeight: 240,
        ),
        child: AspectRatio(
          aspectRatio: videoRatio,
          child: Opacity(
            opacity: animOpacity.clamp(0.0, 1.0),
            child: Video(controller: videoController, controls: NoVideoControls),
          ),
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
              onTap: () => onOverlayTapped(overlay.id),
              onScaleStart: (details) {
                if (!isSelected) return;
                _basePan = overlay.position;
                _baseFocalPoint = details.focalPoint;
                _baseScale = overlay.scale;
                _baseRotation = overlay.rotation;
              },
              onScaleUpdate: (details) {
                if (!isSelected) return;
                final newScale = (_baseScale * details.scale).clamp(0.1, 10.0);
                final newRotation = _baseRotation + details.rotation;
                final movedPosition =
                    _basePan + (details.focalPoint - _baseFocalPoint);
                final updatedOverlay = overlay.copyWith(
                  scale: newScale,
                  rotation: newRotation,
                );
                final clamped = _clampPosition(
                  updatedOverlay,
                  movedPosition,
                  canvasSize: canvasSize,
                );

                onUpdateOverlay(
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
                        child: videoWidget,
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
                        Positioned(top: padXY, left: padXY, child: FractionalTranslation(translation: const Offset(-0.5, -0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, -1, onUpdateOverlay))))),
                        Positioned(top: padXY, right: padXY, child: FractionalTranslation(translation: const Offset(0.5, -0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, -1, onUpdateOverlay))))),
                        Positioned(bottom: padXY, left: padXY, child: FractionalTranslation(translation: const Offset(-0.5, 0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, -1, 1, onUpdateOverlay))))),
                        Positioned(bottom: padXY, right: padXY, child: FractionalTranslation(translation: const Offset(0.5, 0.5), child: Transform.scale(scale: 1 / overlay.scale, child: _buildCornerDot((_) => _handleResizeStart(overlay), (d) => _handleResizeUpdate(d, overlay, 1, 1, onUpdateOverlay))))),
                        
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
                                child: _buildFloatingActionBar(overlay),
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

  Offset _clampPosition(
    VideoOverlayModel overlay,
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

  void _handleResizeStart(VideoOverlayModel overlay) {
    _resizeBaseScale = overlay.scale;
    _accumulatedResizeDx = 0.0;
    _accumulatedResizeDy = 0.0;
  }

  void _handleResizeUpdate(
    DragUpdateDetails details,
    VideoOverlayModel overlay,
    double dirX,
    double dirY,
    void Function(String, VideoOverlayModel Function(VideoOverlayModel)) onUpdate,
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

  Widget _buildFloatingActionBar(VideoOverlayModel overlay) {
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
            onTap: () => notifier.deleteVideoOverlay(overlay.id),
            child: const Icon(LucideIcons.trash2, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: () => notifier.duplicateVideoOverlay(overlay.id),
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
