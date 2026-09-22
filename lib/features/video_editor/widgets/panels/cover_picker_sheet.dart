import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../../core/theme/lucide_icons.dart';

import '../../../../core/services/media_picker_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/toast_utils.dart';
import '../../logic/timeline/timeline_geometry.dart';
import '../../models/video_segment.dart';
import '../../services/video_thumbnail_service.dart';

/// Bottom sheet for choosing the project's cover.
///
/// Offers a scrubbable strip of frames drawn from the edit itself — resolved
/// with the same (path, time) mapping the filmstrip uses, so a trimmed,
/// sped-up or reversed clip offers exactly the frames it plays — plus an
/// import from the gallery. Pops with the chosen image's bytes; the caller
/// owns saving them.
class CoverPickerSheet extends StatefulWidget {
  const CoverPickerSheet({
    super.key,
    required this.segments,
    required this.assetPathFor,
    required this.aspectRatio,
  });

  final List<VideoSegment> segments;

  /// Original media path for a segment. A prepared proxy overrides it
  /// internally, the same way the filmstrip reads a reversed clip.
  final String Function(VideoSegment) assetPathFor;

  /// The project canvas shape, so the preview box matches the real cover.
  final double aspectRatio;

  @override
  State<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverFrame {
  const _CoverFrame(this.path, this.timeMs);

  final String path;
  final int timeMs;
}

class _CoverPickerSheetState extends State<CoverPickerSheet> {
  static const int _gridMs = 200;

  final VideoThumbnailService _thumbs = VideoThumbnailService.instance;

  late final double _duration = videoTimelineDuration(widget.segments);
  late final List<double> _starts = segmentTimelineStarts(widget.segments);

  double _selectedSeconds = 0.0;

  /// Strip frames for the current layout width. Rebuilt when the tile count
  /// changes, requested once, painted from [VideoThumbnailService.peek].
  List<_CoverFrame> _tiles = const [];

  /// A fresh, sheet-sized decode of the selected frame. While it is on its
  /// way the preview shows the 160px strip tile, so scrubbing never blanks.
  Uint8List? _previewBytes;
  int _previewGen = 0;

  bool _busy = false;

  /// The frame the edit shows at [timelineSeconds] — clip resolved through
  /// the shared timeline geometry, source instant through
  /// [VideoSegment.sourceAtOffset], and a prepared proxy read from its own
  /// zero in playback order, exactly like `ClipFilmstrip`.
  _CoverFrame _frameAt(double timelineSeconds) {
    final index = segmentIndexAt(timelineSeconds, widget.segments);
    final segment = widget.segments[index.clamp(0, widget.segments.length - 1)];
    final start = _starts.isEmpty ? 0.0 : _starts[index.clamp(0, _starts.length - 1)];
    final offset = (timelineSeconds - start).clamp(0.0, segment.duration).toDouble();

    final proxy = segment.overrideVideoPath;
    final seconds =
        proxy != null ? offset * segment.speed : segment.sourceAtOffset(offset);
    final ms = (seconds * 1000).round();
    return _CoverFrame(
      proxy ?? widget.assetPathFor(segment),
      (ms ~/ _gridMs) * _gridMs,
    );
  }

