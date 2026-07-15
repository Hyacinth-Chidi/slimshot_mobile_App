import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_player/video_player.dart';

import '../core/services/media_save_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/toast_utils.dart';
import '../features/video_editor/models/text_overlay_model.dart';
import '../features/video_editor/models/image_overlay_model.dart';
import '../features/video_editor/models/video_overlay_model.dart';
import '../features/video_editor/models/audio_track_model.dart';
import '../features/video_editor/models/video_segment.dart' as app;
import '../features/video_editor/services/video_editor_service.dart';

class ExportVideoScreen extends StatefulWidget {
  final File sourceVideo;
  final List<app.VideoSegment> segments;
  final bool muteAudio;
  final double? targetAspectRatio;
  final Rect? customCropRect;
  final Size originalVideoSize;
  final Size previewCanvasSize;
  final String renderId;
  final List<double>? colorFilterMatrix;
  final List<TextOverlayModel>? textOverlays;
  final List<ImageOverlayModel>? imageOverlays;
  final List<VideoOverlayModel>? videoOverlays;
  final List<AudioTrackModel> audioTracks;
  final String backgroundType;
  final Color backgroundColor;
  final double backgroundBlurIntensity;
  final int targetHeight;
  final int targetFps;

  const ExportVideoScreen({
    super.key,
    required this.sourceVideo,
    required this.segments,
    required this.muteAudio,
    required this.targetAspectRatio,
    required this.customCropRect,
    required this.originalVideoSize,
    required this.previewCanvasSize,
    required this.renderId,
    this.colorFilterMatrix,
    this.textOverlays,
    this.imageOverlays,
    this.videoOverlays,
    this.audioTracks = const [],
    required this.backgroundType,
    required this.backgroundColor,
    required this.backgroundBlurIntensity,
    required this.targetHeight,
    required this.targetFps,
  });

  @override
  State<ExportVideoScreen> createState() => _ExportVideoScreenState();
}

class _ExportVideoScreenState extends State<ExportVideoScreen> {
  final _editorService = VideoEditorService();
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
    try {
      final outputPath = await _editorService.exportTrimmedVideo(
        inputPath: widget.sourceVideo.path,
        segments: widget.segments,
        muteAudio: widget.muteAudio,
        targetAspectRatio: widget.targetAspectRatio,
        customCropRect: widget.customCropRect,
        originalVideoSize: widget.originalVideoSize,
        previewCanvasSize: widget.previewCanvasSize,
        renderId: widget.renderId,
        colorFilterMatrix: widget.colorFilterMatrix,
        textOverlays: widget.textOverlays,
        imageOverlays: widget.imageOverlays,
        videoOverlays: widget.videoOverlays,
        audioTracks: widget.audioTracks,
        backgroundType: widget.backgroundType,
        backgroundColor: widget.backgroundColor,
        backgroundBlurIntensity: widget.backgroundBlurIntensity,
        targetHeight: widget.targetHeight,
        targetFps: widget.targetFps,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p.clamp(0.0, 1.0);
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _progress = 1.0;
        _exportedVideoPath = outputPath;
      });

      _initExportedVideo(outputPath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
      });
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
    ProVideoEditor.instance.cancel(widget.renderId);
    Navigator.pop(context);
  }

  Future<void> _saveVideo() async {
    if (_exportedVideoPath == null) return;
    try {
      await MediaSaveService.saveOptimizedMediaToGallery(
        [_exportedVideoPath!],
        album: 'SlimShotAI',
      );
      if (mounted) ToastUtils.show(context, 'Saved to gallery!');
    } catch (e) {
      if (mounted) ToastUtils.show(context, 'Failed to save: $e', isError: true);
    }
  }

  void _shareVideo() {
    if (_exportedVideoPath == null) return;
    MediaSaveService.shareFiles([_exportedVideoPath!]);
  }

  double _resolveDisplayAspectRatio() {
    if (widget.targetAspectRatio != null && widget.targetAspectRatio! > 0) {
      return widget.targetAspectRatio!;
    }

    final cropRect = widget.customCropRect;
    if (cropRect != null &&
        cropRect.width > 0 &&
        cropRect.height > 0 &&
        widget.originalVideoSize.height > 0) {
      return (cropRect.width * widget.originalVideoSize.width) /
          (cropRect.height * widget.originalVideoSize.height);
    }

    return widget.originalVideoSize.width / widget.originalVideoSize.height;
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
                    icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
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
                  color: Colors.white,
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
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'Export Complete!',
                style: TextStyle(
                  color: Colors.white,
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
                        borderRadius: BorderRadius.circular(16),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          backgroundColor: Colors.deepOrange, // Matches the orange gradient in screenshot
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    // Draw background track
    final trackPaint = Paint()
      ..color = AppColors.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawRRect(rrect, trackPaint);

    // Draw progress track using a path
    final progressPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.deepOrange, Colors.orangeAccent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

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
