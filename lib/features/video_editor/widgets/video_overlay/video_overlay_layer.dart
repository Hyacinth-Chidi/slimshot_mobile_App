import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../models/video_overlay_model.dart';
import '../../providers/video_editor_notifier.dart';
import '../overlay_mask_clip.dart';

class VideoOverlayLayer extends ConsumerStatefulWidget {
  final Size videoCanvasSize;
  final int? targetLaneIndex;

  const VideoOverlayLayer({
    super.key,
    required this.videoCanvasSize,
    this.targetLaneIndex,
  });

  @override
  ConsumerState<VideoOverlayLayer> createState() => _VideoOverlayLayerState();
}

class _VideoOverlayLayerState extends ConsumerState<VideoOverlayLayer> {
  /// One player per video overlay, on `video_player` (ExoPlayer underneath).
  ///
  /// The preview draws overlays as Flutter widgets; **export renders them in
  /// the GL pass instead** (`OverlayRenderer`), which is why the two must not
  /// both draw. Moving preview overlays into the engine too would delete this
  /// layer entirely — the right end state, and why this deliberately stays a
  /// thin "keep it in step with the playhead" wrapper rather than growing.
  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, bool> _isSeeking = {};

  /// When each overlay was last corrected, so a correction cannot be issued
  /// again before the decoder has had time to actually land on the target.
  final Map<String, int> _lastSeekMs = {};

  /// The last position sample read from each controller, and the wall clock
  /// when it changed. `VideoPlayerController.value.position` is **polled**
  /// (roughly twice a second), not continuous, so between samples it reports a
  /// stale value while the target keeps advancing. Extrapolating from the
  /// sample is what makes a drift measurement mean anything at 30Hz.
  final Map<String, Duration> _positionSample = {};
  final Map<String, int> _positionSampleAtMs = {};

  /// Drift must persist across this many consecutive checks before a seek is
  /// issued. One bad reading is measurement lag; several in a row is real
  /// divergence.
  static const int _kDriftStrikesBeforeSeek = 3;
  final Map<String, int> _driftStrikes = {};

  /// Minimum gap between corrections on one overlay. A seek flushes the
  /// decoder, which is far more visible than the skew it removes — the same
  /// rule the engine's own lane drift correction follows (dead-ends 11).
  static const int _kSeekCooldownMs = 600;

  /// Only correct real divergence. Below this the picture is fine and a seek
  /// would cost a flush for nothing.
  static const Duration _kPlayingDriftTolerance = Duration(milliseconds: 400);

  /// Paused, there is no decoder churn to protect and the frame under the
  /// playhead should be exact.
  static const Duration _kPausedDriftTolerance = Duration(milliseconds: 120);
  
  Offset _basePan = Offset.zero;
  Offset _baseFocalPoint = Offset.zero;
  double _baseScale = 1.0;
  double _baseRotation = 0.0;

  double _resizeBaseScale = 1.0;
  double _accumulatedResizeDx = 0.0;
  double _accumulatedResizeDy = 0.0;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _initializeController(VideoOverlayModel overlay) async {
    if (_controllers.containsKey(overlay.id)) return;

    final controller = VideoPlayerController.file(File(overlay.videoPath));
    // Registered before initialize completes so a rebuild in the meantime
    // cannot start a second controller for the same overlay.
    _controllers[overlay.id] = controller;

    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(overlay.volume);
    } catch (_) {
      // An unreadable overlay simply does not draw; export reports its own.
      _controllers.remove(overlay.id);
      await controller.dispose();
      return;
    }

