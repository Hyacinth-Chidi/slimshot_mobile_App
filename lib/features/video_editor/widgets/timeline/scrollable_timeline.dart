import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../logic/timeline/timeline_geometry.dart';
import '../../logic/transitions/transition_catalog.dart';
import '../../models/media_asset.dart';
import '../../models/video_segment.dart';
import '../../models/text_overlay_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/video_overlay_model.dart';
import '../../models/audio_track_model.dart';
import '../../models/video_editor_state.dart';
import '../../providers/video_editor_notifier.dart';
import '../../services/video_thumbnail_service.dart';
import '../panels/cover_picker_sheet.dart';
import 'clip_filmstrip.dart';
import 'clip_keyframe_diamonds.dart';
import 'transition_marker.dart';
import '../panels/editor_sheet.dart';

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
          Rect.fromCenter(
            center: Offset(x + barWidth / 2, centerY),
            width: barWidth,
            height: barHeight,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Height of the track area, given the rows it holds.
///
/// With the toolbar showing it is **floored** at [kTimelineTrackFloor]: the
/// editor's canvas is `Expanded`, so any pixel the timeline does not claim the
/// canvas absorbs, and a sparse project used to collapse this area and balloon
/// the picture — CapCut keeps a workable track area and sizes the canvas from
/// what is left. Capped at [kTimelineTrackCap] so a busy project scrolls its
/// lanes rather than eating the canvas.
///
/// With a tool panel open ([compact]) the floor is **released** and the area
/// sizes to its content. The panel is taller than the toolbar it replaces, and
/// that difference has to come from somewhere: taking it from the timeline's
/// idle slack keeps the picture its size and the tracks where they were, where
/// taking it from the canvas — the old behaviour — shrank the picture and shoved
/// the timeline up by the panel's full height. Real rows are never given up;
/// a timeline already at its content height is unchanged.
double timelineTrackHeight({
  required double contentHeight,
  required bool compact,
}) {
  final natural = contentHeight + kTimelineTrackPadding;
  final floor = compact ? 0.0 : kTimelineTrackFloor;
  return natural.clamp(floor, kTimelineTrackCap).toDouble();
}

/// Vertical padding the track area adds around its rows.
const double kTimelineTrackPadding = 16.0;

/// Least height the track area keeps while the toolbar shows.
const double kTimelineTrackFloor = 190.0;

/// Most height the track area takes; lanes beyond it scroll.
const double kTimelineTrackCap = 250.0;

class ScrollableTimeline extends ConsumerStatefulWidget {
  /// Stops playback when a gesture takes over the timeline.
  ///
  /// A callback rather than a player: the timeline never needed to *drive* a
  /// player, only to stop one, and taking the engine's own pause path keeps
  /// that true whichever engine is playing.
  final VoidCallback onPausePlayback;

  /// True while a tool panel is open below the timeline.
  ///
  /// The track area then sizes to its content instead of holding its floor,
  /// so the panel's extra height over the toolbar comes out of idle track
  /// rows first and out of the canvas only if there are none to give. See
  /// [timelineTrackHeight].
  final bool compact;
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
  final void Function(
    String id,
    Duration start,
    Duration end, {
    int? newLaneIndex,
  })?
  onTextTrimChanged;

  final List<ImageOverlayModel> imageOverlays;
  final String? selectedImageId;
  final ValueChanged<String>? onImageTapped;
  final void Function(
    String id,
    Duration start,
    Duration end, {
    int? newLaneIndex,
  })?
  onImageTrimChanged;

  final List<VideoOverlayModel> videoOverlays;
  final String? selectedVideoId;
  final ValueChanged<String>? onVideoTapped;
  final void Function(
    String id,
    Duration start,
    Duration end, {
    int? newLaneIndex,
  })?
  onVideoTrimChanged;

  final List<AudioTrackModel> audioTracks;
  final String? selectedAudioId;
  final ValueChanged<String>? onAudioTapped;
  final void Function(String id, double newTimelineStart, {int? newLaneIndex})?
  onAudioDragChanged;
  final void Function(
    String id,
    double newTimelineStart,
    double newSourceStart,
    double newSourceEnd,
  )?
  onAudioTrimChanged;
  final ValueChanged<double>? onTimelinePositionChanged;
  final ValueChanged<String>? onTransitionTapped;
  final VoidCallback? onDragEnd;

  /// Fires when a trim handle is grabbed.
  ///
  /// Lets the editor hold off work that is far too expensive to repeat per
  /// drag frame — rebuilding the native timeline in particular — until the
  /// handle is released.
  final VoidCallback? onTrimDragStart;

  final VoidCallback? onTrimDragEnd;

  /// Fires when the timeline starts and stops being dragged under the playhead.
  ///
  /// A scrub produces a seek per gesture frame. The engine can coalesce those
  /// far more cheaply than it can serve them one at a time, but only if it
  /// knows a scrub is in progress.
  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  const ScrollableTimeline({
    super.key,
    required this.onPausePlayback,
    this.compact = false,
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
    this.onTransitionTapped,
    this.onDragEnd,
    this.onTrimDragStart,
    this.onTrimDragEnd,
    this.onScrubStart,
    this.onScrubEnd,
  });

  @override
  ConsumerState<ScrollableTimeline> createState() => _ScrollableTimelineState();
}

class _ScrollableTimelineState extends ConsumerState<ScrollableTimeline> {
  final ScrollController _scrollController = ScrollController();

  /// The lanes area's vertical scroll, tracked so the cover card overlay can
  /// stay glued to the filmstrip row when tall lane stacks scroll.
  final ScrollController _verticalScrollController = ScrollController();

  /// Window assumed visible before the scroll view has been laid out, so the
  /// opening filmstrip tiles are already being fetched on first paint.
  static const double _kInitialVisibleSeconds = 12.0;

  static const double _pixelsPerSecond = 50.0;
  static const double _filmstripHeight = 48.0; // Reduced to be more compact

  /// Width of the marker drawn where one clip is cut from the next.
  static const double _clipSeamWidth = 4.0;

  /// Effectively-unbounded upper limit for overlay drags and trims, in ms.
  ///
  /// Overlays and audio may extend past the video's end — the project then
  /// runs longer over the background — so their gestures have no ceiling.
  /// A day keeps the arithmetic in comfortable int range on every platform.
  static const int _kUnboundedMs = 24 * 60 * 60 * 1000;

  /// How close to the viewport edge a carried clip starts pulling the timeline.
  static const double _kReorderEdgeZonePx = 64.0;

  /// Fastest the timeline scrolls itself while a clip is held at the edge.
  static const double _kReorderAutoScrollPxPerTick = 12.0;

  /// How long the other clips take to slide out of the way.
  static const Duration _kReorderSettleDuration = Duration(milliseconds: 160);

  /// How far a carried clip lifts off the track, and how much it grows.
  static const double _kCarriedLiftPx = 6.0;
  static const double _kCarriedScale = 1.06;
  static const double _laneHeight = 32.0;
  static const double _handleWidth = 12.0; // Thinner handle
  static const double _handleTouchWidth =
      44.0; // Keep hit area large for easy grabbing

  /// Minimum length any trim can leave behind — the video clips' rule
  /// ([kMinClipDurationSeconds]) shared by every trimmable thing on the
  /// timeline, so there is one minimum instead of a different one per lane.
  static final Duration _kMinTrimDuration =
      Duration(milliseconds: (kMinClipDurationSeconds * 1000).round());
  static const double _timeRulerHeight = 20.0;
  static const int _textSnapThresholdMs = 200;

  /// Width of the lane-identity gutter drawn in the run-in before 00:00.
  static const double _laneGutterWidth = 72.0;

  /// Width of the project cover card in the run-in before 00:00.
  static const double _coverTileWidth = 44.0;

  /// Which trim handle is being held, so it can show it has been grabbed.
  _TrimHandle? _activeTrimHandle;

  /// Where the finger went down, and the trim value at that instant.
  ///
  /// A handle follows `anchorValue + (fingerX - anchorX)` rather than a running
  /// sum of per-frame deltas. A delta that gets dropped — because the range hit
  /// its minimum length, or the notifier clamped it against the clip's asset —
  /// would otherwise be lost for good, leaving the handle offset from the
  /// finger by however far it was pushed past the limit: dragging back then
  /// does nothing until the overshoot has been paid off.
  double _trimAnchorGlobalX = 0.0;
  double _trimAnchorValue = 0.0;

  // ── Clip reordering ──
  //
  // Picked up with a long press so it cannot be confused with a scrub (a
  // horizontal drag anywhere on the timeline) or with a trim (a horizontal drag
  // on a handle). While a clip is held the timeline stops scrolling with the
  // finger and drives itself instead, so a clip can be carried past the edge of
  // the viewport.

  /// Clip currently being carried, or null.
  String? _reorderingSegmentId;

  /// Its index in `widget.segments` when it was picked up.
  int _reorderFromIndex = -1;

  /// Where it would land if dropped now. Drives the preview layout.
  int _reorderToIndex = -1;

  /// Content-space x of the finger, and where inside the clip it grabbed.
  double _reorderPointerContentX = 0.0;
  double _reorderGrabOffsetPx = 0.0;

  /// Captured at pickup so the preview layout does not have to re-resolve
  /// transition overlaps on every frame of the drag — the widths tile the
  /// timeline exactly, so reusing them reproduces the layout the user grabbed.
  Map<String, double> _reorderWidthsPx = const {};

  /// Pointer and scroll positions at pickup, so finger movement and
  /// auto-scrolling can both be added to the grab point.
  double _reorderStartContentX = 0.0;
  double _reorderStartScrollOffset = 0.0;
  Timer? _reorderAutoScrollTimer;

  bool get _isReorderingClip => _reorderingSegmentId != null;

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
    // Through the shared geometry, never a sum: transitions overlap their
    // clips, so summing durations draws a timeline longer than playback.
    var lastEnd = videoTimelineDuration(widget.segments);
    for (final track in widget.audioTracks) {
      lastEnd = max(lastEnd, track.timelineEnd);
    }
    // Overlays count too: any of them may outlast the video, and the timeline
    // has to be scrollable out to wherever the last thing ends.
    for (final text in widget.textOverlays) {
      lastEnd = max(lastEnd, text.endTime.inMilliseconds / 1000.0);
    }
    for (final image in widget.imageOverlays) {
      lastEnd = max(lastEnd, image.endTime.inMilliseconds / 1000.0);
    }
    for (final video in widget.videoOverlays) {
      lastEnd = max(lastEnd, video.timelineEnd.inMilliseconds / 1000.0);
    }
    return lastEnd;
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

  @override
  void didUpdateWidget(covariant ScrollableTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inputPath != widget.inputPath) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }

    if (oldWidget.timelinePositionSeconds != widget.timelinePositionSeconds) {
      _syncScrollToTimelinePosition(widget.timelinePositionSeconds);
    }
  }

  @override
  void dispose() {
    _reorderAutoScrollTimer?.cancel();
    _scrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _syncScrollToTimelinePosition(double timelinePosition) {
    // A carried clip owns the scroll position; letting the playhead pull it
    // back would fight the drag.
    if (_isUserScrolling ||
        _isDraggingTrimHandle ||
        _isDraggingTextClip ||
        _isReorderingClip) {
      return;
    }
    if (_scrollController.hasClients) {
      final targetOffset = timelinePosition * _pixelsPerSecond;
      final nextOffset = targetOffset
          .clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          )
          .toDouble();

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

  /// Timeline window currently on screen, in seconds.
  ///
  /// Content is padded by half a screen on each side so the playhead sits in
  /// the middle, which means scroll offset `x` puts timeline time
  /// `(x - halfWidth) / pixelsPerSecond` at the left edge of the viewport.
  /// Filmstrips use this to fetch only the frames the user can actually see.
  double get _visibleStartSeconds {
    if (!_scrollController.hasClients) return 0.0;
    final halfViewport = _scrollController.position.viewportDimension / 2;
    return ((_scrollController.offset - halfViewport) / _pixelsPerSecond)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  double get _visibleEndSeconds {
    if (!_scrollController.hasClients) {
      // Before first layout, cover a screenful so the opening frames load.
      return _kInitialVisibleSeconds;
    }
    final halfViewport = _scrollController.position.viewportDimension / 2;
    return (_scrollController.offset + halfViewport) / _pixelsPerSecond;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Only handle horizontal scrolling for the timeline position
    if (notification.metrics.axis != Axis.horizontal) {
      return false;
    }

    // A reorder drives the scroll itself when a clip is carried to the edge, so
    // those movements must not be read as the user scrubbing.
    if (_isAutoScrolling ||
        _isDraggingTrimHandle ||
        _isDraggingTextClip ||
        _isReorderingClip) {
      return false;
    }

    if (notification is ScrollStartNotification) {
      _isUserScrolling = true;
      widget.onScrubStart?.call();
      widget.onPausePlayback();
    } else if (notification is ScrollUpdateNotification) {
      final timelineSeconds = (notification.metrics.pixels / _pixelsPerSecond)
          .clamp(0.0, _totalEditedDuration)
          .toDouble();
      // The engine follows the reported position; the timeline itself never
      // seeks anything.
      widget.onTimelinePositionChanged?.call(timelineSeconds);
    } else if (notification is ScrollEndNotification) {
      final wasUser = _isUserScrolling;
      _isUserScrolling = false;
      widget.onScrubEnd?.call();
      if (wasUser) _snapScrubRelease();
    }
    return true;
  }

  /// A released scrub within [kSnapTolerancePx] of a clip seam glides onto it.
  ///
  /// **On release, not during the drag.** The playhead is fixed and the content
  /// scrolls under it, so snapping the *reported* position mid-drag would put
  /// the marker a few pixels off the seam it claimed to be on; sticking the
  /// scroll itself mid-drag fights the finger. A short glide after the finger
  /// lifts is what feels magnetic without either. The glide scrolls through the
  /// same notifications a finger does, so the engine follows it the same way.
  void _snapScrubRelease() {
    if (!_scrollController.hasClients) return;
    final pixels = _scrollController.offset;
    final seconds = pixels / _pixelsPerSecond;
    final snapped = snapToNearest(
      seconds,
      clipBoundaryTimes(widget.segments),
      kSnapTolerancePx / _pixelsPerSecond,
    );
    if (snapped == seconds) return;
    HapticFeedback.selectionClick();
    _scrollController.animateTo(
      snapped * _pixelsPerSecond,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _updateTrim(double newStart, double newEnd) {
    // Deliberately not clamped to `widget.durationSeconds`: that is the *first
    // asset's* length, which says nothing about the clip being trimmed. On a
    // photo project it is zero — a photo has no source duration — so clamping
    // to it collapsed every drag to an empty range and the handles did
    // nothing at all. `VideoEditorNotifier.setTrimRange` clamps against the
    // clip's own asset, which is the only correct bound.
    if (newStart < 0) newStart = 0;
    if (newEnd - newStart < kMinClipDurationSeconds) return;
    widget.onTrimChanged?.call(RangeValues(newStart, newEnd));
  }

  /// Where a trim handle currently sits, for a live preview of that frame.
  ///
  /// Intentionally does nothing today. It drove a `media_kit` seek per drag
  /// frame, which the native engine made pointless — that player's output was
  /// no longer on screen, so each seek bought nothing and cost a decoder
  /// flush on the device already serving the drag. The call sites remain
  /// because the *feature* is still wanted: the engine should show the frame
  /// under the handle, through its own coalescing scrub path rather than a
  /// second seek channel.
  // ignore: avoid_unused_constructor_parameters
  void _previewTrimPosition(double sourceSeconds) {}

  void _beginTrimDrag(_TrimHandle handle, double globalX) {
    _isDraggingTrimHandle = true;
    _trimAnchorGlobalX = globalX;
    _trimAnchorValue = handle == _TrimHandle.start
        ? widget.trimRange.start
        : widget.trimRange.end;

    widget.onPausePlayback();
    HapticFeedback.selectionClick();
    setState(() => _activeTrimHandle = handle);
    widget.onTrimDragStart?.call();
  }

  void _dragTrimHandle(double globalX) {
    final handle = _activeTrimHandle;
    if (handle == null) return;

    // Absolute, from the anchor — see [_trimAnchorGlobalX].
    final free =
        _trimAnchorValue + (globalX - _trimAnchorGlobalX) / _pixelsPerSecond;
    // Pulled onto the playhead when it is inside this clip and within
    // [kSnapTolerancePx]: trimming *to the frame you are looking at* is the
    // common intent, and it is otherwise a frame or two off every time. The
    // playhead is timeline seconds; the trim is source seconds; the tolerance
    // is pixels — converted here, with the clip's speed, so the pull feels the
    // same on a sped clip.
    final next = _snapTrimToPlayhead(free);

    // Clamped to the shortest allowed clip here, rather than left for
    // `_updateTrim` to reject: a rejected update leaves the handle wherever the
    // last accepted frame put it, which on a fast drag is short of the limit
    // and looks like the handle gave up early. Clamping walks it right up to
    // the limit and holds it there.
    final double target;
    if (handle == _TrimHandle.start) {
      final maxStart =
          max(0.0, widget.trimRange.end - kMinClipDurationSeconds);
      target = next.clamp(0.0, maxStart).toDouble();
      _updateTrim(target, widget.trimRange.end);
    } else {
      final minEnd = widget.trimRange.start + kMinClipDurationSeconds;
      target = max(next, minEnd);
      _updateTrim(widget.trimRange.start, target);
    }
    _previewTrimPosition(target);
  }

  /// Whether the current trim frame is held on the playhead, so the tick fires
  /// once on arrival rather than on every frame spent there.
  bool _trimSnapped = false;

  double _snapTrimToPlayhead(double sourceSeconds) {
    final segments = widget.segments;
    final selectedIndex = segments.indexWhere((s) => s.id == widget.selectedSegmentId);
    if (selectedIndex < 0) return sourceSeconds;
    final playhead = widget.timelinePositionSeconds;
    if (segmentIndexAt(playhead, segments) != selectedIndex) {
      _trimSnapped = false;
      return sourceSeconds;
    }
    final segment = segments[selectedIndex];
    final playheadSource = timelineTimeToSourceTime(playhead, segments);
    final tolerance = kSnapTolerancePx / _pixelsPerSecond * segment.speed;
    final snapped = snapToNearest(sourceSeconds, [playheadSource], tolerance);
    final nowSnapped = snapped != sourceSeconds;
    if (nowSnapped && !_trimSnapped) HapticFeedback.selectionClick();
    _trimSnapped = nowSnapped;
    return snapped;
  }

  void _endTrimDrag() {
    _trimSnapped = false;
    if (!_isDraggingTrimHandle) return;
    _isDraggingTrimHandle = false;
    setState(() => _activeTrimHandle = null);
    widget.onTrimDragEnd?.call();
    widget.onDragEnd?.call();
  }

  /// One end of the selected clip, as a grab handle.
  ///
  /// The grip widens and brightens while held. Without that there is nothing to
  /// confirm the handle was caught, so a drag that has not moved far enough to
  /// change the trim yet reads as the handle having missed the touch.
  Widget _buildTrimHandle(_TrimHandle handle) {
    final isHeld = _activeTrimHandle == handle;

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: _trimHandleGestures(handle),
      child: SizedBox(
        width: _handleTouchWidth,
        child: Align(
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            width: isHeld ? _handleWidth + 4 : _handleWidth,
            decoration: BoxDecoration(
              color: isHeld
                  ? AppColors.textPrimary
                  : AppColors.primaryStart,
              boxShadow: isHeld
                  ? [
                      BoxShadow(
                        color: AppColors.primaryStart.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              // The same grip on both ends — a chevron implied a direction
              // the drag does not have.
              child: Container(
                width: 2.5,
                height: 14,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Gesture wiring shared by both trim handles.
  Map<Type, GestureRecognizerFactory> _trimHandleGestures(_TrimHandle handle) {
    return <Type, GestureRecognizerFactory>{
      _ImmediateHorizontalDragRecognizer:
          GestureRecognizerFactoryWithHandlers<
              _ImmediateHorizontalDragRecognizer>(
        () => _ImmediateHorizontalDragRecognizer(debugOwner: this),
        (instance) {
          instance.onStart =
              (details) => _beginTrimDrag(handle, details.globalPosition.dx);
          instance.onUpdate =
              (details) => _dragTrimHandle(details.globalPosition.dx);
          instance.onEnd = (_) => _endTrimDrag();
          instance.onCancel = _endTrimDrag;
        },
      ),
    };
  }

  /// Which lane trim handle (audio/overlay) is currently held, as a
  /// `'<kind>:<id>:<edge>'` key, so exactly that handle lights up.
  String? _heldLaneHandleKey;

  /// A lane trim handle that wins the gesture arena on touch-down and lights
  /// up while held.
  ///
  /// A plain [GestureDetector] waits out `kTouchSlop` (~18px) before its drag
  /// beats the scrolling timeline — a third of a second of trim at 50px/s
  /// swallowed before anything moves, so the handle read as having missed the
  /// touch. Same fix as the clip trim handles: claim the pointer immediately.
  /// The held highlight is the confirmation the grab landed; without it a
  /// drag that has not moved far enough to change anything looks like a miss.
  Widget _laneTrimHandle({
    required String handleKey,
    required GestureDragStartCallback onStart,
    required GestureDragUpdateCallback onUpdate,
    required VoidCallback onEnd,
    required Widget Function(bool isHeld) visual,
  }) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _ImmediateHorizontalDragRecognizer:
            GestureRecognizerFactoryWithHandlers<
                _ImmediateHorizontalDragRecognizer>(
          () => _ImmediateHorizontalDragRecognizer(debugOwner: this),
          (instance) {
            instance.onStart = (details) {
              setState(() => _heldLaneHandleKey = handleKey);
              onStart(details);
            };
            instance.onUpdate = onUpdate;
            instance.onEnd = (_) {
              setState(() => _heldLaneHandleKey = null);
              onEnd();
            };
            instance.onCancel = () {
              setState(() => _heldLaneHandleKey = null);
              onEnd();
            };
          },
        ),
      },
      child: visual(_heldLaneHandleKey == handleKey),
    );
  }

  /// The audio lane's handle block: full-height colour with a centred grip
  /// bar — the same bar on both ends, because a chevron implied a direction
  /// the drag does not have.
  Widget _audioHandleVisual(bool isHeld) {
    return Container(
      color: isHeld ? AppColors.textPrimary : AppColors.primaryStart,
      child: Center(
        child: Container(width: 2.5, height: 14, color: Colors.black),
      ),
    );
  }

  /// The overlay lanes' slim handle: a centred bar that widens and brightens
  /// while held, like the clip trim handles.
  Widget _overlayHandleVisual(bool isHeld) {
    return Align(
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        width: isHeld ? 12 : 8,
        color: isHeld ? AppColors.textPrimary : AppColors.primaryStart,
      ),
    );
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
    widget.onPausePlayback();
    widget.onTextTapped?.call(text.id);
  }

  int _applyTextSnap(int proposedStartMs, int maxStartMs) {
    int snappedStartMs = proposedStartMs;
    int? snapGuideMs;

    final playheadMs = (widget.timelinePositionSeconds * 1000)
        .round()
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

    final deltaMs = (details.offsetFromOrigin.dx / _pixelsPerSecond * 1000)
        .round();
    final clipDurationMs =
        _textDragInitialEnd!.inMilliseconds -
        _textDragInitialStart!.inMilliseconds;
    // No upper bound: an overlay may be dragged past the video's end and the
    // project simply runs longer, matching audio. The old ceiling was also
    // computed from `durationSeconds` — the *first asset's* length.
    const maxStartMs = _kUnboundedMs;

    final proposedStartMs = (_textDragInitialStart!.inMilliseconds + deltaMs)
        .clamp(0, maxStartMs)
        .toInt();
    final nextStartMs = _applyTextSnap(proposedStartMs, maxStartMs);
    final nextEndMs = nextStartMs + clipDurationMs;

    final nextStart = Duration(milliseconds: nextStartMs);
    final nextEnd = Duration(milliseconds: nextEndMs);

    // Lanes stack *downward* (lane 0 nearest the filmstrip), so dragging down
    // is a higher lane index. The old negation came from the upward-growing
    // layout and made every vertical drag land on the opposite side.
    final lanesMoved = (details.offsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(
      0,
      min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved),
    );

    widget.onTextTrimChanged?.call(
      _draggingTextId!,
      nextStart,
      nextEnd,
      newLaneIndex: newLaneIndex,
    );
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

    final audio = widget.audioTracks.firstWhere(
      (a) => a.id == _draggingAudioId,
      orElse: () => widget.audioTracks.first,
    );
    if (audio.id != _draggingAudioId) return;

    final duration = audio.trimmedDuration;

    double nextStart = _audioDragInitialTimelineStart! + deltaSeconds;
    if (nextStart < 0) nextStart = 0;
    if (nextStart + duration > totalVideoDuration) {
      nextStart = totalVideoDuration - duration;
      if (nextStart < 0) nextStart = 0;
    }

    // Same downward lane order as the overlay movers: drag down = higher lane.
    final lanesMoved = (details.localOffsetFromOrigin.dy / _laneHeight)
        .round();
    final newLaneIndex = max(
      0,
      min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved),
    );

    widget.onAudioDragChanged?.call(
      _draggingAudioId!,
      nextStart,
      newLaneIndex: newLaneIndex,
    );
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
    widget.onPausePlayback();
  }

  void _updateAudioTrimStart(DragUpdateDetails details) {
    if (_trimmingAudioId == null ||
        _audioTrimInitialTimelineStart == null ||
        _audioTrimInitialSourceStart == null ||
        _audioTrimInitialSourceEnd == null)
      return;

    final audio = widget.audioTracks.firstWhere(
      (a) => a.id == _trimmingAudioId,
      orElse: () => widget.audioTracks.first,
    );
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
      newTimelineStart =
          _audioTrimInitialTimelineStart! +
          (newSourceStart - _audioTrimInitialSourceStart!);
    }

    widget.onAudioTrimChanged?.call(
      _trimmingAudioId!,
      newTimelineStart,
      newSourceStart,
      _audioTrimInitialSourceEnd!,
    );
    _previewTrimPosition(newTimelineStart);
  }

  void _updateAudioTrimEnd(DragUpdateDetails details) {
    if (_trimmingAudioId == null ||
        _audioTrimInitialTimelineStart == null ||
        _audioTrimInitialSourceStart == null ||
        _audioTrimInitialSourceEnd == null)
      return;

    final audio = widget.audioTracks.firstWhere(
      (a) => a.id == _trimmingAudioId,
      orElse: () => widget.audioTracks.first,
    );
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

    widget.onAudioTrimChanged?.call(
      _trimmingAudioId!,
      _audioTrimInitialTimelineStart!,
      _audioTrimInitialSourceStart!,
      newSourceEnd,
    );

    final newTimelineEnd =
        _audioTrimInitialTimelineStart! +
        (newSourceEnd - _audioTrimInitialSourceStart!);
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
    final ms = ((seconds - seconds.toInt()) * 100).toInt().toString().padLeft(
      2,
      '0',
    );
    return '$mins:$secs:$ms';
  }


  // ───────────────────────────── clip reordering ─────────────────────────────

  /// Where every clip box sits, in content pixels.
  ///
  /// One place decides this so the filmstrip, the selection border, the trim
  /// handles and the transition markers cannot disagree — during a reorder they
  /// all have to move together or the timeline comes apart in the user's hands.
  List<_ClipLayout> _clipLayouts() {
    final segments = widget.segments;
    if (segments.isEmpty) return const [];

    if (!_isReorderingClip) {
      final starts = segmentTimelineStarts(segments);
      final displays = segmentDisplayDurations(segments);
      return [
        for (var i = 0; i < segments.length; i++)
          _ClipLayout(
            segment: segments[i],
            index: i,
            leftPx: starts[i] * _pixelsPerSecond,
            widthPx: displays[i] * _pixelsPerSecond,
            timelineStart: starts[i],
            displaySeconds: displays[i],
            isDragged: false,
          ),
      ];
    }

    // Preview order: the carried clip lifted out and put back where it would
    // land. Widths are the ones captured at pickup — recomputing transition
    // overlaps for a hypothetical order every frame would be both expensive and
    // jumpy, and the real geometry is resolved on drop anyway.
    final order = [...segments];
    final from = order.indexWhere((s) => s.id == _reorderingSegmentId);
    if (from == -1) return _clipLayoutsUnordered(segments);
    final carried = order.removeAt(from);
    order.insert(_reorderToIndex.clamp(0, order.length), carried);

    final layouts = <_ClipLayout>[];
    var leftPx = 0.0;
    for (var i = 0; i < order.length; i++) {
      final segment = order[i];
      final widthPx = _reorderWidthsPx[segment.id] ?? 0.0;
      layouts.add(
        _ClipLayout(
          segment: segment,
          index: i,
          leftPx: leftPx,
          widthPx: widthPx,
          timelineStart: leftPx / _pixelsPerSecond,
          displaySeconds: widthPx / _pixelsPerSecond,
          isDragged: segment.id == _reorderingSegmentId,
        ),
      );
      leftPx += widthPx;
    }
    return layouts;
  }

  List<_ClipLayout> _clipLayoutsUnordered(List<VideoSegment> segments) {
    final starts = segmentTimelineStarts(segments);
    final displays = segmentDisplayDurations(segments);
    return [
      for (var i = 0; i < segments.length; i++)
        _ClipLayout(
          segment: segments[i],
          index: i,
          leftPx: starts[i] * _pixelsPerSecond,
          widthPx: displays[i] * _pixelsPerSecond,
          timelineStart: starts[i],
          displaySeconds: displays[i],
          isDragged: false,
        ),
    ];
  }

  /// Left edge of the carried clip as it follows the finger.
  double get _carriedLeftPx => _reorderPointerContentX - _reorderGrabOffsetPx;

  void _beginClipReorder(VideoSegment segment, double grabOffsetPx) {
    if (widget.segments.length < 2) return;

    final index = widget.segments.indexWhere((s) => s.id == segment.id);
    if (index == -1) return;

    final starts = segmentTimelineStarts(widget.segments);
    final displays = segmentDisplayDurations(widget.segments);

    setState(() {
      _reorderingSegmentId = segment.id;
      _reorderFromIndex = index;
      _reorderToIndex = index;
      _reorderGrabOffsetPx = grabOffsetPx;
      _reorderStartContentX = starts[index] * _pixelsPerSecond + grabOffsetPx;
      _reorderPointerContentX = _reorderStartContentX;
      _reorderStartScrollOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;
      _reorderWidthsPx = {
        for (var i = 0; i < widget.segments.length; i++)
          widget.segments[i].id: displays[i] * _pixelsPerSecond,
      };
    });

    HapticFeedback.mediumImpact();
    widget.onSegmentTapped?.call(segment.id);
    _reorderAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickReorderAutoScroll(),
    );
  }

  void _updateClipReorder(double fingerDx) {
    if (!_isReorderingClip) return;

    final scrolled = _scrollController.hasClients
        ? _scrollController.offset - _reorderStartScrollOffset
        : 0.0;
    _reorderPointerContentX = _reorderStartContentX + fingerDx + scrolled;
    _recomputeReorderTarget();
  }

  /// Chooses the slot the carried clip would drop into.
  ///
  /// Decided by where the carried clip's **centre** falls among the others,
  /// rather than by the finger: dragging a long clip by its left edge should
  /// not move it a slot before any of it overlaps the neighbour.
  void _recomputeReorderTarget() {
    final carriedWidth = _reorderWidthsPx[_reorderingSegmentId] ?? 0.0;
    final centre = _carriedLeftPx + carriedWidth / 2;

    final others = widget.segments
        .where((s) => s.id != _reorderingSegmentId)
        .toList(growable: false);

    var target = others.length;
    var cursor = 0.0;
    for (var i = 0; i < others.length; i++) {
      final width = _reorderWidthsPx[others[i].id] ?? 0.0;
      if (centre < cursor + width / 2) {
        target = i;
        break;
      }
      cursor += width;
    }

    if (target == _reorderToIndex) {
      setState(() {}); // the carried clip still has to follow the finger
      return;
    }

    setState(() => _reorderToIndex = target);
    HapticFeedback.selectionClick();
  }

  /// Carries the timeline along when the clip is held near an edge.
  void _tickReorderAutoScroll() {
    if (!_isReorderingClip || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final viewport = position.viewportDimension;
    final halfViewport = viewport / 2;
    // Content x → viewport x. Timeline zero sits half a screen in, because the
    // playhead is pinned to the middle.
    final pointerViewportX =
        halfViewport + _reorderPointerContentX - position.pixels;

    var delta = 0.0;
    if (pointerViewportX < _kReorderEdgeZonePx) {
      delta = -(_kReorderEdgeZonePx - pointerViewportX);
    } else if (pointerViewportX > viewport - _kReorderEdgeZonePx) {
      delta = pointerViewportX - (viewport - _kReorderEdgeZonePx);
    }
    if (delta == 0.0) return;

    final step = (delta / _kReorderEdgeZonePx * _kReorderAutoScrollPxPerTick)
        .clamp(-_kReorderAutoScrollPxPerTick, _kReorderAutoScrollPxPerTick);
    final next = (position.pixels + step)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next == position.pixels) return;

    _scrollController.jumpTo(next);
    // The finger has not moved but the content under it has.
    _reorderPointerContentX += next - position.pixels;
    _recomputeReorderTarget();
  }

  void _endClipReorder({required bool cancelled}) {
    if (!_isReorderingClip) return;

    _reorderAutoScrollTimer?.cancel();
    _reorderAutoScrollTimer = null;

    final from = _reorderFromIndex;
    final to = _reorderToIndex;

    setState(() {
      _reorderingSegmentId = null;
      _reorderFromIndex = -1;
      _reorderToIndex = -1;
      _reorderWidthsPx = const {};
    });

    if (cancelled || from < 0 || to < 0 || from == to) return;

    HapticFeedback.mediumImpact();
    ref.read(videoEditorProvider.notifier).reorderSegment(from, to);
  }

  List<Widget> _buildSegmentTracks(
    List<_ClipLayout> layouts,
    double topOffset,
  ) {
    final widgets = <Widget>[];
    final editorState = ref.read(videoEditorProvider);

    for (var i = 0; i < layouts.length; i++) {
      final layout = layouts[i];
      final segment = layout.segment;

      // Filmstrip chunk — each clip owns its own strip, indexed by timeline
      // time, so trims, speed, reversal and transition overlaps all stay
      // aligned to the playhead.
      final proxyPath = segment.overrideVideoPath;
      final hasProxy = proxyPath != null && proxyPath.isNotEmpty;
      // Each clip reads frames from its own imported file; a project can mix
      // several videos and photos, so there is no single source to fall back on
      // except for drafts that predate the asset pool.
      final assetPath =
          editorState.assetFor(segment)?.path ?? widget.inputPath;

      final filmstrip = ClipFilmstrip(
        key: ValueKey('filmstrip_${segment.id}'),
        segment: segment,
        sourcePath: hasProxy ? proxyPath : assetPath,
        isProxySource: hasProxy,
        // The carried copy is drawn on its own, always fully visible, so it is
        // given a strip that starts at zero and spans the whole clip. Tile
        // source times come from the clip's own offsets either way, so moving a
        // clip's preview position never re-decodes its frames.
        timelineStart: layout.isDragged ? 0.0 : layout.timelineStart,
        displaySeconds: layout.displaySeconds,
        pixelsPerSecond: _pixelsPerSecond,
        height: _filmstripHeight,
        visibleStartSeconds: layout.isDragged ? 0.0 : _visibleStartSeconds,
        visibleEndSeconds:
            layout.isDragged ? layout.displaySeconds : _visibleEndSeconds,
      );

      // The carried clip is drawn separately, on top and at the finger.
      if (layout.isDragged) continue;

      widgets.add(
        AnimatedPositioned(
          key: ValueKey('strip_slot_${segment.id}'),
          duration: _isReorderingClip ? _kReorderSettleDuration : Duration.zero,
          curve: Curves.easeOutCubic,
          top: topOffset,
          left: layout.leftPx,
          width: layout.widthPx,
          height: _filmstripHeight,
          child: filmstrip,
        ),
      );

      // The seam between this clip and the one before it.
      //
      // A cut has to be legible against whatever frames happen to sit either
      // side of it. The previous 2px of pure black was invisible on dark
      // footage, so a split looked like it had not happened; the pale edges
      // give it contrast on any frame.
      //
      // Only drawn for a hard cut. Where a transition spans the boundary the
      // clips genuinely blend, and the transition marker already sits on the
      // seam — drawing a cut there would claim something untrue.
      final previous = i > 0 ? layouts[i - 1].segment : null;
      final joinsPrevious =
          previous != null && EditorTransition.isSupported(previous.transitionType);
      if (previous != null && !joinsPrevious) {
        widgets.add(
          AnimatedPositioned(
            key: ValueKey('seam_${segment.id}'),
            duration: _isReorderingClip ? _kReorderSettleDuration : Duration.zero,
            curve: Curves.easeOutCubic,
            top: topOffset,
            left: layout.leftPx - _clipSeamWidth / 2,
            width: _clipSeamWidth,
            height: _filmstripHeight,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.symmetric(
                  vertical: BorderSide(color: AppColors.textPrimary, width: 1),
                ),
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  // ── Keyframe diamonds ─────────────────────────────────────────────────────
  //
  // **A diamond is an instant of a clip**, drawn on the clip's own thumbnail,
  // and every animatable property carries a keyframe at it. A clip with no
  // diamonds draws nothing and the timeline keeps exactly the height it had
  // before this feature — the row this replaced claimed 26px whenever it opened
  // and pushed every lane down.

  /// The layout of the clip diamonds are drawn on, or null.
  _ClipLayout? _keyframeClipLayout(
    List<_ClipLayout> layouts,
    VideoEditorState editorState,
  ) {
    final id = editorState.keyframeClipId;
    if (id == null) return null;
    for (final layout in layouts) {
      // Never over a clip being carried: its position is provisional, and a
      // diamond tap must not compete with the reorder.
      if (layout.segment.id == id && !layout.isDragged) return layout;
    }
    return null;
  }

  /// The clip under the finger, drawn lifted off the timeline.
  ///
  /// Deliberately the last thing painted and never animated: it has to track
  /// the finger exactly, so any easing here would read as lag.
  Widget? _buildCarriedClip(List<_ClipLayout> layouts, double topOffset) {
    if (!_isReorderingClip) return null;

    _ClipLayout? carried;
    for (final layout in layouts) {
      if (layout.isDragged) carried = layout;
    }
    if (carried == null) return null;

    final segment = carried.segment;
    final proxyPath = segment.overrideVideoPath;
    final hasProxy = proxyPath != null && proxyPath.isNotEmpty;
    final assetPath =
        ref.read(videoEditorProvider).assetFor(segment)?.path ?? widget.inputPath;

    return Positioned(
      top: topOffset - _kCarriedLiftPx,
      left: _carriedLeftPx,
      width: carried.widthPx,
      height: _filmstripHeight,
      child: IgnorePointer(
        child: Transform.scale(
          scale: _kCarriedScale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipFilmstrip(
                    key: ValueKey('carried_${segment.id}'),
                    segment: segment,
                    sourcePath: hasProxy ? proxyPath : assetPath,
                    isProxySource: hasProxy,
                    timelineStart: 0.0,
                    displaySeconds: carried.displaySeconds,
                    pixelsPerSecond: _pixelsPerSecond,
                    height: _filmstripHeight,
                    visibleStartSeconds: 0.0,
                    visibleEndSeconds: carried.displaySeconds,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primaryStart,
                        width: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSegmentBorders(
    List<_ClipLayout> layouts,
    double topOffset,
    VideoEditorState editorState,
  ) {
    final widgets = <Widget>[];

    for (int i = 0; i < layouts.length; i++) {
      final layout = layouts[i];
      final segment = layout.segment;
      final accumulatedPx = layout.leftPx;
      final segmentWidthPx = layout.widthPx;
      final isSelected = widget.selectedSegmentId == segment.id;
      final canReorder = widget.segments.length > 1;

      widgets.add(
        AnimatedPositioned(
          key: ValueKey('border_${segment.id}'),
          duration: _isReorderingClip ? _kReorderSettleDuration : Duration.zero,
          curve: Curves.easeOutCubic,
          top: topOffset,
          left: accumulatedPx,
          width: segmentWidthPx,
          height: _filmstripHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSegmentTapped?.call(segment.id),
            // Long press to pick a clip up, so reordering cannot be confused
            // with a scrub — which is a plain horizontal drag anywhere on the
            // timeline — or with a trim, which is a horizontal drag on a handle
            // sitting on this same box.
            onLongPressStart: canReorder
                ? (details) =>
                    _beginClipReorder(segment, details.localPosition.dx)
                : null,
            onLongPressMoveUpdate: canReorder
                ? (details) => _updateClipReorder(details.offsetFromOrigin.dx)
                : null,
            onLongPressEnd: canReorder
                ? (_) => _endClipReorder(cancelled: false)
                : null,
            onLongPressCancel: canReorder
                ? () => _endClipReorder(cancelled: true)
                : null,
            child: AnimatedOpacity(
              duration: _kReorderSettleDuration,
              // The clip left behind fades to a slot: the carried copy is the
              // one the user is looking at.
              opacity: layout.isDragged ? 0.0 : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryStart
                        : Colors.white.withValues(alpha: 0.18),
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // The gap the carried clip would drop into, so the landing place is
      // obvious before the finger is lifted.
      if (layout.isDragged) {
        widgets.add(
          AnimatedPositioned(
            key: ValueKey('drop_slot_${segment.id}'),
            duration: _kReorderSettleDuration,
            curve: Curves.easeOutCubic,
            top: topOffset,
            left: accumulatedPx,
            width: segmentWidthPx,
            height: _filmstripHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.14),
                  border: Border.all(
                    color: AppColors.primaryStart.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Add Transition Indicator between clips.
      //
      // Hidden while a clip is being carried: which clips meet at a seam is
      // exactly what is in flux, so a marker there would be pointing at a
      // boundary that does not exist yet.
      if (i < layouts.length - 1 && !_isReorderingClip) {
        final transitionType = segment.transitionType;
        final hasTransition = transitionType != null;
        final isTransitionSelected =
            editorState.selectedTransitionSegmentId == segment.id;

        widgets.add(
          Positioned(
            top: topOffset +
                _filmstripHeight / 2 -
                TransitionMarker.hitSize / 2,
            left: accumulatedPx +
                segmentWidthPx -
                TransitionMarker.hitSize / 2,
            width: TransitionMarker.hitSize,
            height: TransitionMarker.hitSize,
            child: TransitionMarker(
              hasTransition: hasTransition,
              isSelected: isTransitionSelected,
              onTap: () {
                // **Select, then tell the screen to open the sheet.**
                // `selectTransition` sets `currentMenuId: 'transition'`, whose
                // tool list is deliberately empty because the drawer replaces
                // it — so on its own the tap surfaced an empty submenu and
                // nothing else. The screen owns the sheet, because a widget
                // deep in the timeline should not be reaching for a modal.
                ref
                    .read(videoEditorProvider.notifier)
                    .selectTransition(segment.id);
                widget.onTransitionTapped?.call(segment.id);
              },
            ),
          ),
        );
      }

    }

    return widgets;
  }

  /// Lane identity, drawn in the empty run-in before 00:00.
  ///
  /// A vertical line marks the timeline's start, and to its left each lane
  /// shows one icon per kind of thing it holds — audio, text, sticker, video
  /// overlay — so a stack of thin lanes can be told apart at a glance. A lane
  /// holding several kinds shows several icons. It lives in the scrolling
  /// content deliberately: it is visible exactly when the start of the
  /// timeline is, the way CapCut's lane icons behave.
  List<Widget> _buildLaneGutter({
    required double lanesTop,
    required int maxLane,
    required double totalHeight,
  }) {
    final widgets = <Widget>[
      // The start line sits just before 00:00 so it can never cover frame one.
      Positioned(
        top: _timeRulerHeight,
        left: -2,
        width: 2,
        height: totalHeight - _timeRulerHeight,
        child: IgnorePointer(
          child: Container(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    ];

    for (var lane = 0; lane <= maxLane; lane++) {
      final icons = <IconData>[
        if (widget.audioTracks.any((a) => a.laneIndex == lane))
          LucideIcons.music,
        if (widget.textOverlays.any((t) => t.laneIndex == lane))
          LucideIcons.type,
        if (widget.imageOverlays.any((i) => i.laneIndex == lane))
          LucideIcons.image,
        if (widget.videoOverlays.any((v) => v.laneIndex == lane))
          LucideIcons.video,
      ];
      if (icons.isEmpty) continue;

      widgets.add(
        Positioned(
          top: lanesTop + lane * _laneHeight,
          left: -_laneGutterWidth,
          width: _laneGutterWidth - 8,
          height: _laneHeight,
          child: IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final icon in icons) ...[
                  Icon(icon, size: 12, color: Colors.white54),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  /// Cover-file existence, cached so the 30Hz playback rebuild does not stat
  /// the file every frame.
  String? _checkedCoverPath;
  bool _coverFileExists = false;

  bool _coverExists(String? path) {
    if (path == null) return false;
    if (path != _checkedCoverPath) {
      _checkedCoverPath = path;
      _coverFileExists = File(path).existsSync();
    }
    return _coverFileExists;
  }

  /// First frame of the edit, for the cover tile's default picture.
  Uint8List? _defaultCoverBytes(VideoEditorState editorState) {
    if (widget.segments.isEmpty) return null;
    final segment = widget.segments.first;
    final proxy = segment.overrideVideoPath;
    final path =
        proxy ?? editorState.assetFor(segment)?.path ?? widget.inputPath;
    final seconds = proxy != null ? 0.0 : segment.sourceAtOffset(0.0);
    final timeMs = ((seconds * 1000).round() ~/ 200) * 200;

    final bytes = VideoThumbnailService.instance.peek(path, timeMs);
    if (bytes == null &&
        !VideoThumbnailService.instance.isResolved(path, timeMs)) {
      unawaited(
        VideoThumbnailService.instance
            .request(path: path, timesMs: [timeMs]).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    return bytes;
  }

  /// The project cover card: the chosen cover (or the edit's first frame
  /// until one is chosen) under a translucent scrim with a pencil, opening
  /// the cover picker. The small radius is deliberate — it is the one rounded
  /// element on the timeline, which is what makes it read as a card rather
  /// than a clip.
  ///
  /// Positioned by the caller: it lives in the **outer** stack, tracked over
  /// the scroll offsets, not in the content stack. It sits before 00:00,
  /// outside the content's bounds, and Flutter paints such overflow but never
  /// hit-tests it — placed in the content the card showed perfectly while
  /// every tap fell through to nothing.
  Widget _coverTileBody(VideoEditorState editorState) {
    final coverPath = editorState.thumbnailPath;
    final hasCover = _coverExists(coverPath);

    Widget picture;
    if (hasCover) {
      picture = Image.file(
        File(coverPath!),
        fit: BoxFit.cover,
        cacheWidth: 132,
        gaplessPlayback: true,
      );
    } else {
      final bytes = _defaultCoverBytes(editorState);
      picture = bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
          : Container(color: Colors.white10);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showCoverPicker(editorState),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            picture,
            Container(color: Colors.black.withValues(alpha: 0.35)),
            const Center(
              child: Icon(LucideIcons.edit2, size: 13, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCoverPicker(VideoEditorState editorState) async {
    final segments = List<VideoSegment>.from(widget.segments);
    if (segments.isEmpty) return;

    final bytes = await showEditorSheet<Uint8List>(
      context,
      builder: (_) => CoverPickerSheet(
        segments: segments,
        assetPathFor: (segment) =>
            editorState.assetFor(segment)?.path ?? widget.inputPath,
        aspectRatio: editorState.projectAspectRatio,
      ),
    );
    if (bytes == null || !mounted) return;

    final saved =
        await ref.read(videoEditorProvider.notifier).setCoverImage(bytes);
    if (!mounted) return;
    ToastUtils.show(
      context,
      saved ? 'Cover updated' : 'Could not save the cover',
      isError: !saved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(videoEditorProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final halfWidth = screenWidth / 2;

    final contentWidth = _totalEditedDuration * _pixelsPerSecond;

    // Resolved once per frame: every clip-track widget positions itself from
    // this, so a reorder preview cannot leave the filmstrip, the border and the
    // trim handles disagreeing about where a clip is.
    final clipLayouts = _clipLayouts();

    double? trimStartPx;
    double? trimEndPx;

    if (widget.selectedSegmentId != null) {
      final starts = segmentTimelineStarts(widget.segments);
      final displays = segmentDisplayDurations(widget.segments);
      for (var i = 0; i < widget.segments.length; i++) {
        if (widget.segments[i].id != widget.selectedSegmentId) continue;

        // Handles sit on the clip's visible edges, which stop at the seam when
        // it transitions into the next clip.
        trimStartPx = starts[i] * _pixelsPerSecond;
        trimEndPx = (starts[i] + displays[i]) * _pixelsPerSecond;
        break;
      }
    }

    final trimWidthPx = (trimEndPx != null && trimStartPx != null)
        ? trimEndPx - trimStartPx
        : 0.0;
    final int maxLane = _maxLane;
    // The video track sits directly under the ruler and everything added —
    // overlays, audio — stacks *below* it, lane 0 nearest the video. The old
    // layout grew upwards, so each addition pushed the filmstrip further down
    // and the primary content kept moving under the user's finger.
    final double lanesHeight = (maxLane + 1) * _laneHeight;
    final double filmstripTop = _timeRulerHeight;

    // The keyframe row sits directly under the clip it belongs to, above the
    // overlay and audio lanes — it is part of that clip, not another track. It
    // claims height only while it exists, so a project that never asked for a
    // keyframe has exactly the timeline it had before this feature.
    // Diamonds are drawn *on* the filmstrip, so they claim no height of their
    // own and the lanes sit where they always did.
    final keyframeLayout = _keyframeClipLayout(clipLayouts, editorState);
    final double lanesTop = filmstripTop + _filmstripHeight;
    final double totalHeight = lanesTop + lanesHeight;

    // A floor as well as a cap: the editor's canvas is `Expanded`, so any
    // pixel the timeline does not claim the canvas absorbs. A simple project
    // used to collapse this area to its content and the canvas ballooned;
    // CapCut instead keeps a workable track area and sizes the canvas from
    // what is left.
    final double containerHeight = timelineTrackHeight(
      contentHeight: totalHeight,
      compact: widget.compact,
    );

    // The scroll content fills the whole track area. Sized to the lanes
    // alone, the empty space under them belonged to the container's
    // background — outside the scroll views — so a drag there scrubbed
    // nothing, and the timeline only responded on rows that held content.
    final double contentHeight = max(totalHeight, containerHeight - 16.0);

    return AnimatedContainer(
      // Animated on the editor's motion, so the release of slack on a tool
      // opening moves with the panel's own growth rather than snapping ahead
      // of it or trailing behind.
      duration: AppMotion.enter,
      curve: AppMotion.enterCurve,
      height: containerHeight, // padding handled by containerHeight
      color: AppColors.background, // match dark theme
      child: Stack(
        children: [
          // â”€â”€ Scrollable content â”€â”€
          SingleChildScrollView(
            controller: _verticalScrollController,
            scrollDirection: Axis.vertical,
            physics: const BouncingScrollPhysics(),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Container(
                  padding: EdgeInsets.only(
                    left: halfWidth,
                    right: halfWidth,
                    top: 8,
                    bottom: 8,
                  ),
                  child: SizedBox(
                    width: max(
                      contentWidth,
                      screenWidth,
                    ), // ensure minimum width to scroll
                    height: contentHeight,
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
                          ..._buildSegmentTracks(clipLayouts, filmstripTop),

                          // 3. Selection borders & tap targets
                          ..._buildSegmentBorders(
                            clipLayouts,
                            filmstripTop,
                            editorState,
                          ),

                          // 3b. The keyframe row, when one has been asked for.
                          //
                          // Inside the scrolling content, at ordinary content
                          // x, so it scrolls with its clip and is hit-tested
                          // normally — the run-in trap that forced the cover
                          // card into the outer stack applies only before
                          // 00:00, and a diamond is always at or after it.
                          if (keyframeLayout != null)
                            Positioned(
                              top: filmstripTop,
                              left: keyframeLayout.leftPx,
                              width: keyframeLayout.widthPx,
                              height: _filmstripHeight,
                              child: ClipKeyframeDiamonds(
                                key: ValueKey(
                                  'keyframe_diamonds_${keyframeLayout.segment.id}',
                                ),
                                segment: keyframeLayout.segment,
                                widthPx: keyframeLayout.widthPx,
                                height: _filmstripHeight,
                              ),
                            ),

                          ..._buildAudioTracks(lanesTop),

                          // 5. Text overlays track
                          ..._buildTextTracks(lanesTop),

                          // 6. Image overlays track
                          ..._buildImageTracks(lanesTop),

                          // 7. Video overlays track
                          ..._buildVideoTracks(lanesTop),

                          // 8. Lane gutter: the start line and per-lane
                          // identity icons in the run-in before 00:00.
                          // Decoration only (IgnorePointer): the interactive
                          // cover card lives in the outer stack, because
                          // overflow past the content bounds paints but is
                          // never hit-tested.
                          ..._buildLaneGutter(
                            lanesTop: lanesTop,
                            maxLane: maxLane,
                            totalHeight: totalHeight,
                          ),

                          if (_activeSnapGuideMs != null)
                            Positioned(
                              top: lanesTop + 2,
                              left:
                                  (_activeSnapGuideMs! / 1000.0) *
                                  _pixelsPerSecond,
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

                          // 4. Trim brackets & handles for selected segment.
                          // Hidden while a clip is carried: the handles belong
                          // to a clip whose position is provisional, and a
                          // trim gesture must not compete with the drag.
                          if (widget.selectedSegmentId != null &&
                              !_isReorderingClip &&
                              trimStartPx != null &&
                              trimEndPx != null) ...[
                            // Top and bottom borders for the selected segment
                            Positioned(
                              top: filmstripTop,
                              height: _filmstripHeight,
                              left: trimStartPx + _handleWidth,
                              width: (trimWidthPx - _handleWidth * 2)
                                  .clamp(0, double.infinity)
                                  .toDouble(),
                              child: IgnorePointer(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(
                                        color: AppColors.primaryStart,
                                        width: 2.5,
                                      ),
                                      bottom: BorderSide(
                                        color: AppColors.primaryStart,
                                        width: 2.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Left trim handle
                            Positioned(
                              top: filmstripTop,
                              height: _filmstripHeight,
                              left:
                                  trimStartPx -
                                  ((_handleTouchWidth - _handleWidth) / 2),
                              child: _buildTrimHandle(_TrimHandle.start),
                            ),

                            // Right trim handle
                            Positioned(
                              top: filmstripTop,
                              height: _filmstripHeight,
                              left:
                                  trimEndPx -
                                  _handleWidth -
                                  ((_handleTouchWidth - _handleWidth) / 2),
                              child: _buildTrimHandle(_TrimHandle.end),
                            ),
                          ],

                          // Last, so the clip being carried is above every
                          // other track and above the drop slot.
                          ?_buildCarriedClip(clipLayouts, filmstripTop),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // â”€â”€ Cover card, tracked over the scroll position â”€â”€
          // In the outer stack because it sits before 00:00: overflow past
          // the content stack's bounds paints but is never hit-tested, so
          // placed there the card was visible yet untappable.
          if (widget.segments.isNotEmpty)
            AnimatedBuilder(
              animation: Listenable.merge(
                [_scrollController, _verticalScrollController],
              ),
              builder: (context, _) {
                final scrolledX = _scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0;
                final scrolledY = _verticalScrollController.hasClients
                    ? _verticalScrollController.offset
                    : 0.0;
                // Content x=0 sits at screen `halfWidth - offset`; the card
                // ends 8px before it, aligned with the lane-icon gutter.
                final left =
                    halfWidth - scrolledX - _coverTileWidth - 8;
                final top = 8.0 + filmstripTop - scrolledY;
                return Stack(
                  children: [
                    Positioned(
                      top: top,
                      left: left,
                      width: _coverTileWidth,
                      height: _filmstripHeight,
                      child: _coverTileBody(editorState),
                    ),
                  ],
                );
              },
            ),

          // â”€â”€ Fixed center playhead â”€â”€
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
                  Expanded(child: Container(width: 1.5, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAudioTracks(double lanesTop) {
    final widgets = <Widget>[];

    for (int i = 0; i < widget.audioTracks.length; i++) {
      final audio = widget.audioTracks[i];
      final startPx = audio.timelineStart * _pixelsPerSecond;
      final endPx = audio.timelineEnd * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0, double.infinity).toDouble();

      final isSelected = audio.id == widget.selectedAudioId;
      final isBeingDragged =
          _isDraggingAudioClip && _draggingAudioId == audio.id;
      final double topOffset =
          lanesTop + audio.laneIndex * _laneHeight + 4;

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
                // The fill does not change with selection — swapping it for
                // opaque purpleAccent recoloured the body under the waveform,
                // which read as a second purple washing over the clip.
                // Selection is the border's job, like every other clip.
                color: isBeingDragged
                    ? Colors.purpleAccent.shade400
                    : Colors.purple.withValues(alpha: 0.5),
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
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          color: Colors.white.withValues(alpha: 0.3),
                          seed: audio.id.hashCode,
                        ),
                      ),
                    ),
                    Center(
                      child: isBeingDragged
                          ? const Icon(
                              Icons.drag_indicator,
                              color: Colors.white,
                              size: 14,
                            )
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
        // Left trim handle â€” overlap 4px into the clip body
        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx - 12,
            width: 16,
            height: _laneHeight - 8,
            child: _laneTrimHandle(
              handleKey: 'audio:${audio.id}:start',
              onStart: (_) => _beginAudioTrim(audio),
              onUpdate: _updateAudioTrimStart,
              onEnd: _endAudioTrim,
              visual: _audioHandleVisual,
            ),
          ),
        );

        // Right trim handle â€” overlap 4px into the clip body
        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx + widthPx - 4,
            width: 16,
            height: _laneHeight - 8,
            child: _laneTrimHandle(
              handleKey: 'audio:${audio.id}:end',
              onStart: (_) => _beginAudioTrim(audio),
              onUpdate: _updateAudioTrimEnd,
              onEnd: _endAudioTrim,
              visual: _audioHandleVisual,
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _buildTextTracks(double lanesTop) {
    final widgets = <Widget>[];

    for (final text in widget.textOverlays) {
      final startPx =
          (text.startTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final endPx = (text.endTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0, double.infinity).toDouble();

      final isSelected = text.id == widget.selectedTextId;
      final isBeingDragged = _isDraggingTextClip && _draggingTextId == text.id;
      final double topOffset =
          lanesTop + text.laneIndex * _laneHeight + 4; // 4px visual separation

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
                      const Icon(
                        Icons.drag_indicator,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        text.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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
            child: _laneTrimHandle(
              handleKey: 'text:${text.id}:start',
              onStart: (details) {
                setState(() {
                  _trimmingTextId = text.id;
                  _textTrimInitialTime = text.startTime;
                  _textTrimAccumulatedDelta = 0.0;
                });
              },
              onUpdate: (details) {
                if (_trimmingTextId != text.id || _textTrimInitialTime == null)
                  return;

                _textTrimAccumulatedDelta += details.delta.dx;
                final deltaMs =
                    (_textTrimAccumulatedDelta / _pixelsPerSecond * 1000)
                        .round();

                var newStart = Duration(
                  milliseconds: _textTrimInitialTime!.inMilliseconds + deltaMs,
                );
                if (newStart < Duration.zero) newStart = Duration.zero;
                if (newStart >= text.endTime)
                  newStart = text.endTime - _kMinTrimDuration;

                widget.onTextTrimChanged?.call(text.id, newStart, text.endTime);
                _previewTrimPosition(newStart.inMilliseconds / 1000.0);
              },
              onEnd: () {
                setState(() {
                  _trimmingTextId = null;
                  _textTrimInitialTime = null;
                });
              },
              visual: _overlayHandleVisual,
            ),
          ),
        );

        widgets.add(
          Positioned(
            top: topOffset,
            left: startPx + widthPx - (_handleTouchWidth / 2),
            width: _handleTouchWidth,
            height: _laneHeight - 8,
            child: _laneTrimHandle(
              handleKey: 'text:${text.id}:end',
              onStart: (details) {
                setState(() {
                  _trimmingTextId = text.id;
                  _textTrimInitialTime = text.endTime;
                  _textTrimAccumulatedDelta = 0.0;
                });
              },
              onUpdate: (details) {
                if (_trimmingTextId != text.id || _textTrimInitialTime == null)
                  return;

                _textTrimAccumulatedDelta += details.delta.dx;
                final deltaMs =
                    (_textTrimAccumulatedDelta / _pixelsPerSecond * 1000)
                        .round();

                var newEnd = Duration(
                  milliseconds: _textTrimInitialTime!.inMilliseconds + deltaMs,
                );
                // Unbounded above: overlays may outlast the video, like audio.
                const maxEnd = Duration(milliseconds: _kUnboundedMs);
                if (newEnd > maxEnd) newEnd = maxEnd;
                if (newEnd <= text.startTime)
                  newEnd = text.startTime + _kMinTrimDuration;

                widget.onTextTrimChanged?.call(text.id, text.startTime, newEnd);
                _previewTrimPosition(newEnd.inMilliseconds / 1000.0);
              },
              onEnd: () {
                setState(() {
                  _trimmingTextId = null;
                  _textTrimInitialTime = null;
                });
              },
              visual: _overlayHandleVisual,
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
    widget.onPausePlayback();
    widget.onImageTapped?.call(image.id);
  }

  void _moveImageClip(LongPressMoveUpdateDetails details) {
    if (!_isDraggingImageClip ||
        _draggingImageId == null ||
        _imageDragInitialStart == null ||
        _imageDragInitialEnd == null) {
      return;
    }

    final deltaMs = (details.offsetFromOrigin.dx / _pixelsPerSecond * 1000)
        .round();
    final clipDurationMs =
        _imageDragInitialEnd!.inMilliseconds -
        _imageDragInitialStart!.inMilliseconds;
    // No upper bound: an overlay may be dragged past the video's end and the
    // project simply runs longer, matching audio. The old ceiling was also
    // computed from `durationSeconds` — the *first asset's* length.
    const maxStartMs = _kUnboundedMs;

    final proposedStartMs = (_imageDragInitialStart!.inMilliseconds + deltaMs)
        .clamp(0, maxStartMs)
        .toInt();
    final nextEndMs = proposedStartMs + clipDurationMs;

    final nextStart = Duration(milliseconds: proposedStartMs);
    final nextEnd = Duration(milliseconds: nextEndMs);

    // Lanes stack *downward* (lane 0 nearest the filmstrip), so dragging down
    // is a higher lane index. The old negation came from the upward-growing
    // layout and made every vertical drag land on the opposite side.
    final lanesMoved = (details.offsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(
      0,
      min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved),
    );

    widget.onImageTrimChanged?.call(
      _draggingImageId!,
      nextStart,
      nextEnd,
      newLaneIndex: newLaneIndex,
    );
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

  List<Widget> _buildImageTracks(double lanesTop) {
    final widgets = <Widget>[];

    for (final image in widget.imageOverlays) {
      final double imageTrackTop =
          lanesTop + image.laneIndex * _laneHeight + 4;
      final startPx =
          (image.startTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final endPx = (image.endTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0, double.infinity).toDouble();

      final isSelected = image.id == widget.selectedImageId;
      final isBeingDragged =
          _isDraggingImageClip && _draggingImageId == image.id;

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
                      const Icon(
                        Icons.drag_indicator,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Icon(Icons.image, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    const Flexible(
                      child: Text(
                        'Image',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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
            child: _laneTrimHandle(
              handleKey: 'image:${image.id}:start',
              onStart: (details) {
                setState(() {
                  _trimmingImageId = image.id;
                  _imageTrimInitialTime = image.startTime;
                  _imageTrimAccumulatedDelta = 0.0;
                });
              },
              onUpdate: (details) {
                if (_trimmingImageId != image.id ||
                    _imageTrimInitialTime == null)
                  return;

                _imageTrimAccumulatedDelta += details.delta.dx;
                final deltaMs =
                    (_imageTrimAccumulatedDelta / _pixelsPerSecond * 1000)
                        .round();

                var newStart = Duration(
                  milliseconds: _imageTrimInitialTime!.inMilliseconds + deltaMs,
                );
                if (newStart < Duration.zero) newStart = Duration.zero;
                if (newStart >= image.endTime)
                  newStart = image.endTime - _kMinTrimDuration;

                widget.onImageTrimChanged?.call(
                  image.id,
                  newStart,
                  image.endTime,
                );
                _previewTrimPosition(newStart.inMilliseconds / 1000.0);
              },
              onEnd: () {
                setState(() {
                  _trimmingImageId = null;
                  _imageTrimInitialTime = null;
                });
              },
              visual: _overlayHandleVisual,
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
            child: _laneTrimHandle(
              handleKey: 'image:${image.id}:end',
              onStart: (details) {
                setState(() {
                  _trimmingImageId = image.id;
                  _imageTrimInitialTime = image.endTime;
                  _imageTrimAccumulatedDelta = 0.0;
                });
              },
              onUpdate: (details) {
                if (_trimmingImageId != image.id ||
                    _imageTrimInitialTime == null)
                  return;

                _imageTrimAccumulatedDelta += details.delta.dx;
                final deltaMs =
                    (_imageTrimAccumulatedDelta / _pixelsPerSecond * 1000)
                        .round();

                var newEnd = Duration(
                  milliseconds: _imageTrimInitialTime!.inMilliseconds + deltaMs,
                );
                // Unbounded above: overlays may outlast the video, like audio.
                const maxEnd = Duration(milliseconds: _kUnboundedMs);
                if (newEnd > maxEnd) newEnd = maxEnd;
                if (newEnd <= image.startTime)
                  newEnd = image.startTime + _kMinTrimDuration;

                widget.onImageTrimChanged?.call(
                  image.id,
                  image.startTime,
                  newEnd,
                );
                _previewTrimPosition(newEnd.inMilliseconds / 1000.0);
              },
              onEnd: () {
                setState(() {
                  _trimmingImageId = null;
                  _imageTrimInitialTime = null;
                });
              },
              visual: _overlayHandleVisual,
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
    widget.onPausePlayback();
    widget.onVideoTapped?.call(video.id);
  }

  void _moveVideoClip(LongPressMoveUpdateDetails details) {
    if (!_isDraggingVideoClip ||
        _draggingVideoId == null ||
        _videoDragInitialStart == null ||
        _videoDragInitialEnd == null) {
      return;
    }

    final deltaMs = (details.offsetFromOrigin.dx / _pixelsPerSecond * 1000)
        .round();
    final clipDurationMs =
        _videoDragInitialEnd!.inMilliseconds -
        _videoDragInitialStart!.inMilliseconds;
    // No upper bound: an overlay may be dragged past the video's end and the
    // project simply runs longer, matching audio. The old ceiling was also
    // computed from `durationSeconds` — the *first asset's* length.
    const maxStartMs = _kUnboundedMs;

    final proposedStartMs = (_videoDragInitialStart!.inMilliseconds + deltaMs)
        .clamp(0, maxStartMs)
        .toInt();
    final nextEndMs = proposedStartMs + clipDurationMs;

    final nextStart = Duration(milliseconds: proposedStartMs);
    final nextEnd = Duration(milliseconds: nextEndMs);

    // Lanes stack *downward* (lane 0 nearest the filmstrip), so dragging down
    // is a higher lane index. The old negation came from the upward-growing
    // layout and made every vertical drag land on the opposite side.
    final lanesMoved = (details.offsetFromOrigin.dy / _laneHeight).round();
    final newLaneIndex = max(
      0,
      min(_dragStartMaxLane, _dragStartLaneIndex + lanesMoved),
    );

    widget.onVideoTrimChanged?.call(
      _draggingVideoId!,
      nextStart,
      nextEnd,
      newLaneIndex: newLaneIndex,
    );
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

  List<Widget> _buildVideoTracks(double lanesTop) {
    final widgets = <Widget>[];

    for (final video in widget.videoOverlays) {
      final double videoTrackTop =
          lanesTop + video.laneIndex * _laneHeight + 4;
      final startPx =
          (video.timelineStart.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final endPx =
          (video.timelineEnd.inMilliseconds / 1000.0) * _pixelsPerSecond;
      final widthPx = (endPx - startPx).clamp(0.0, double.infinity).toDouble();

      final isSelected = video.id == widget.selectedVideoId;
      final isBeingDragged =
          _isDraggingVideoClip && _draggingVideoId == video.id;

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
                      const Icon(
                        Icons.drag_indicator,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                    ],
                    const Icon(LucideIcons.film, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    const Flexible(
                      child: Text(
                        'Video',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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
            child: _laneTrimHandle(
              handleKey: 'video:${video.id}:start',
              onStart: (details) {
                setState(() {
                  _trimmingVideoId = video.id;
                  _videoTrimInitialTime = video.timelineStart;
                  _videoTrimAccumulatedDelta = 0.0;
                });
              },
              onUpdate: (details) {
                if (_trimmingVideoId != video.id ||
                    _videoTrimInitialTime == null)
                  return;

                _videoTrimAccumulatedDelta += details.delta.dx;
                final deltaMs =
                    (_videoTrimAccumulatedDelta / _pixelsPerSecond * 1000)
                        .round();

                var newStart = Duration(
                  milliseconds: _videoTrimInitialTime!.inMilliseconds + deltaMs,
                );
                if (newStart < Duration.zero) newStart = Duration.zero;
                if (newStart >= video.timelineEnd)
                  newStart =
                      video.timelineEnd - _kMinTrimDuration;

                widget.onVideoTrimChanged?.call(
                  video.id,
                  newStart,
                  video.timelineEnd,
                );
                _previewTrimPosition(newStart.inMilliseconds / 1000.0);
              },
              onEnd: () {
                setState(() {
                  _trimmingVideoId = null;
                  _videoTrimInitialTime = null;
                });
              },
              visual: _overlayHandleVisual,
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
            child: _laneTrimHandle(
              handleKey: 'video:${video.id}:end',
              onStart: (details) {
                setState(() {
                  _trimmingVideoId = video.id;
                  _videoTrimInitialTime = video.timelineEnd;
                  _videoTrimAccumulatedDelta = 0.0;
                });
              },
              onUpdate: (details) {
                if (_trimmingVideoId != video.id ||
                    _videoTrimInitialTime == null)
                  return;

                _videoTrimAccumulatedDelta += details.delta.dx;
                final deltaMs =
                    (_videoTrimAccumulatedDelta / _pixelsPerSecond * 1000)
                        .round();

                var newEnd = Duration(
                  milliseconds: _videoTrimInitialTime!.inMilliseconds + deltaMs,
                );
                // Unbounded above: overlays may outlast the video, like audio.
                const maxEnd = Duration(milliseconds: _kUnboundedMs);
                if (newEnd > maxEnd) newEnd = maxEnd;
                if (newEnd <= video.timelineStart)
                  newEnd =
                      video.timelineStart + _kMinTrimDuration;

                widget.onVideoTrimChanged?.call(
                  video.id,
                  video.timelineStart,
                  newEnd,
                );
                _previewTrimPosition(newEnd.inMilliseconds / 1000.0);
              },
              onEnd: () {
                setState(() {
                  _trimmingVideoId = null;
                  _videoTrimInitialTime = null;
                });
              },
              visual: _overlayHandleVisual,
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
      canvas.drawLine(
        Offset(x, size.height - 4),
        Offset(x, size.height),
        tickPaint,
      );

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
      canvas.drawLine(
        Offset(x, size.height - 2),
        Offset(x, size.height),
        smallTickPaint,
      );
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

/// Where one clip box sits on the timeline, in content pixels.
///
/// During a reorder this is the *preview* position — where the clip would be if
/// the carried clip were dropped now — so the filmstrip, the border, the trim
/// handles and the transition markers all read the same source and move
/// together.
class _ClipLayout {
  const _ClipLayout({
    required this.segment,
    required this.index,
    required this.leftPx,
    required this.widthPx,
    required this.timelineStart,
    required this.displaySeconds,
    required this.isDragged,
  });

  final VideoSegment segment;

  /// Position in the previewed order, which is not the segment's index in
  /// `widget.segments` while a clip is being carried.
  final int index;

  final double leftPx;
  final double widthPx;
  final double timelineStart;
  final double displaySeconds;

  /// True for the clip under the finger — drawn lifted, and last.
  final bool isDragged;
}

/// Which end of the selected clip a trim gesture is holding.
enum _TrimHandle { start, end }

/// A horizontal drag that claims the pointer the moment it goes down.
///
/// Trim handles sit inside a horizontally scrolling timeline, so the handle and
/// the scroll view want the same gesture. Left to the normal arena neither wins
/// until the finger has travelled `kTouchSlop` — about 18 logical pixels, which
/// at 50 pixels per second is a third of a second of trim swallowed before the
/// handle moves at all. That is what makes a handle feel like it does not pick
/// up when touched: it ignores the start of the drag and then jumps.
///
/// Claiming on pointer-down makes the grab immediate, and
/// [DragStartBehavior.down] means the drag is measured from the touch itself,
/// so none of that travel is lost and the handle tracks the finger exactly.
class _ImmediateHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _ImmediateHorizontalDragRecognizer({super.debugOwner}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}
