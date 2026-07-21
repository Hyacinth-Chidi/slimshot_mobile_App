import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/video_segment.dart';
import '../../models/text_overlay_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/video_overlay_model.dart';
import '../../models/audio_track_model.dart';
import '../../models/video_editor_state.dart';
import '../../providers/video_editor_notifier.dart';
import '../../services/video_editor_service.dart';

class _WaveformPainter extends CustomPainter {
  final Color color;
  final int seed;

  _WaveformPainter({required this.color, this.seed = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final random = Random(seed);
    const barWidth = 2.0;
    const gap = 1.5;
    final centerY = size.height / 2;
    final barCount = (size.width / (barWidth + gap)).floor();

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      // Generate a pseudo-random height with some smoothness
      final amplitude = 0.2 + random.nextDouble() * 0.8;
      final barHeight = size.height * amplitude * 0.8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x + barWidth / 2, centerY), width: barWidth, height: barHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ScrollableTimeline extends ConsumerStatefulWidget {
  final Player player;
  final String inputPath;
  final double durationSeconds;
  final double timelinePositionSeconds;
  final RangeValues trimRange;
  final List<VideoSegment> segments;
  final String? selectedSegmentId;
  final ValueChanged<String?>? onSegmentTapped;
  final ValueChanged<RangeValues>? onTrimChanged;

  final List<TextOverlayModel> textOverlays;
  final String? selectedTextId;
  final ValueChanged<String>? onTextTapped;
  final ValueChanged<String>? onTextDoubleTapped;
  final void Function(String id, Duration start, Duration end, {int? newLaneIndex})? onTextTrimChanged;

  final List<ImageOverlayModel> imageOverlays;
  final String? selectedImageId;
  final ValueChanged<String>? onImageTapped;
  final void Function(String id, Duration start, Duration end, {int? newLaneIndex})? onImageTrimChanged;

  final List<VideoOverlayModel> videoOverlays;
  final String? selectedVideoId;
  final ValueChanged<String>? onVideoTapped;
  final void Function(String id, Duration start, Duration end, {int? newLaneIndex})? onVideoTrimChanged;

  final List<AudioTrackModel> audioTracks;
  final String? selectedAudioId;
  final ValueChanged<String>? onAudioTapped;
  final void Function(String id, double newTimelineStart, {int? newLaneIndex})? onAudioDragChanged;
  final void Function(String id, double newTimelineStart, double newSourceStart, double newSourceEnd)? onAudioTrimChanged;
  final ValueChanged<double>? onTimelinePositionChanged;
  final VoidCallback? onDragEnd;

  const ScrollableTimeline({
    super.key,
    required this.player,
    required this.inputPath,
    required this.durationSeconds,
    this.timelinePositionSeconds = 0.0,
    required this.trimRange,
    this.segments = const [],
    this.selectedSegmentId,
    this.onSegmentTapped,
    this.onTrimChanged,
    this.textOverlays = const [],
    this.selectedTextId,
    this.onTextTapped,
    this.onTextDoubleTapped,
    this.onTextTrimChanged,
    this.imageOverlays = const [],
    this.selectedImageId,
    this.onImageTapped,
    this.onImageTrimChanged,
    this.videoOverlays = const [],
    this.selectedVideoId,
    this.onVideoTapped,
    this.onVideoTrimChanged,
    this.audioTracks = const [],
    this.selectedAudioId,
    this.onAudioTapped,
    this.onAudioDragChanged,
    this.onAudioTrimChanged,
    this.onTimelinePositionChanged,
    this.onDragEnd,
  });

  @override
  ConsumerState<ScrollableTimeline> createState() => _ScrollableTimelineState();
}

class _ScrollableTimelineState extends ConsumerState<ScrollableTimeline> {
  final VideoEditorService _service = VideoEditorService();
  final ScrollController _scrollController = ScrollController();

  List<Uint8List>? _thumbnails;
  bool _isLoading = true;
  String? _error;

  static const double _pixelsPerSecond = 50.0;
  static const double _filmstripHeight = 48.0; // Reduced to be more compact
  static const double _laneHeight = 32.0;
  static const double _handleWidth = 12.0; // Thinner handle
  static const double _handleTouchWidth = 44.0; // Keep hit area large for easy grabbing
  static const double _timeRulerHeight = 20.0;
  static const int _textSnapThresholdMs = 200;

  bool _isUserScrolling = false;
  bool _isAutoScrolling = false;
  bool _isDraggingTrimHandle = false;
  bool _isDraggingTextClip = false;
  String? _draggingTextId;
  Duration? _textDragInitialStart;
  Duration? _textDragInitialEnd;
  int? _activeSnapGuideMs;
  String? _trimmingTextId;
  Duration? _textTrimInitialTime;
  double _textTrimAccumulatedDelta = 0.0;

  bool _isDraggingImageClip = false;
  String? _draggingImageId;
  Duration? _imageDragInitialStart;
  Duration? _imageDragInitialEnd;

  bool _isDraggingAudioClip = false;
  String? _draggingAudioId;
  double? _audioDragInitialTimelineStart;

  String? _trimmingAudioId;
  double? _audioTrimInitialTimelineStart;
  double? _audioTrimInitialSourceStart;
  double? _audioTrimInitialSourceEnd;
  double _audioTrimAccumulatedDelta = 0.0;

  String? _trimmingImageId;
  Duration? _imageTrimInitialTime;
  double _imageTrimAccumulatedDelta = 0.0;

  bool _isDraggingVideoClip = false;
  String? _draggingVideoId;
  Duration? _videoDragInitialStart;
  Duration? _videoDragInitialEnd;

  String? _trimmingVideoId;
  Duration? _videoTrimInitialTime;
  double _videoTrimAccumulatedDelta = 0.0;

  // Shared drag-start lane index for vertical 2D drag
  int _dragStartLaneIndex = 0;
  int _dragStartMaxLane = 0;

  double get _totalEditedDuration {
    final videoDuration =
        widget.segments.fold(0.0, (sum, seg) => sum + seg.duration);
    final maxAudioEnd = widget.audioTracks.fold(
      0.0,
      (maxEnd, track) => max(maxEnd, track.timelineEnd),
    );
    return max(videoDuration, maxAudioEnd);
  }

  int get _maxLane {
    int m = 0;
    for (final o in widget.textOverlays) {
      if (o.laneIndex > m) m = o.laneIndex;
    }
    for (final o in widget.imageOverlays) {
      if (o.laneIndex > m) m = o.laneIndex;
    }
    for (final o in widget.videoOverlays) {
      if (o.laneIndex > m) m = o.laneIndex;
    }
    for (final o in widget.audioTracks) {
      if (o.laneIndex > m) m = o.laneIndex;
    }
    return m;
  }

  double _timelineTimeToSourceTime(double timelineTime) {
    if (widget.segments.isEmpty) return timelineTime;
    double accumulated = 0.0;
    for (final segment in widget.segments) {
      if (timelineTime >= accumulated && timelineTime <= accumulated + segment.duration) {
        return segment.sourceStart + ((timelineTime - accumulated) * segment.speed);
      }
      accumulated += segment.duration;
    }
    return widget.segments.last.sourceEnd;
  }

  @override
  void initState() {
    super.initState();
    _loadThumbnails();
  }

  @override
  void didUpdateWidget(covariant ScrollableTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputPath != widget.inputPath) {
      _thumbnails = null;
      _error = null;
      _isLoading = true;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _loadThumbnails();
    }

    if (oldWidget.timelinePositionSeconds != widget.timelinePositionSeconds) {
      _syncScrollToTimelinePosition(widget.timelinePositionSeconds);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncScrollToTimelinePosition(double timelinePosition) {
    if (_isUserScrolling || _isDraggingTrimHandle || _isDraggingTextClip) {
      return;
    }
    if (_scrollController.hasClients) {
      final targetOffset = timelinePosition * _pixelsPerSecond;
      final nextOffset = targetOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ).toDouble();

      if ((_scrollController.offset - nextOffset).abs() < 0.5) return;

      _isAutoScrolling = true;
      _scrollController.jumpTo(nextOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _isAutoScrolling = false;
        }
      });
    }
  }

