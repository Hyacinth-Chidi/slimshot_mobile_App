import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../../audio_tools/audio_tools_service.dart';
import '../../../audio_tools/extract_preview_player.dart';
import '../../../audio_tools/extract_selection.dart';
import '../../../audio_tools/same_file.dart';

/// What Done hands back: the whole sound, and the part of it the handles
/// enclose — the track's trim.
typedef ExtractChoice = ({ExtractedSound sound, ExtractSelection selection});

/// How much of the screen the sheet takes: the video, its waveform and the
/// handles want room, and nothing behind it is being judged.
const double kExtractSheetHeightFraction = 0.9;

/// Extract's sheet: the picked video playing, its sound's waveform between
/// two handles, **Change video** and **Done**.
///
/// The sound is taken out as the sheet opens; the handles then set the
/// track's trim without cutting the file. A sound the user did not keep —
/// the sheet closed, or another video chosen — is handed to [discardSound],
/// so nothing is left in the draft's folder for a track that does not exist.
class ExtractAudioSheet extends StatefulWidget {
  const ExtractAudioSheet({
    super.key,
    required this.initialVideoPath,
    required this.pickVideo,
    required this.extract,
    required this.peaks,
    required this.player,
    this.discardSound,
    this.isSameVideo,
  });

  final String initialVideoPath;

  /// Opens the gallery again; null when the user picked nothing.
  final Future<String?> Function() pickVideo;

  /// The video's sound in a file of its own, or null when it has none.
  final Future<ExtractedSound?> Function(String videoPath) extract;
  final Future<List<double>> Function(String soundPath) peaks;
  final ExtractPreviewPlayer player;
  final void Function(String soundPath)? discardSound;

  /// Whether a newly picked video is the one already open; [isSameFile] when
  /// not given. Picked again, a video keeps its sound and handles.
  final Future<bool> Function(String a, String b)? isSameVideo;

  @override
  State<ExtractAudioSheet> createState() => _ExtractAudioSheetState();
}

class _ExtractAudioSheetState extends State<ExtractAudioSheet> {
  late String _videoPath = widget.initialVideoPath;
  ExtractedSound? _sound;
  ExtractSelection? _selection;
  List<double>? _peaks;
  bool _loading = true;
  String? _problem;
  bool _kept = false;

  /// Bumped per video, so an answer for a video since replaced is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load(widget.initialVideoPath));
  }

  @override
  void dispose() {
    unawaited(widget.player.dispose());
    final sound = _sound;
    if (!_kept && sound != null) widget.discardSound?.call(sound.path);
    super.dispose();
  }

  Future<void> _load(String videoPath) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _problem = null;
      _sound = null;
      _selection = null;
      _peaks = null;
    });
    await widget.player.open(videoPath);

    ExtractedSound? sound;
    String? problem;
    try {
      sound = await widget.extract(videoPath);
      if (sound == null) problem = 'This video has no sound';
    } on AudioToolsException catch (e) {
      problem = e.message;
    } catch (_) {
      // The draft's folder could not be written, or anything else the
      // channel did not word: said, never a sheet that silently spins.
      problem = kExtractFailedMessage;
    }
    if (!mounted || generation != _generation) {
      if (sound != null) widget.discardSound?.call(sound.path);
      return;
    }
    setState(() {
      _loading = false;
      _problem = problem;
      _sound = sound;
      _selection = sound == null ? null : ExtractSelection.whole(sound.durationSeconds);
    });
    if (sound == null) return;
    unawaited(widget.player.playRange(0, sound.durationSeconds));

    final peaks = await widget.peaks(sound.path);
    if (!mounted || generation != _generation) return;
    setState(() => _peaks = peaks);
  }

  Future<void> _changeVideo() async {
    final path = await widget.pickVideo();
    if (path == null || !mounted) return;
    // The same video again — the gallery's fresh copy of it — keeps the sound
    // already taken out, and the handles where the user left them.
    final same = await (widget.isSameVideo ?? isSameFile)(_videoPath, path);
    if (same || !mounted) return;
    _videoPath = path;
    await widget.player.pause();
    final old = _sound;
    if (old != null) widget.discardSound?.call(old.path);
    _sound = null;
    await _load(path);
  }

  void _done() {
    final sound = _sound;
    final selection = _selection;
    if (sound == null || selection == null) return;
    _kept = true;
    Navigator.of(context).pop<ExtractChoice>((sound: sound, selection: selection));
  }

  void _select(ExtractSelection selection) => setState(() => _selection = selection);

  void _selectionSettled() {
    final selection = _selection;
    if (selection == null) return;
    unawaited(widget.player.playRange(selection.start, selection.end));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _sound != null && _selection != null;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * kExtractSheetHeightFraction,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _header(ready),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: widget.player.view(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(height: _kStripHeight, child: _strip()),
              const SizedBox(height: 8),
              _readout(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _changeVideo,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Change video'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool ready) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const ValueKey('extract-close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, color: AppColors.textSecondary, size: 20),
          ),
          TextButton(
            onPressed: ready ? _done : null,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryStart,
              disabledForegroundColor: AppColors.textTertiary,
            ),
            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _strip() {
    final problem = _problem;
    if (problem != null) {
      return Center(
        child: Text(problem, style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final sound = _sound;
    final selection = _selection;
    if (_loading || sound == null || selection == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryStart),
        ),
      );
    }
    return _TrimStrip(
      peaks: _peaks ?? const [],
      selection: selection,
      onChanged: _select,
      onSettled: _selectionSettled,
    );
  }

  Widget _readout() {
    final selection = _selection;
    final text = selection == null
        ? ''
        : '${_clock(selection.start)} – ${_clock(selection.end)}';
    return Text(
      text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
    );
  }

  static String _clock(double seconds) {
    final whole = seconds.floor();
    final tenths = ((seconds - whole) * 10).floor();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}.$tenths';
  }
}

