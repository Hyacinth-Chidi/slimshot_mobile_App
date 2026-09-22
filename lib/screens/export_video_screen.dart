import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../core/theme/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/services/media_save_service.dart';
import '../core/services/ad_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../features/video_editor/models/media_asset.dart';
import '../features/video_editor/models/video_editor_state.dart';
import '../features/video_editor/services/native_timeline_preview_service.dart';

/// Renders the project and previews the result.
///
/// **There is one export path.** It was routed by capability while the native
/// engine could not draw everything — overlays, then text — and the legacy
/// `pro_video_editor` branch has been deleted now that it can. The screen
/// therefore takes the project state rather than the flattened parameters PVE
/// needed.
class ExportVideoScreen extends StatefulWidget {
  /// The project to render. Native export composes the timeline from it.
  final VideoEditorState exportState;

  final Size previewCanvasSize;
  final int targetHeight;
  final int targetFps;

  const ExportVideoScreen({
    super.key,
    required this.exportState,
    required this.previewCanvasSize,
    required this.targetHeight,
    required this.targetFps,
  });

  @override
  State<ExportVideoScreen> createState() => _ExportVideoScreenState();
}

class _ExportVideoScreenState extends State<ExportVideoScreen> {
  final _nativePreview = NativeTimelinePreviewService();
  StreamSubscription? _progressSub;
  double _progress = 0.0;
  bool _isExporting = true;
  String? _exportedVideoPath;
  VideoPlayerController? _playerController;

  @override
  void initState() {
    super.initState();
    _startExport();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _playerController?.dispose();
    super.dispose();
  }

  void _startExport() async {
    await _startNativeExport(widget.exportState);
  }

  /// Renders through the preview engine, so the file matches what was previewed.
  Future<void> _startNativeExport(VideoEditorState state) async {
    _progressSub = _nativePreview.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'exportProgress' && event.progress != null) {
        setState(() => _progress = event.progress!.clamp(0.0, 1.0));
      } else if (event.type == 'exportWarning' && event.message != null) {
        // A device that forced a compromise says so; a file that quietly
        // differs from the preview must never pass as a clean success.
        ToastUtils.show(context, event.message!, isWarning: true);
      }
    });

    try {
      final directory = await getTemporaryDirectory();
      final outputPath =
          '${directory.path}/slimshot_export_${DateTime.now().millisecondsSinceEpoch}.mp4';

      final result = await _nativePreview.exportVideo(
        state,
        outputPath: outputPath,
        previewCanvasSize: widget.previewCanvasSize,
        frameRate: widget.targetFps,
        targetShortSidePx: widget.targetHeight,
        // The Dart-side half of the same rule the `exportWarning` listener
        // above serves: a compromise decided before the platform call has no
        // event channel to arrive on, so it comes back through here and lands
        // in the same toast.
        onWarning: (message) {
          if (!mounted) return;
          ToastUtils.show(context, message, isWarning: true);
        },
      );

      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _progress = 1.0;
        _exportedVideoPath = result.outputPath;
      });
      _initExportedVideo(result.outputPath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ToastUtils.show(context, 'Export failed: $e', isError: true);
    }
  }

  void _initExportedVideo(String path) {
    _playerController = VideoPlayerController.file(File(path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _playerController?.setLooping(true);
        _playerController?.play();
      });
  }

  void _cancelExport() {
    // The engine deletes the partial file when it sees the flag; nothing is
    // awaited here because the screen is leaving either way.
    unawaited(_nativePreview.cancelExport());
    Navigator.pop(context);
  }

  Future<void> _saveVideo() async {
    if (_exportedVideoPath == null) return;
    
    AdService.showInterstitialAd(
      context,
      onAdDismissed: () async {
        if (!mounted) return;
        try {
          await MediaSaveService.saveOptimizedMediaToGallery(
            [_exportedVideoPath!],
            album: 'SlimShotAI',
          );
          if (mounted) ToastUtils.show(context, 'Saved to gallery!');
        } catch (e) {
          if (mounted) ToastUtils.show(context, 'Failed to save: $e', isError: true);
        }
      },
    );
  }

  void _shareVideo() {
    if (_exportedVideoPath == null) return;
    MediaSaveService.shareFiles([_exportedVideoPath!]);
  }

  /// Shape of the result preview box.
  ///
  /// The project canvas *is* the exported frame, so this is simply its ratio —
  /// it used to be reconstructed from the legacy crop parameters, which could
  /// disagree with what the renderer actually produced.
  double _resolveDisplayAspectRatio() {
    final ratio = widget.exportState.projectAspectRatio;
    return ratio > 0 ? ratio : kDefaultCanvasAspectRatio;
  }

  @override
  Widget build(BuildContext context) {
    final double displayAspectRatio = _resolveDisplayAspectRatio();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _progress),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, _) {
            return Column(
              children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: AppColors.textPrimary, size: 28),
                    onPressed: () {
                      if (_isExporting) {
                        _cancelExport();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Text Header
            if (_isExporting) ...[
              Text(
                '${(animatedProgress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40.0),
                child: Text(
                  "Please don't close the app or lock your screen.\nYou can choose where to share your video next.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'Export Complete!',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 28),
            ],

            const Spacer(),

            // Video Preview Container
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                ),
                child: AspectRatio(
                  aspectRatio: displayAspectRatio,
                  child: CustomPaint(
                    painter: _isExporting ? _ProgressBorderPainter(progress: animatedProgress) : null,
                    child: Container(
                      margin: EdgeInsets.all(_isExporting ? 4.0 : 0.0), // Space for border
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _isExporting 
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primaryStart))
                        : (_playerController != null && _playerController!.value.isInitialized)
                          ? VideoPlayer(_playerController!)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),

            const Spacer(),

            // Post-Export Actions
            if (!_isExporting)
              Padding(
                padding: const EdgeInsets.only(bottom: 40.0, left: 24.0, right: 24.0),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(LucideIcons.download),
                        label: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: _saveVideo,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryStart,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(LucideIcons.share),
                        label: const Text('Share', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        onPressed: _shareVideo,
                      ),
                    ),
                  ],
                ),
              ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressBorderPainter extends CustomPainter {
  final double progress;

  _ProgressBorderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));

    // Draw background track
    final trackPaint = Paint()
      ..color = AppColors.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawRRect(rrect, trackPaint);

    // Draw progress track using a path
    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.primaryStart, AppColors.primaryEnd],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6.0;

    Path path = Path();
    path.addRRect(rrect);
    
    // We can use a DashPath or PathMetrics to extract a subpath
    // For simplicity, we extract the path metric
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    
    final metric = metrics.first;
    final extractPath = metric.extractPath(0.0, metric.length * progress);
    
    canvas.drawPath(extractPath, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