  Future<void> _loadThumbnails() async {
    try {
      final thumbnailCount =
          (widget.durationSeconds / 2).ceil().clamp(5, 30).toInt();

      final thumbnails = await _service.generateThumbnails(
        inputPath: widget.inputPath,
        durationSeconds: widget.durationSeconds,
        count: thumbnailCount,
      );

      if (mounted) {
        setState(() {
          _thumbnails = thumbnails;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Only handle horizontal scrolling for the timeline position
    if (notification.metrics.axis != Axis.horizontal) {
      return false;
    }

    if (_isAutoScrolling || _isDraggingTrimHandle || _isDraggingTextClip) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _isUserScrolling = true;
      if (widget.player.state.playing) {
        widget.player.pause();
      }
    } else if (notification is ScrollUpdateNotification) {
      final timelineSeconds = (notification.metrics.pixels / _pixelsPerSecond)
          .clamp(0.0, _totalEditedDuration)
          .toDouble();
      widget.onTimelinePositionChanged?.call(timelineSeconds);
      final sourceSeconds = _timelineTimeToSourceTime(timelineSeconds);
      widget.player.seek(
        Duration(milliseconds: (sourceSeconds * 1000).round()),
      );
    } else if (notification is ScrollEndNotification) {
      _isUserScrolling = false;
    }
    return true;
  }

  void _updateTrim(double newStart, double newEnd) {
    newStart = newStart.clamp(0.0, widget.durationSeconds).toDouble();
    newEnd = newEnd.clamp(0.0, widget.durationSeconds).toDouble();
    if (newEnd - newStart < 0.5) return;
    widget.onTrimChanged?.call(RangeValues(newStart, newEnd));
  }

  void _previewTrimPosition(double sourceSeconds) {
    final preview = sourceSeconds.clamp(0.0, widget.durationSeconds).toDouble();
    widget.player.seek(
      Duration(milliseconds: (preview * 1000).round()),
    );
  }

  void _beginTrimDrag() {
    _isDraggingTrimHandle = true;
    if (widget.player.state.playing) {
      widget.player.pause();
    }
  }

  void _endTrimDrag() {
    _isDraggingTrimHandle = false;
    widget.onDragEnd?.call();
  }

  void _beginTextClipDrag(TextOverlayModel text) {
    setState(() {
      _isDraggingTextClip = true;
      _draggingTextId = text.id;
      _textDragInitialStart = text.startTime;
      _textDragInitialEnd = text.endTime;
      _activeSnapGuideMs = text.startTime.inMilliseconds;
      _dragStartLaneIndex = text.laneIndex;
      _dragStartMaxLane = _maxLane;
    });
    if (widget.player.state.playing) {
      widget.player.pause();
    }
    widget.onTextTapped?.call(text.id);
  }

  int _applyTextSnap(int proposedStartMs, int maxStartMs) {
    int snappedStartMs = proposedStartMs;
    int? snapGuideMs;

    final playheadMs = (widget.timelinePositionSeconds * 1000).round()
        .clamp(0, (_totalEditedDuration * 1000).round())
        .toInt();
    if ((proposedStartMs - playheadMs).abs() <= _textSnapThresholdMs) {
      snappedStartMs = playheadMs;
      snapGuideMs = playheadMs;
    } else {
      final nearestSecondMs = (proposedStartMs / 1000).round() * 1000;
      if ((proposedStartMs - nearestSecondMs).abs() <= _textSnapThresholdMs) {
        snappedStartMs = nearestSecondMs;
        snapGuideMs = nearestSecondMs;
      }
    }

    snappedStartMs = snappedStartMs.clamp(0, maxStartMs).toInt();

    if (_activeSnapGuideMs != snapGuideMs) {
      setState(() {
        _activeSnapGuideMs = snapGuideMs;
      });
    }

    return snappedStartMs;
  }

  void _moveTextClip(LongPressMoveUpdateDetails details) {
    if (!_isDraggingTextClip ||
        _draggingTextId == null ||
        _textDragInitialStart == null ||
        _textDragInitialEnd == null) {
      return;
    }

    final deltaMs =
        (details.offsetFromOrigin.dx / _pixelsPerSecond * 1000).round();
    final clipDurationMs =
        _textDragInitialEnd!.inMilliseconds - _textDragInitialStart!.inMilliseconds;
    final maxStartMs = ((widget.durationSeconds * 1000).round() - clipDurationMs)
        .clamp(0, double.infinity)
        .toInt();

    final proposedStartMs = (_textDragInitialStart!.inMilliseconds + deltaMs)
        .clamp(0, maxStartMs)
        .toInt();
    final nextStartMs = _applyTextSnap(proposedStartMs, maxStartMs);
    final nextEndMs = nextStartMs + clipDurationMs;

    final nextStart = Duration(milliseconds: nextStartMs);
    final nextEnd = Duration(milliseconds: nextEndMs);

    final lanesMoved = -(details.offsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(0, min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved));

    widget.onTextTrimChanged?.call(_draggingTextId!, nextStart, nextEnd, newLaneIndex: newLaneIndex);
    _previewTrimPosition(nextStart.inMilliseconds / 1000.0);
  }

  void _endTextClipDrag() {
    setState(() {
      _isDraggingTextClip = false;
      _draggingTextId = null;
      _textDragInitialStart = null;
      _textDragInitialEnd = null;
      _activeSnapGuideMs = null;
    });
    widget.onDragEnd?.call();
  }

  void _beginAudioClipDrag(AudioTrackModel audio) {
    HapticFeedback.selectionClick();
    setState(() {
      _isDraggingAudioClip = true;
      _draggingAudioId = audio.id;
      _audioDragInitialTimelineStart = audio.timelineStart;
      _dragStartLaneIndex = audio.laneIndex;
      _dragStartMaxLane = _maxLane;
    });
  }

  void _moveAudioClip(LongPressMoveUpdateDetails details) {
    if (!_isDraggingAudioClip || _audioDragInitialTimelineStart == null) return;
    
    final deltaSeconds = details.localOffsetFromOrigin.dx / _pixelsPerSecond;
    final totalVideoDuration = widget.durationSeconds;
    
    final audio = widget.audioTracks.firstWhere((a) => a.id == _draggingAudioId, orElse: () => widget.audioTracks.first);
    if (audio.id != _draggingAudioId) return;
    
    final duration = audio.trimmedDuration;

    double nextStart = _audioDragInitialTimelineStart! + deltaSeconds;
    if (nextStart < 0) nextStart = 0;
    if (nextStart + duration > totalVideoDuration) {
      nextStart = totalVideoDuration - duration;
      if (nextStart < 0) nextStart = 0;
    }

    final lanesMoved = -(details.localOffsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(0, min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved));

    widget.onAudioDragChanged?.call(_draggingAudioId!, nextStart, newLaneIndex: newLaneIndex);
  }

  void _endAudioClipDrag() {
    setState(() {
      _isDraggingAudioClip = false;
      _draggingAudioId = null;
      _audioDragInitialTimelineStart = null;
    });
    widget.onDragEnd?.call();
  }

  void _beginAudioTrim(AudioTrackModel audio) {
    HapticFeedback.selectionClick();
    setState(() {
      _trimmingAudioId = audio.id;
      _audioTrimInitialTimelineStart = audio.timelineStart;
      _audioTrimInitialSourceStart = audio.sourceStart;
      _audioTrimInitialSourceEnd = audio.sourceEnd;
      _audioTrimAccumulatedDelta = 0.0;
    });
    if (widget.player.state.playing) {
      widget.player.pause();
    }
  }

  void _updateAudioTrimStart(DragUpdateDetails details) {
    if (_trimmingAudioId == null || _audioTrimInitialTimelineStart == null || _audioTrimInitialSourceStart == null || _audioTrimInitialSourceEnd == null) return;

    final audio = widget.audioTracks.firstWhere((a) => a.id == _trimmingAudioId, orElse: () => widget.audioTracks.first);
    if (audio.id != _trimmingAudioId) return;

    _audioTrimAccumulatedDelta += details.delta.dx;
    final deltaSeconds = _audioTrimAccumulatedDelta / _pixelsPerSecond;

    double newTimelineStart = _audioTrimInitialTimelineStart! + deltaSeconds;
    double newSourceStart = _audioTrimInitialSourceStart! + deltaSeconds;

    // Constraints for left handle:
    if (newSourceStart < 0) {
      newTimelineStart -= newSourceStart;
      newSourceStart = 0;
    }
    if (newTimelineStart < 0) {
      newSourceStart -= newTimelineStart;
      newTimelineStart = 0;
    }
    if (_audioTrimInitialSourceEnd! - newSourceStart < 0.5) {
      newSourceStart = _audioTrimInitialSourceEnd! - 0.5;
      newTimelineStart = _audioTrimInitialTimelineStart! + (newSourceStart - _audioTrimInitialSourceStart!);
    }

    widget.onAudioTrimChanged?.call(_trimmingAudioId!, newTimelineStart, newSourceStart, _audioTrimInitialSourceEnd!);
    _previewTrimPosition(newTimelineStart);
  }

  void _updateAudioTrimEnd(DragUpdateDetails details) {
    if (_trimmingAudioId == null || _audioTrimInitialTimelineStart == null || _audioTrimInitialSourceStart == null || _audioTrimInitialSourceEnd == null) return;

    final audio = widget.audioTracks.firstWhere((a) => a.id == _trimmingAudioId, orElse: () => widget.audioTracks.first);
    if (audio.id != _trimmingAudioId) return;

    _audioTrimAccumulatedDelta += details.delta.dx;
    final deltaSeconds = _audioTrimAccumulatedDelta / _pixelsPerSecond;

    double newSourceEnd = _audioTrimInitialSourceEnd! + deltaSeconds;

    // Constraints for right handle:
    if (newSourceEnd > audio.sourceDuration) {
      newSourceEnd = audio.sourceDuration;
    }
    if (newSourceEnd - _audioTrimInitialSourceStart! < 0.5) {
      newSourceEnd = _audioTrimInitialSourceStart! + 0.5;
    }

    widget.onAudioTrimChanged?.call(_trimmingAudioId!, _audioTrimInitialTimelineStart!, _audioTrimInitialSourceStart!, newSourceEnd);
    
    final newTimelineEnd = _audioTrimInitialTimelineStart! + (newSourceEnd - _audioTrimInitialSourceStart!);
    _previewTrimPosition(newTimelineEnd);
  }

  void _endAudioTrim() {
    setState(() {
      _trimmingAudioId = null;
      _audioTrimInitialTimelineStart = null;
      _audioTrimInitialSourceStart = null;
      _audioTrimInitialSourceEnd = null;
    });
    widget.onDragEnd?.call();
  }

  String _formatTimeRuler(double seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(1, '0');
    final secs = (seconds.toInt() % 60).toString().padLeft(2, '0');
    final ms = ((seconds - seconds.toInt()) * 100).toInt().toString().padLeft(2, '0');
    return '$mins:$secs:$ms';
  }

  Widget _buildGlobalFilmstripRow(double totalVideoWidth) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryStart),
        ),
      );
    }

    if (_error != null || _thumbnails == null || _thumbnails!.isEmpty) {
      return Center(
        child: Icon(LucideIcons.imageOff, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 18),
      );
    }

    return SizedBox(
      width: totalVideoWidth,
      height: _filmstripHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _thumbnails!.map((bytes) {
          return Expanded(
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildSegmentTracks(double totalVideoWidth, double topOffset) {
    final widgets = <Widget>[];
    double accumulatedPx = 0.0;

    for (int i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      final segmentWidthPx = segment.duration * _pixelsPerSecond;
      final sourceStartPx = segment.sourceStart * _pixelsPerSecond;

      // Filmstrip chunk
      widgets.add(
        Positioned(
          top: topOffset,
          left: accumulatedPx,
          width: segmentWidthPx,
          height: _filmstripHeight,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: totalVideoWidth,
              maxWidth: totalVideoWidth,
              child: Transform.scale(
                scaleX: 1 / segment.speed,
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(-sourceStartPx, 0),
                  child: _buildGlobalFilmstripRow(totalVideoWidth),
                ),
              ),
            ),
          ),
        ),
      );



      // Gap line between segments
      if (i > 0) {
        widgets.add(
          Positioned(
            top: topOffset,
            left: accumulatedPx - 1,
            width: 2,
            height: _filmstripHeight,
            child: Container(color: Colors.black),
          ),
        );
      }

      accumulatedPx += segmentWidthPx;
    }

    return widgets;
  }

  List<Widget> _buildSegmentBorders(double topOffset, VideoEditorState editorState) {
    final widgets = <Widget>[];
    double accumulatedPx = 0.0;

    for (int i = 0; i < widget.segments.length; i++) {
      final segment = widget.segments[i];
      final segmentWidthPx = segment.duration * _pixelsPerSecond;
      final isSelected = widget.selectedSegmentId == segment.id;

      widgets.add(
        Positioned(
          top: topOffset,
          left: accumulatedPx,
          width: segmentWidthPx,
          height: _filmstripHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSegmentTapped?.call(segment.id),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? AppColors.primaryStart : Colors.white.withValues(alpha: 0.18),
                  width: isSelected ? 2.5 : 1,
                ),
              ),
            ),
          ),
        ),
      );

      // Add Transition Indicator between clips
      if (i < widget.segments.length - 1) {
        final transitionType = segment.transitionType;
        final hasTransition = transitionType != null;
        final isTransitionSelected = editorState.selectedTransitionSegmentId == segment.id;

        widgets.add(
          Positioned(
            top: topOffset + _filmstripHeight / 2 - 12, // Centered vertically
            left: accumulatedPx + segmentWidthPx - 12, // Centered horizontally on the seam
            width: 24,
            height: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                ref.read(videoEditorProvider.notifier).selectTransition(segment.id);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isTransitionSelected
                      ? AppColors.primaryStart
                      : (hasTransition ? Colors.white : Colors.black87),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Icon(
                  hasTransition ? LucideIcons.infinity : LucideIcons.minus,
                  color: isTransitionSelected
                      ? Colors.white
                      : (hasTransition ? Colors.black : Colors.white),
                  size: 14,
                ),
              ),
            ),
          ),
        );
      }

      accumulatedPx += segmentWidthPx;
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final halfWidth = screenWidth / 2;
    
    final contentWidth = _totalEditedDuration * _pixelsPerSecond;
    final totalVideoWidth = widget.durationSeconds * _pixelsPerSecond;

    double? trimStartPx;
    double? trimEndPx;

    if (widget.selectedSegmentId != null) {
      double accumulated = 0.0;
      for (final segment in widget.segments) {
        if (segment.id == widget.selectedSegmentId) {
          trimStartPx = accumulated * _pixelsPerSecond;
          trimEndPx = (accumulated + segment.duration) * _pixelsPerSecond;
          break;
        }
        accumulated += segment.duration;
      }
    }

    final trimWidthPx = (trimEndPx != null && trimStartPx != null) ? trimEndPx - trimStartPx : 0.0;
    final int maxLane = _maxLane;
    final double lanesHeight = (maxLane + 1) * _laneHeight;
    final double filmstripTop = _timeRulerHeight + lanesHeight;
    final double totalHeight = filmstripTop + _filmstripHeight;

    final double containerHeight = min(totalHeight + 16, 250.0);

    return Container(
      height: containerHeight, // padding handled by containerHeight
      color: AppColors.background, // match dark theme
      child: Stack(
        children: [
          // ── Scrollable content ──
          SingleChildScrollView(
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
              child: Container(
                padding: EdgeInsets.only(left: halfWidth, right: halfWidth, top: 8, bottom: 8),
                child: SizedBox(
                  width: max(contentWidth, screenWidth), // ensure minimum width to scroll
                  height: totalHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => widget.onSegmentTapped?.call(null),
                    child: Stack(
                      clipBehavior: Clip.none,
                    children: [
                      // 1. Time ruler
                      SizedBox(
                        height: _timeRulerHeight,
                        width: contentWidth,
                        child: CustomPaint(
                          painter: _TimeRulerPainter(
                            durationSeconds: _totalEditedDuration,
                            pixelsPerSecond: _pixelsPerSecond,
                            formatTime: _formatTimeRuler,
                          ),
                        ),
                      ),

                      // 2. Track contents (Video, Audio, Voiceover) clipped per segment
                      ..._buildSegmentTracks(totalVideoWidth, filmstripTop),

                      // 3. Selection borders & tap targets
                      ..._buildSegmentBorders(filmstripTop, editorState),

                      // 4. Audio tracks
                      ..._buildAudioTracks(maxLane),

                      // 5. Text overlays track
                      ..._buildTextTracks(maxLane),

                      // 6. Image overlays track
                      ..._buildImageTracks(maxLane),

                      // 7. Video overlays track
                      ..._buildVideoTracks(maxLane),

                      if (_activeSnapGuideMs != null)
                        Positioned(
                          top: _timeRulerHeight + 2,
                          left: (_activeSnapGuideMs! / 1000.0) * _pixelsPerSecond,
                          width: 2,
                          height: _laneHeight - 4,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primaryStart,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.primaryStart,
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // 4. Trim brackets & handles for selected segment
                      if (widget.selectedSegmentId != null && trimStartPx != null && trimEndPx != null) ...[
                        // Top and bottom borders for the selected segment
                        Positioned(
                          top: filmstripTop,
                          height: _filmstripHeight,
                          left: trimStartPx + _handleWidth,
                          width: (trimWidthPx - _handleWidth * 2).clamp(0, double.infinity).toDouble(),
                          child: IgnorePointer(
                            child: Container(
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: AppColors.primaryStart, width: 2.5),
                                  bottom: BorderSide(color: AppColors.primaryStart, width: 2.5),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Left trim handle
                        Positioned(
                          top: filmstripTop,
                          height: _filmstripHeight,
                          left: trimStartPx - ((_handleTouchWidth - _handleWidth) / 2),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (_) => _beginTrimDrag(),
                            onHorizontalDragUpdate: (details) {
                              final nextStart = widget.trimRange.start + (details.delta.dx / _pixelsPerSecond);
                              _updateTrim(nextStart, widget.trimRange.end);
                              _previewTrimPosition(nextStart);
                            },
                            onHorizontalDragEnd: (_) => _endTrimDrag(),
                            onHorizontalDragCancel: _endTrimDrag,
                            child: SizedBox(
                              width: _handleTouchWidth,
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  width: _handleWidth,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryStart,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(6),
                                      bottomLeft: Radius.circular(6),
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 2.5,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Right trim handle
                        Positioned(
                          top: filmstripTop,
                          height: _filmstripHeight,
                          left: trimEndPx - _handleWidth - ((_handleTouchWidth - _handleWidth) / 2),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (_) => _beginTrimDrag(),
                            onHorizontalDragUpdate: (details) {
                              final nextEnd = widget.trimRange.end + (details.delta.dx / _pixelsPerSecond);
                              _updateTrim(widget.trimRange.start, nextEnd);
                              _previewTrimPosition(nextEnd);
                            },
                            onHorizontalDragEnd: (_) => _endTrimDrag(),
                            onHorizontalDragCancel: _endTrimDrag,
                            child: SizedBox(
                              width: _handleTouchWidth,
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  width: _handleWidth,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryStart,
                                    borderRadius: BorderRadius.only(
                                      topRight: Radius.circular(6),
                                      bottomRight: Radius.circular(6),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.chevron_right, size: 16, color: Colors.black),
                                  ),
                                ),
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
          ),
          ),

          // ── Fixed center playhead ──
          Positioned(
            left: halfWidth - 0.75,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Column(
                children: [
                  // Small triangle indicator at the top
                  CustomPaint(
                    size: const Size(10, 6),
                    painter: _TrianglePainter(color: Colors.white),
                  ),
                  Expanded(
                    child: Container(width: 1.5, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAudioTracks(int maxLane) {
    final widgets = <Widget>[];

    for (int i = 0; i < widget.audioTracks.length; i++) {
      final audio = widget.audioTracks[i];
      final startPx = audio.timelineStart * _pixelsPerSecond;
      final endPx = audio.timelineEnd * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0, double.infinity).toDouble();
      
      final isSelected = audio.id == widget.selectedAudioId;
      final isBeingDragged = _isDraggingAudioClip && _draggingAudioId == audio.id;
      final double topOffset = _timeRulerHeight + (maxLane - audio.laneIndex) * _laneHeight + 4;

      widgets.add(
        Positioned(
          top: isBeingDragged ? topOffset - 3 : topOffset,
          left: startPx,
          width: widthPx,
          height: isBeingDragged ? _laneHeight - 2 : _laneHeight - 8,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onAudioTapped?.call(audio.id),
            onLongPressStart: (_) => _beginAudioClipDrag(audio),
            onLongPressMoveUpdate: _moveAudioClip,
            onLongPressEnd: (_) => _endAudioClipDrag(),
            child: Container(
              decoration: BoxDecoration(
                color: isBeingDragged 
                    ? Colors.purpleAccent.shade400 
                    : isSelected 
                        ? Colors.purpleAccent 
                        : Colors.purple.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isBeingDragged 
                      ? Colors.white 
                      : isSelected 
                          ? AppColors.primaryStart 
                          : Colors.transparent,
                  width: isBeingDragged ? 2 : (isSelected ? 2.0 : 1.5),
                ),
                boxShadow: isBeingDragged
                    ? [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WaveformPainter(color: Colors.white.withValues(alpha: 0.3), seed: audio.id.hashCode),
                      ),
                    ),
                    Center(
                      child: isBeingDragged 
                          ? const Icon(Icons.drag_indicator, color: Colors.white, size: 14)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );


      if (isSelected && !isBeingDragged) {
        // Left trim handle — overlap 4px into the clip body
        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx - 12,
            width: 16,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _beginAudioTrim(audio),
              onHorizontalDragUpdate: _updateAudioTrimStart,
              onHorizontalDragEnd: (_) => _endAudioTrim(),
              onHorizontalDragCancel: _endAudioTrim,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.primaryStart,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
                ),
                child: Center(
                  child: Container(
                    width: 2.5,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Right trim handle — overlap 4px into the clip body
        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx + widthPx - 4,
            width: 16,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _beginAudioTrim(audio),
              onHorizontalDragUpdate: _updateAudioTrimEnd,
              onHorizontalDragEnd: (_) => _endAudioTrim(),
              onHorizontalDragCancel: _endAudioTrim,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.primaryStart,
                  borderRadius: BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                ),
                child: const Center(
                  child: Icon(Icons.chevron_right, size: 16, color: Colors.black),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }
  List<Widget> _buildTextTracks(int maxLane) {
    final widgets = <Widget>[];

    for (final text in widget.textOverlays) {
      final startPx = (text.startTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final endPx = (text.endTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0, double.infinity).toDouble();
      
      final isSelected = text.id == widget.selectedTextId;
      final isBeingDragged = _isDraggingTextClip && _draggingTextId == text.id;
      final double topOffset = _timeRulerHeight + (maxLane - text.laneIndex) * _laneHeight + 4; // 4px padding for visual separation

      widgets.add(
        Positioned(
          top: isBeingDragged ? topOffset - 3 : topOffset,
          left: startPx,
          width: widthPx,
          height: isBeingDragged ? _laneHeight - 2 : _laneHeight - 8,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onTextTapped?.call(text.id),
            onDoubleTap: () => widget.onTextDoubleTapped?.call(text.id),
            onLongPressStart: (_) => _beginTextClipDrag(text),
            onLongPressMoveUpdate: _moveTextClip,
            onLongPressEnd: (_) => _endTextClipDrag(),
            child: Container(
              decoration: BoxDecoration(
                color: isBeingDragged
                    ? Colors.deepOrange
                    : isSelected
                        ? AppColors.primaryStart
                        : AppColors.primaryStart.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isBeingDragged
                      ? Colors.white
                      : isSelected
                          ? Colors.white
                          : Colors.transparent,
                  width: isBeingDragged ? 2 : 1.5,
                ),
                boxShadow: isBeingDragged
                    ? [
                        BoxShadow(
                          color: Colors.deepOrange.withValues(alpha: 0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isBeingDragged) ...[
                      const Icon(Icons.drag_indicator, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        text.text,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (isSelected) {
        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _trimmingTextId = text.id;
                  _textTrimInitialTime = text.startTime;
                  _textTrimAccumulatedDelta = 0.0;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingTextId != text.id || _textTrimInitialTime == null) return;
                
                _textTrimAccumulatedDelta += details.delta.dx;
                final deltaMs = (_textTrimAccumulatedDelta / _pixelsPerSecond * 1000).round();
                
                var newStart = Duration(milliseconds: _textTrimInitialTime!.inMilliseconds + deltaMs);
                if (newStart < Duration.zero) newStart = Duration.zero;
                if (newStart >= text.endTime) newStart = text.endTime - const Duration(milliseconds: 100);
                
                widget.onTextTrimChanged?.call(text.id, newStart, text.endTime);
                _previewTrimPosition(newStart.inMilliseconds / 1000.0);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _trimmingTextId = null;
                  _textTrimInitialTime = null;
                });
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _trimmingTextId = null;
                  _textTrimInitialTime = null;
                });
              },
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryStart, // Yellow handle
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        );

        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx + widthPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _trimmingTextId = text.id;
                  _textTrimInitialTime = text.endTime;
                  _textTrimAccumulatedDelta = 0.0;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingTextId != text.id || _textTrimInitialTime == null) return;
                
                _textTrimAccumulatedDelta += details.delta.dx;
                final deltaMs = (_textTrimAccumulatedDelta / _pixelsPerSecond * 1000).round();
                
                var newEnd = Duration(milliseconds: _textTrimInitialTime!.inMilliseconds + deltaMs);
                final maxEnd = Duration(milliseconds: (widget.durationSeconds * 1000).round());
                if (newEnd > maxEnd) newEnd = maxEnd;
                if (newEnd <= text.startTime) newEnd = text.startTime + const Duration(milliseconds: 100);
                
                widget.onTextTrimChanged?.call(text.id, text.startTime, newEnd);
                _previewTrimPosition(newEnd.inMilliseconds / 1000.0);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _trimmingTextId = null;
                  _textTrimInitialTime = null;
                });
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _trimmingTextId = null;
                  _textTrimInitialTime = null;
                });
              },
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryStart, // Yellow handle
                    borderRadius: BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  void _beginImageClipDrag(ImageOverlayModel image) {
    setState(() {
      _isDraggingImageClip = true;
      _draggingImageId = image.id;
      _imageDragInitialStart = image.startTime;
      _imageDragInitialEnd = image.endTime;
      _dragStartLaneIndex = image.laneIndex;
      _dragStartMaxLane = _maxLane;
    });
    if (widget.player.state.playing) {
      widget.player.pause();
    }
    widget.onImageTapped?.call(image.id);
  }

  void _moveImageClip(LongPressMoveUpdateDetails details) {
    if (!_isDraggingImageClip ||
        _draggingImageId == null ||
        _imageDragInitialStart == null ||
        _imageDragInitialEnd == null) {
      return;
    }

    final deltaMs =
        (details.offsetFromOrigin.dx / _pixelsPerSecond * 1000).round();
    final clipDurationMs =
        _imageDragInitialEnd!.inMilliseconds - _imageDragInitialStart!.inMilliseconds;
    final maxStartMs = ((widget.durationSeconds * 1000).round() - clipDurationMs)
        .clamp(0, double.infinity)
        .toInt();

    final proposedStartMs = (_imageDragInitialStart!.inMilliseconds + deltaMs)
        .clamp(0, maxStartMs)
        .toInt();
    final nextEndMs = proposedStartMs + clipDurationMs;

    final nextStart = Duration(milliseconds: proposedStartMs);
    final nextEnd = Duration(milliseconds: nextEndMs);

    final lanesMoved = -(details.offsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(0, min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved));

    widget.onImageTrimChanged?.call(_draggingImageId!, nextStart, nextEnd, newLaneIndex: newLaneIndex);
    _previewTrimPosition(nextStart.inMilliseconds / 1000.0);
  }

  void _endImageClipDrag() {
    setState(() {
      _isDraggingImageClip = false;
      _draggingImageId = null;
      _imageDragInitialStart = null;
      _imageDragInitialEnd = null;
    });
  }

  List<Widget> _buildImageTracks(int maxLane) {
    final widgets = <Widget>[];

    for (final image in widget.imageOverlays) {
      final double imageTrackTop = _timeRulerHeight + (maxLane - image.laneIndex) * _laneHeight + 4;
      final startPx = (image.startTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final endPx = (image.endTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0, double.infinity).toDouble();
      
      final isSelected = image.id == widget.selectedImageId;
      final isBeingDragged = _isDraggingImageClip && _draggingImageId == image.id;

      widgets.add(
        Positioned(
          top: isBeingDragged ? imageTrackTop - 3 : imageTrackTop,
          left: startPx,
          width: widthPx,
          height: isBeingDragged ? _laneHeight - 2 : _laneHeight - 8,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onImageTapped?.call(image.id),
            onLongPressStart: (_) => _beginImageClipDrag(image),
            onLongPressMoveUpdate: _moveImageClip,
            onLongPressEnd: (_) => _endImageClipDrag(),
            child: Container(
              decoration: BoxDecoration(
                color: isBeingDragged
                    ? Colors.teal
                    : isSelected
                        ? Colors.teal.shade400
                        : Colors.teal.shade400.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isBeingDragged
                      ? Colors.white
                      : isSelected
                          ? Colors.white
                          : Colors.transparent,
                  width: isBeingDragged ? 2 : 1.5,
                ),
                boxShadow: isBeingDragged
                    ? [
                        BoxShadow(
                          color: Colors.teal.withValues(alpha: 0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isBeingDragged) ...[
                      const Icon(Icons.drag_indicator, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                    ],
                    const Icon(Icons.image, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    const Flexible(
                      child: Text(
                        'Image',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (isSelected) {
        // Left trim handle
        widgets.add(
          Positioned(
            top: imageTrackTop,
            left: startPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _trimmingImageId = image.id;
                  _imageTrimInitialTime = image.startTime;
                  _imageTrimAccumulatedDelta = 0.0;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingImageId != image.id || _imageTrimInitialTime == null) return;
                
                _imageTrimAccumulatedDelta += details.delta.dx;
                final deltaMs = (_imageTrimAccumulatedDelta / _pixelsPerSecond * 1000).round();
                
                var newStart = Duration(milliseconds: _imageTrimInitialTime!.inMilliseconds + deltaMs);
                if (newStart < Duration.zero) newStart = Duration.zero;
                if (newStart >= image.endTime) newStart = image.endTime - const Duration(milliseconds: 100);
                
                widget.onImageTrimChanged?.call(image.id, newStart, image.endTime);
                _previewTrimPosition(newStart.inMilliseconds / 1000.0);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _trimmingImageId = null;
                  _imageTrimInitialTime = null;
                });
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _trimmingImageId = null;
                  _imageTrimInitialTime = null;
                });
              },
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryStart,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        );

        // Right trim handle
        widgets.add(
          Positioned(
            top: imageTrackTop,
            left: startPx + widthPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _trimmingImageId = image.id;
                  _imageTrimInitialTime = image.endTime;
                  _imageTrimAccumulatedDelta = 0.0;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingImageId != image.id || _imageTrimInitialTime == null) return;
                
                _imageTrimAccumulatedDelta += details.delta.dx;
                final deltaMs = (_imageTrimAccumulatedDelta / _pixelsPerSecond * 1000).round();
                
                var newEnd = Duration(milliseconds: _imageTrimInitialTime!.inMilliseconds + deltaMs);
                final maxEnd = Duration(milliseconds: (widget.durationSeconds * 1000).round());
                if (newEnd > maxEnd) newEnd = maxEnd;
                if (newEnd <= image.startTime) newEnd = image.startTime + const Duration(milliseconds: 100);
                
                widget.onImageTrimChanged?.call(image.id, image.startTime, newEnd);
                _previewTrimPosition(newEnd.inMilliseconds / 1000.0);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _trimmingImageId = null;
                  _imageTrimInitialTime = null;
                });
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _trimmingImageId = null;
                  _imageTrimInitialTime = null;
                });
              },
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryStart,
                    borderRadius: BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  void _beginVideoClipDrag(VideoOverlayModel video) {
    setState(() {
      _isDraggingVideoClip = true;
      _draggingVideoId = video.id;
      _videoDragInitialStart = video.timelineStart;
      _videoDragInitialEnd = video.timelineEnd;
      _dragStartLaneIndex = video.laneIndex;
      _dragStartMaxLane = _maxLane;
    });
    if (widget.player.state.playing) {
      widget.player.pause();
    }
    widget.onVideoTapped?.call(video.id);
  }

  void _moveVideoClip(LongPressMoveUpdateDetails details) {
    if (!_isDraggingVideoClip ||
        _draggingVideoId == null ||
        _videoDragInitialStart == null ||
        _videoDragInitialEnd == null) {
      return;
    }

    final deltaMs =
        (details.offsetFromOrigin.dx / _pixelsPerSecond * 1000).round();
    final clipDurationMs =
        _videoDragInitialEnd!.inMilliseconds - _videoDragInitialStart!.inMilliseconds;
    final maxStartMs = ((widget.durationSeconds * 1000).round() - clipDurationMs)
        .clamp(0, double.infinity)
        .toInt();

    final proposedStartMs = (_videoDragInitialStart!.inMilliseconds + deltaMs)
        .clamp(0, maxStartMs)
        .toInt();
    final nextEndMs = proposedStartMs + clipDurationMs;

    final nextStart = Duration(milliseconds: proposedStartMs);
    final nextEnd = Duration(milliseconds: nextEndMs);

    final lanesMoved = -(details.offsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(0, min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved));

    widget.onVideoTrimChanged?.call(_draggingVideoId!, nextStart, nextEnd, newLaneIndex: newLaneIndex);
    _previewTrimPosition(nextStart.inMilliseconds / 1000.0);
  }

  void _endVideoClipDrag() {
    setState(() {
      _isDraggingVideoClip = false;
      _draggingVideoId = null;
      _videoDragInitialStart = null;
      _videoDragInitialEnd = null;
    });
  }

  List<Widget> _buildVideoTracks(int maxLane) {
    final widgets = <Widget>[];

    for (final video in widget.videoOverlays) {
      final double videoTrackTop = _timeRulerHeight + (maxLane - video.laneIndex) * _laneHeight + 4;
      final startPx = (video.timelineStart.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final endPx = (video.timelineEnd.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0.0, double.infinity).toDouble();
      
      final isSelected = video.id == widget.selectedVideoId;
      final isBeingDragged = _isDraggingVideoClip && _draggingVideoId == video.id;

      widgets.add(
        Positioned(
          top: isBeingDragged ? videoTrackTop - 3 : videoTrackTop,
          left: startPx,
          width: widthPx,
          height: isBeingDragged ? _laneHeight - 2 : _laneHeight - 8,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onVideoTapped?.call(video.id),
            onLongPressStart: (_) => _beginVideoClipDrag(video),
            onLongPressMoveUpdate: _moveVideoClip,
            onLongPressEnd: (_) => _endVideoClipDrag(),
            child: Container(
              decoration: BoxDecoration(
                color: isBeingDragged
                    ? Colors.pink
                    : isSelected
                        ? Colors.pink.shade400
                        : Colors.pink.shade400.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isBeingDragged
                      ? Colors.white
                      : isSelected
                          ? Colors.white
                          : Colors.transparent,
                  width: isBeingDragged ? 2 : 1.5,
                ),
                boxShadow: isBeingDragged
                    ? [
                        BoxShadow(
                          color: Colors.pink.withValues(alpha: 0.45),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isBeingDragged) ...[
                      const Icon(Icons.drag_indicator, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                    ],
                    const Icon(LucideIcons.film, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    const Flexible(
                      child: Text(
                        'Video',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      if (isSelected) {
        // Left trim handle
        widgets.add(
          Positioned(
            top: videoTrackTop,
            left: startPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _trimmingVideoId = video.id;
                  _videoTrimInitialTime = video.timelineStart;
                  _videoTrimAccumulatedDelta = 0.0;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingVideoId != video.id || _videoTrimInitialTime == null) return;
                
                _videoTrimAccumulatedDelta += details.delta.dx;
                final deltaMs = (_videoTrimAccumulatedDelta / _pixelsPerSecond * 1000).round();
                
                var newStart = Duration(milliseconds: _videoTrimInitialTime!.inMilliseconds + deltaMs);
                if (newStart < Duration.zero) newStart = Duration.zero;
                if (newStart >= video.timelineEnd) newStart = video.timelineEnd - const Duration(milliseconds: 100);
                
                widget.onVideoTrimChanged?.call(video.id, newStart, video.timelineEnd);
                _previewTrimPosition(newStart.inMilliseconds / 1000.0);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _trimmingVideoId = null;
                  _videoTrimInitialTime = null;
                });
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _trimmingVideoId = null;
                  _videoTrimInitialTime = null;
                });
              },
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryStart,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(4), bottomLeft: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        );

        // Right trim handle
        widgets.add(
          Positioned(
            top: videoTrackTop,
            left: startPx + widthPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _trimmingVideoId = video.id;
                  _videoTrimInitialTime = video.timelineEnd;
                  _videoTrimAccumulatedDelta = 0.0;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (_trimmingVideoId != video.id || _videoTrimInitialTime == null) return;
                
                _videoTrimAccumulatedDelta += details.delta.dx;
                final deltaMs = (_videoTrimAccumulatedDelta / _pixelsPerSecond * 1000).round();
                
                var newEnd = Duration(milliseconds: _videoTrimInitialTime!.inMilliseconds + deltaMs);
                final maxEnd = Duration(milliseconds: (widget.durationSeconds * 1000).round());
                if (newEnd > maxEnd) newEnd = maxEnd;
                if (newEnd <= video.timelineStart) newEnd = video.timelineStart + const Duration(milliseconds: 100);
                
                widget.onVideoTrimChanged?.call(video.id, video.timelineStart, newEnd);
                _previewTrimPosition(newEnd.inMilliseconds / 1000.0);
              },
              onHorizontalDragEnd: (_) {
                setState(() {
                  _trimmingVideoId = null;
                  _videoTrimInitialTime = null;
                });
              },
              onHorizontalDragCancel: () {
                setState(() {
                  _trimmingVideoId = null;
                  _videoTrimInitialTime = null;
                });
              },
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryStart,
                    borderRadius: BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}

/// Paints the time ruler with tick marks and labels.
class _TimeRulerPainter extends CustomPainter {
  final double durationSeconds;
  final double pixelsPerSecond;
  final String Function(double) formatTime;

  _TimeRulerPainter({
    required this.durationSeconds,
    required this.pixelsPerSecond,
    required this.formatTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (durationSeconds <= 0) return;

    final tickPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;

    const textStyle = TextStyle(
      color: Colors.white38,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    // Determine a good interval for tick marks
    double interval;
    if (durationSeconds <= 10) {
      interval = 2;
    } else if (durationSeconds <= 30) {
      interval = 5;
    } else if (durationSeconds <= 120) {
      interval = 10;
    } else {
      interval = 20;
    }

    for (double t = 0; t <= durationSeconds; t += interval) {
      final x = t * pixelsPerSecond;
      // Tick mark
      canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), tickPaint);

      // Label
      final tp = TextPainter(
        text: TextSpan(text: formatTime(t), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, 0));
    }

    // Small ticks between major ones
    final smallInterval = interval / 4;
    final smallTickPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5;
    for (double t = 0; t <= durationSeconds; t += smallInterval) {
      final x = t * pixelsPerSecond;
      canvas.drawLine(Offset(x, size.height - 2), Offset(x, size.height), smallTickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true; // Make sure it repaints when duration changes
}

/// Paints a small downward-pointing triangle for the playhead indicator.
class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