    if (!mounted) {
      await controller.dispose();
      _controllers.remove(overlay.id);
      return;
    }
    setState(() {});
  }

  /// Keeps every overlay player in step with the editor's own clock.
  ///
  /// Driven by `currentPlaybackPosition` from state — the native engine's
  /// playhead — and never by another Flutter player's position stream. These
  /// players are followers with no clock of their own; hanging them off a
  /// second player's stream is what once left video overlays frozen in the
  /// preview while the same overlays played correctly in the export.
  void _syncPlayback() {
    if (!mounted) return;

    final editorState = ref.read(videoEditorProvider);
    final mainPos = Duration(
      milliseconds: (editorState.currentPlaybackPosition * 1000).round(),
    );
    final isPlaying = editorState.isPlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;


    for (final overlay in editorState.videoOverlays) {
      final controller = _controllers[overlay.id];
      if (controller == null || !controller.value.isInitialized) continue;

      final value = controller.value;

      if (mainPos >= overlay.timelineStart && mainPos < overlay.timelineEnd) {
        // We are within the active window
        final targetPosition = mainPos -
            overlay.timelineStart +
            Duration(milliseconds: (overlay.sourceStart * 1000).round());

        // Sync volume (in case it changed)
        if ((value.volume - overlay.volume).abs() > 0.01) {
          controller.setVolume(overlay.volume);
        }

        final estimated = _estimatedPosition(overlay.id, value, nowMs);
        final drift = (estimated - targetPosition).abs();
        final tolerance =
            isPlaying ? _kPlayingDriftTolerance : _kPausedDriftTolerance;

        if (isPlaying) {
          // Start it before correcting: a player that has not been told to
          // play has a position that cannot converge, so seeking it first
          // just flushes a decoder that is about to start anyway.
          if (!value.isPlaying && _isSeeking[overlay.id] != true) {
            controller.play();
            // Its own clock takes over from here; the stale sample must not
            // be read as drift on the next tick.
            _resetTracking(overlay.id, nowMs, value.position);
            continue;
          }
        } else if (value.isPlaying) {
          controller.pause();
          _resetTracking(overlay.id, nowMs, value.position);
          continue;
        }

        if (drift <= tolerance) {
          _driftStrikes[overlay.id] = 0;
          continue;
        }

        // Drift has to persist. `value.position` is polled roughly twice a
        // second, so a single reading that looks wrong is usually just a
        // stale sample — acting on it is what turned this into a seek storm
        // and cracked the picture (the same failure as dead-ends entry 11).
        final strikes = (_driftStrikes[overlay.id] ?? 0) + 1;
        _driftStrikes[overlay.id] = strikes;
        if (isPlaying && strikes < _kDriftStrikesBeforeSeek) continue;

        if (_isSeeking[overlay.id] == true) continue;
        final lastSeek = _lastSeekMs[overlay.id] ?? 0;
        if (isPlaying && nowMs - lastSeek < _kSeekCooldownMs) continue;

        _driftStrikes[overlay.id] = 0;
        _lastSeekMs[overlay.id] = nowMs;
        _performSeek(overlay.id, controller, targetPosition);
      } else {
        // Outside the active window
        if (value.isPlaying) {
          controller.pause();
          _resetTracking(overlay.id, nowMs, value.position);
        }
      }
    }
  }

  /// Where the overlay actually is now, filling in between its coarse
  /// position samples.
  ///
  /// `value.position` only refreshes a couple of times a second. Comparing a
  /// 30Hz target against it measures the poll interval, not real drift — so
  /// while the sample is unchanged and the player is playing, the elapsed
  /// wall time since it *did* change is added to it.
  Duration _estimatedPosition(
    String id,
    VideoPlayerValue value,
    int nowMs,
  ) {
    final sample = _positionSample[id];
    if (sample != value.position) {
      _positionSample[id] = value.position;
      _positionSampleAtMs[id] = nowMs;
      return value.position;
    }
    if (!value.isPlaying) return value.position;
    final since = nowMs - (_positionSampleAtMs[id] ?? nowMs);
    return value.position + Duration(milliseconds: since);
  }

  /// Forgets the tracking state for one overlay after a transport change, so
  /// a sample taken under the old state cannot be read as drift.
  void _resetTracking(String id, int nowMs, Duration position) {
    _positionSample[id] = position;
    _positionSampleAtMs[id] = nowMs;
    _driftStrikes[id] = 0;
  }

  Future<void> _performSeek(
    String id,
    VideoPlayerController controller,
    Duration position,
  ) async {
    _isSeeking[id] = true;
    try {
      await controller.seekTo(position);
    } catch (_) {
      // Ignore seek errors
    } finally {
      if (mounted) {
        _isSeeking[id] = false;
        // The player is at the target but its polled sample has not caught up
        // yet. Seeding the estimate with where it was *told* to go stops the
        // next tick reading that lag as fresh drift and seeking again.
        _resetTracking(id, DateTime.now().millisecondsSinceEpoch, position);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // The playhead and the transport state are the overlay players' clock.
    ref.listen<double>(
      videoEditorProvider.select((s) => s.currentPlaybackPosition),
      (_, __) => _syncPlayback(),
    );
    ref.listen<bool>(
      videoEditorProvider.select((s) => s.isPlaying),
      (_, __) => _syncPlayback(),
    );

    final editorState = ref.watch(videoEditorProvider);
    final notifier = ref.read(videoEditorProvider.notifier);

    // Clean up players for deleted overlays
    final currentOverlayIds = editorState.videoOverlays.map((e) => e.id).toSet();
    _controllers.keys
        .where((id) => !currentOverlayIds.contains(id))
        .toList()
        .forEach((id) {
      _controllers.remove(id)?.dispose();
      _isSeeking.remove(id);
      _lastSeekMs.remove(id);
      _positionSample.remove(id);
      _positionSampleAtMs.remove(id);
      _driftStrikes.remove(id);
    });

    // Initialize new players
    for (final overlay in editorState.videoOverlays) {
      if (!_controllers.containsKey(overlay.id)) {
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

      final controller = _controllers[overlay.id];
      if (controller == null || !controller.value.isInitialized) {
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
        if (overlay.animationIn == 'fade_in') {
          animOpacity *= progress;
        } else if (overlay.animationIn == 'zoom_in') {
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
        if (overlay.animationOut == 'fade_out') {
          animOpacity *= (1 - progress);
        } else if (overlay.animationOut == 'zoom_in_out') {
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

      // `aspectRatio` already accounts for any rotation tag, so portrait
      // footage is not laid out sideways.
      final videoRatio = controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9;

      Widget videoWidget = ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 240,
          maxHeight: 240,
        ),
        // Cut to the overlay's shape, from the same ClipMask the export
        // resolves in its shader.
        child: OverlayMaskClip(
          mask: overlay.mask,
          child: AspectRatio(
            aspectRatio: videoRatio,
            child: Opacity(
              opacity: animOpacity.clamp(0.0, 1.0),
              child: VideoPlayer(controller),
            ),
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