const double _kStripHeight = 72;

/// Room either side of the waveform for the handles, which hang half past
/// its ends and could not be touched outside the strip.
const double _kStripInset = 16;
const double _kHandleTouch = 28;

/// The waveform with the selection lit and a handle at each end of it.
class _TrimStrip extends StatefulWidget {
  const _TrimStrip({
    required this.peaks,
    required this.selection,
    required this.onChanged,
    required this.onSettled,
  });

  final List<double> peaks;
  final ExtractSelection selection;
  final ValueChanged<ExtractSelection> onChanged;
  final VoidCallback onSettled;

  @override
  State<_TrimStrip> createState() => _TrimStripState();
}

class _TrimStripState extends State<_TrimStrip> {
  // A handle tracks an anchor, never a running sum of deltas: a delta the
  // clamp swallowed would leave the handle offset from the finger for good.
  double _anchorValue = 0;
  double _anchorX = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - _kStripInset * 2;
        final selection = widget.selection;
        final duration = selection.durationSeconds;
        double x(double seconds) =>
            duration <= 0 ? 0 : _kStripInset + seconds / duration * width;

        return Stack(
          children: [
            Positioned(
              left: _kStripInset,
              right: _kStripInset,
              top: 8,
              bottom: 8,
              child: CustomPaint(
                key: const ValueKey('extract-waveform'),
                painter: _WaveformPainter(
                  peaks: widget.peaks,
                  start: duration <= 0 ? 0 : selection.start / duration,
                  end: duration <= 0 ? 1 : selection.end / duration,
                ),
              ),
            ),
            _handle(
              key: const ValueKey('extract-handle-start'),
              centreX: x(selection.start),
              width: width,
              valueOf: () => selection.start,
              apply: (v) => widget.selection.withStart(v),
            ),
            _handle(
              key: const ValueKey('extract-handle-end'),
              centreX: x(selection.end),
              width: width,
              valueOf: () => selection.end,
              apply: (v) => widget.selection.withEnd(v),
            ),
          ],
        );
      },
    );
  }

  Widget _handle({
    required Key key,
    required double centreX,
    required double width,
    required double Function() valueOf,
    required ExtractSelection Function(double) apply,
  }) {
    final duration = widget.selection.durationSeconds;
    return Positioned(
      left: centreX - _kHandleTouch / 2,
      width: _kHandleTouch,
      top: 0,
      bottom: 0,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        // Anchored on pointer-down, so no travel is lost to the touch slop.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (details) {
          _anchorValue = valueOf();
          _anchorX = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          if (width <= 0) return;
          final moved = (details.globalPosition.dx - _anchorX) / width * duration;
          widget.onChanged(apply(_anchorValue + moved));
        },
        onHorizontalDragEnd: (_) => widget.onSettled(),
        child: Center(
          child: Container(
            width: 8,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Center(
              child: Container(width: 2, height: 16, color: AppColors.background),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.peaks, required this.start, required this.end});

  final List<double> peaks;

  /// The selection, as fractions of the strip.
  final double start;
  final double end;

  @override
  void paint(Canvas canvas, Size size) {
    final lit = Paint()..color = AppColors.primaryStart;
    final dim = Paint()..color = AppColors.border;
    final frame = Paint()
      ..color = AppColors.primaryStart
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final mid = size.height / 2;
    if (peaks.isEmpty) {
      canvas.drawRect(Rect.fromLTWH(0, mid - 1, size.width, 2), dim);
    } else {
      final step = size.width / peaks.length;
      final bar = (step * 0.6).clamp(1.0, 4.0);
      for (var i = 0; i < peaks.length; i++) {
        final centre = (i + 0.5) * step;
        final fraction = centre / size.width;
        final h = (peaks[i].clamp(0.0, 1.0) * (size.height - 4)).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(centre, mid), width: bar, height: h),
            const Radius.circular(1),
          ),
          fraction >= start && fraction <= end ? lit : dim,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTRB(start * size.width, 0, end * size.width, size.height),
      frame,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks != peaks || old.start != start || old.end != end;
}