  void _ensureTiles(int count) {
    if (_tiles.length == count || _duration <= 0 || count <= 0) return;
    final tiles = <_CoverFrame>[
      for (var i = 0; i < count; i++)
        _frameAt(((i + 0.5) / count) * _duration),
    ];
    _tiles = tiles;

    // One request per source file, so a multi-asset timeline batches cleanly.
    final byPath = <String, List<int>>{};
    for (final tile in tiles) {
      byPath.putIfAbsent(tile.path, () => []).add(tile.timeMs);
    }
    for (final entry in byPath.entries) {
      unawaited(
        _thumbs.request(path: entry.key, timesMs: entry.value).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  void _scrubTo(double dx, double width) {
    if (_duration <= 0 || width <= 0) return;
    final t = ((dx / width) * _duration).clamp(0.0, _duration);
    if (t == _selectedSeconds) return;
    setState(() => _selectedSeconds = t);
    _loadPreview();
  }

  /// Fetches a sheet-sized decode of the selected frame, dropping any result
  /// that lands after the selection has already moved on.
  void _loadPreview() {
    final gen = ++_previewGen;
    final frame = _frameAt(_selectedSeconds);
    unawaited(
      _thumbs
          .frameAtSize(
            path: frame.path,
            timeMs: frame.timeMs,
            width: 480,
            height: 480,
          )
          .then((bytes) {
        if (!mounted || gen != _previewGen || bytes == null) return;
        setState(() => _previewBytes = bytes);
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.segments.isNotEmpty) _loadPreview();
  }

  Future<void> _useSelectedFrame() async {
    if (_busy || widget.segments.isEmpty) return;
    setState(() => _busy = true);

    final frame = _frameAt(_selectedSeconds);
    // Cover quality, decoded fresh; the strip's 160px tile is the fallback so
    // a frame the device can show is never refused as a cover.
    final bytes = await _thumbs.frameAtSize(
          path: frame.path,
          timeMs: frame.timeMs,
          width: 720,
          height: 720,
        ) ??
        _previewBytes ??
        _thumbs.peek(frame.path, frame.timeMs);

    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      ToastUtils.show(context, 'Could not read that frame', isError: true);
      return;
    }
    Navigator.of(context).pop(bytes);
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    try {
      final files = await MediaPickerService().pickImages();
      if (files.isEmpty || !mounted) return;
      final bytes = await files.first.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } catch (error) {
      if (!mounted) return;
      ToastUtils.show(
        context,
        MediaPickerService.isPermissionError(error)
            ? 'Photo access is needed to pick a cover'
            : 'Could not pick an image',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedFrame =
        widget.segments.isEmpty ? null : _frameAt(_selectedSeconds);
    final previewBytes = _previewBytes ??
        (selectedFrame == null
            ? null
            : _thumbs.peek(selectedFrame.path, selectedFrame.timeMs));

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Cover',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _useSelectedFrame,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryStart, AppColors.primaryEnd],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.check,
                                  size: 14, color: AppColors.textPrimary),
                              SizedBox(width: 6),
                              Text(
                                'Use',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // The chosen frame, in the project's own shape.
            SizedBox(
              height: 200,
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: Colors.black,
                      child: previewBytes != null
                          ? Image.memory(
                              previewBytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          : const Center(
                              child: Icon(
                                LucideIcons.image,
                                color: Colors.white24,
                                size: 24,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // The scrub strip: frames across the whole edit, indicator on the
            // chosen instant.
            if (widget.segments.isNotEmpty && _duration > 0)
              SizedBox(
                height: 48,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final count = (width / 48).round().clamp(4, 16);
                    _ensureTiles(count);
                    final fraction =
                        (_selectedSeconds / _duration).clamp(0.0, 1.0);

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _scrubTo(d.localPosition.dx, width),
                      onHorizontalDragStart: (d) =>
                          _scrubTo(d.localPosition.dx, width),
                      onHorizontalDragUpdate: (d) =>
                          _scrubTo(d.localPosition.dx, width),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Row(
                                children: [
                                  for (final tile in _tiles)
                                    Expanded(
                                      child: Builder(builder: (_) {
                                        final bytes = _thumbs.peek(
                                            tile.path, tile.timeMs);
                                        return bytes != null
                                            ? Image.memory(
                                                bytes,
                                                fit: BoxFit.cover,
                                                gaplessPlayback: true,
                                              )
                                            : Container(
                                                color: Colors.white10);
                                      }),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // The scrub indicator: a tile-sized viewfinder that
                          // slides with the finger, framing what will be the
                          // cover — a bare line read as a playhead, not a
                          // selection.
                          Builder(builder: (_) {
                            final tileWidth = width / count;
                            final left = (fraction * width - tileWidth / 2)
                                .clamp(0.0, width - tileWidth);
                            return Positioned(
                              top: 0,
                              bottom: 0,
                              left: left,
                              width: tileWidth,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.textPrimary,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.45),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),

            GestureDetector(
              onTap: _pickFromGallery,
              child: Container(
                height: 44,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.image,
                        size: 16, color: AppColors.textPrimary),
                    SizedBox(width: 8),
                    Text(
                      'Choose from gallery',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
