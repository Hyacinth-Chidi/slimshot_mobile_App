import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/video_segment.dart';
import '../../services/video_thumbnail_service.dart';

/// The filmstrip for a single clip.
///
/// Tiles are **timeline-indexed**: tile `k` covers a fixed slice of this clip's
/// span on the timeline, and the frame it shows is whatever the source holds at
/// that instant, resolved through [VideoSegment.sourceAtOffset] — the same
/// mapping playback uses. Trims, speed, reversal and transition overlaps
/// therefore stay aligned to the playhead for free.
///
/// The previous implementation laid one strip of evenly-spread frames across
/// the *source* duration and shifted it per clip by `sourceStart`. That is only
/// correct while timeline position happens to equal source position, so it
/// broke as soon as a transition overlapped two clips and pulled everything
/// after it earlier. It also stretched a fixed number of frames across the
/// whole strip, so one thumbnail could cover several seconds.
///
/// Each clip carries its own [sourcePath], so a timeline assembled from several
/// imported videos works without changes here.
class ClipFilmstrip extends StatefulWidget {
  const ClipFilmstrip({
    super.key,
    required this.segment,
    required this.sourcePath,
    required this.timelineStart,
    required this.pixelsPerSecond,
    required this.height,
    required this.visibleStartSeconds,
    required this.visibleEndSeconds,
    this.displaySeconds,
    this.isProxySource = false,
    this.tileWidth = 48.0,
  });

  /// How much of the clip the timeline actually shows, in seconds.
  ///
  /// Shorter than the clip's own duration when it transitions into the next
  /// one: the overlap belongs to both clips, and the timeline draws the seam
  /// where the incoming clip starts so the two boxes abut instead of stacking.
  /// Defaults to the whole clip.
  final double? displaySeconds;

  final VideoSegment segment;

  /// The file frames are read from — the original media, or a prepared proxy.
  final String sourcePath;

  /// True when [sourcePath] is a prepared proxy (a reversed clip, say) rather
  /// than the original. A proxy already contains exactly this clip's range in
  /// playback order, so frames are addressed from its own zero rather than
  /// through the clip's source range.
  final bool isProxySource;

  /// Where this clip begins on the timeline, already accounting for any
  /// transition overlap before it.
  final double timelineStart;

  final double pixelsPerSecond;
  final double height;
  final double tileWidth;

  /// Visible timeline window. Only tiles inside it (plus a margin) are
  /// fetched, so a long timeline does not decode frames nobody is looking at.
  final double visibleStartSeconds;
  final double visibleEndSeconds;

  @override
  State<ClipFilmstrip> createState() => _ClipFilmstripState();
}

class _ClipFilmstripState extends State<ClipFilmstrip> {
  final _thumbnails = VideoThumbnailService.instance;
  Timer? _debounce;

  /// Fetch a screen's worth beyond the viewport so scrolling reveals tiles that
  /// are already decoded rather than empty boxes that fill in late.
  static const double _prefetchMarginSeconds = 4.0;

  /// Source times are snapped to this grid before becoming cache keys. Dragging
  /// a trim handle shifts every tile's source time slightly; without snapping
  /// each frame of the drag would miss the cache and re-decode the whole strip.
  static const int _sourceQuantumMs = 200;

  @override
  void didUpdateWidget(covariant ClipFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibleStartSeconds != widget.visibleStartSeconds ||
        oldWidget.visibleEndSeconds != widget.visibleEndSeconds ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond ||
        oldWidget.timelineStart != widget.timelineStart ||
        oldWidget.displaySeconds != widget.displaySeconds ||
        oldWidget.segment != widget.segment) {
      _scheduleFetch();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleFetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  double get _tileSeconds =>
      (widget.tileWidth / widget.pixelsPerSecond).clamp(0.05, 60.0).toDouble();

  /// The span this strip covers — the visible part of the clip, not its whole
  /// duration, so tiles are never laid out past the seam.
  double get _spanSeconds {
    final span = widget.displaySeconds ?? widget.segment.duration;
    return span.clamp(0.0, widget.segment.duration).toDouble();
  }

  int get _tileCount => (_spanSeconds / _tileSeconds).ceil().clamp(1, 4000);

  /// Source time for tile [index], snapped to the cache grid.
  int _frameTimeMsFor(int index) {
    final secondsIntoClip = index * _tileSeconds;
    final seconds = widget.isProxySource
        // A proxy holds only this clip, already in playback order.
        ? secondsIntoClip * widget.segment.speed
        : widget.segment.sourceAtOffset(secondsIntoClip);
    final ms = (seconds * 1000).round();
    return (ms ~/ _sourceQuantumMs) * _sourceQuantumMs;
  }

  bool _isTileVisible(int index) {
    final start = widget.timelineStart + (index * _tileSeconds);
    return start >= widget.visibleStartSeconds - _prefetchMarginSeconds &&
        start <= widget.visibleEndSeconds + _prefetchMarginSeconds;
  }

  void _scheduleFetch() {
    // Scrolling and trim-dragging both change the window every frame; batch the
    // resulting requests instead of firing one per frame.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), _fetchVisible);
  }

  Future<void> _fetchVisible() async {
    if (!mounted) return;

    final wanted = <int>{};
    for (var index = 0; index < _tileCount; index++) {
      if (!_isTileVisible(index)) continue;
      final timeMs = _frameTimeMsFor(index);
      if (_thumbnails.isResolved(widget.sourcePath, timeMs)) continue;
      wanted.add(timeMs);
    }
    if (wanted.isEmpty) return;

    await _thumbnails.request(
      path: widget.sourcePath,
      timesMs: wanted.toList(growable: false),
      width: _requestWidth,
      height: _requestHeight,
    );

    if (mounted) setState(() {});
  }

  /// Decode a little above display size so tiles stay crisp on dense screens
  /// without holding full-resolution frames in memory.
  int get _requestWidth => (widget.tileWidth * 3).round();

  int get _requestHeight => (widget.height * 3).round();

  @override
  Widget build(BuildContext context) {
    final clipWidth = _spanSeconds * widget.pixelsPerSecond;
    final tileCount = _tileCount;

    return SizedBox(
      width: clipWidth,
      height: widget.height,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: ColoredBox(color: AppColors.surfaceLight.withValues(alpha: 0.35)),
            ),
            for (var index = 0; index < tileCount; index++)
              Positioned(
                left: index * widget.tileWidth,
                top: 0,
                height: widget.height,
                // The final tile is clamped so a clip whose duration is not a
                // whole number of tiles does not paint past its own edge.
                width: (clipWidth - (index * widget.tileWidth))
                    .clamp(0.0, widget.tileWidth)
                    .toDouble(),
                child: _buildTile(index),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(int index) {
    final bytes = _thumbnails.peek(widget.sourcePath, _frameTimeMsFor(index));
    if (bytes == null) {
      // Nothing yet, or the source could not produce this frame. Either way the
      // slot keeps its width so tiles never reflow as frames arrive.
      return const SizedBox.shrink();
    }

    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
  }
}
