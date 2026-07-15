import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart' hide ColorFilter;
import 'package:pro_video_editor/pro_video_editor.dart' as pve;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img_lib;

import '../../../core/utils/file_utils.dart';

import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/ffmpeg_overlay_builder.dart';
import '../../../features/video_editor/models/audio_track_model.dart';
import '../../../features/video_editor/models/video_segment.dart' as app;

class VideoEditorService {
  Size _buildTargetRenderSize({
    required Size originalVideoSize,
    required double? targetAspectRatio,
    required Rect? customCropRect,
    int targetHeight = 1080,
  }) {
    if (targetAspectRatio != null && targetAspectRatio > 0) {
      double w = targetHeight * targetAspectRatio;
      return Size(w, targetHeight.toDouble());
    }

    if (customCropRect != null && customCropRect.width > 0 && customCropRect.height > 0) {
      final cropW = customCropRect.width * originalVideoSize.width;
      final cropH = customCropRect.height * originalVideoSize.height;
      if (cropH > 0) {
        final ratio = cropW / cropH;
        double w = targetHeight * ratio;
        return Size(w, targetHeight.toDouble());
      }
    }

    // Default: return original video size to preserve overlay scale factors
    return originalVideoSize;
  }

  /// Maps an app-level animation string (e.g. 'fade_in', 'zoom_in', 'slide_up')
  /// to a [LayerAnimation] from pro_video_editor.
  List<LayerAnimation> _mapAnimations({
    String? animationIn,
    String? animationOut,
    double animationInDuration = 0.5,
    double animationOutDuration = 0.5,
  }) {
    final List<LayerAnimation> animations = [];

    // --- In Animations ---
    if (animationIn != null) {
      final inDuration = Duration(milliseconds: (animationInDuration * 1000).round());
      switch (animationIn) {
        case 'fade_in':
          animations.add(LayerAnimation(
            type: LayerAnimationType.fade,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            curve: AnimationCurve.easeOut,
          ));
          break;
        case 'zoom_in':
          animations.add(LayerAnimation(
            type: LayerAnimationType.scale,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            scaleFrom: 0.0,
            curve: AnimationCurve.easeOutCubic,
          ));
          break;
        case 'zoom_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.scale,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            scaleFrom: 2.0,
            curve: AnimationCurve.easeOutCubic,
          ));
          break;
        case 'slide_up':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            slideDirection: SlideDirection.bottom,
            curve: AnimationCurve.easeOut,
          ));
          break;
        case 'slide_down':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            slideDirection: SlideDirection.top,
            curve: AnimationCurve.easeOut,
          ));
          break;
        case 'slide_left':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            slideDirection: SlideDirection.right,
            curve: AnimationCurve.easeOut,
          ));
          break;
        case 'slide_right':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateIn,
            duration: inDuration,
            slideDirection: SlideDirection.left,
            curve: AnimationCurve.easeOut,
          ));
          break;
      }
    }

    // --- Out Animations ---
    if (animationOut != null) {
      final outDuration = Duration(milliseconds: (animationOutDuration * 1000).round());
      switch (animationOut) {
        case 'fade_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.fade,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            curve: AnimationCurve.easeIn,
          ));
          break;
        case 'zoom_in':
        case 'zoom_in_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.scale,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            scaleFrom: 0.0,
            curve: AnimationCurve.easeInCubic,
          ));
          break;
        case 'zoom_out':
        case 'zoom_out_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.scale,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            scaleFrom: 2.0,
            curve: AnimationCurve.easeInCubic,
          ));
          break;
        case 'slide_up':
        case 'slide_up_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            slideDirection: SlideDirection.top,
            curve: AnimationCurve.easeIn,
          ));
          break;
        case 'slide_down':
        case 'slide_down_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            slideDirection: SlideDirection.bottom,
            curve: AnimationCurve.easeIn,
          ));
          break;
        case 'slide_left':
        case 'slide_left_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            slideDirection: SlideDirection.left,
            curve: AnimationCurve.easeIn,
          ));
          break;
        case 'slide_right':
        case 'slide_right_out':
          animations.add(LayerAnimation(
            type: LayerAnimationType.slide,
            phase: AnimationPhase.animateOut,
            duration: outDuration,
            slideDirection: SlideDirection.right,
            curve: AnimationCurve.easeIn,
          ));
          break;
      }
    }

    return animations;
  }

  pve.ClipTransitionType _mapTransitionType(String type) {
    switch (type) {
      case 'dissolve': return pve.ClipTransitionType.dissolve;
      case 'fadeToBlack': return pve.ClipTransitionType.fadeToBlack;
      case 'fadeToWhite': return pve.ClipTransitionType.fadeToWhite;
      case 'slide': return pve.ClipTransitionType.slide;
      case 'push': return pve.ClipTransitionType.push;
      case 'wipe': return pve.ClipTransitionType.wipe;
      default: return pve.ClipTransitionType.dissolve;
    }
  }

  Future<String> exportTrimmedVideo({
    required String inputPath,
    required List<app.VideoSegment> segments,
    required bool muteAudio,
    double? targetAspectRatio,
    Rect? customCropRect,
    required Size originalVideoSize,
    required Size previewCanvasSize,
    required String renderId,
    List<double>? colorFilterMatrix,
    List<TextOverlayModel>? textOverlays,
    List<ImageOverlayModel>? imageOverlays,
    List<VideoOverlayModel>? videoOverlays,
    List<AudioTrackModel>? audioTracks,
    String backgroundType = 'blur',
    Color backgroundColor = Colors.black,
    double backgroundBlurIntensity = 20.0,
    void Function(double)? onProgress,
    int targetHeight = 1080,
    int targetFps = 30,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final outputPath =
        '${tempDir.path}/${FileUtils.filePrefix}editor_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final targetRenderSize = _buildTargetRenderSize(
      originalVideoSize: originalVideoSize,
      targetAspectRatio: targetAspectRatio,
      customCropRect: customCropRect,
      targetHeight: targetHeight,
    );
    final videoDurationSeconds = _segmentsDurationSeconds(segments);
    final importedAudioTracks = audioTracks ?? const <AudioTrackModel>[];

    final hasVideoOverlays = videoOverlays != null && videoOverlays.isNotEmpty;
    final hasImageOverlays = imageOverlays != null && imageOverlays.isNotEmpty;
    final hasTextOverlays = textOverlays != null && textOverlays.isNotEmpty;
    final hasAnyOverlays = hasVideoOverlays || hasImageOverlays || hasTextOverlays;
    final needsAudioMix = importedAudioTracks.isNotEmpty;
    final needsCustomBackground = targetAspectRatio != null || backgroundType != 'black';
    String finalPveOutputPath = outputPath;

    // Wrap onProgress so it can only go forward (monotonic).
    // This prevents the UI from jumping backwards when transitioning between passes.
    double _lastProgress = 0.0;
    void Function(double)? safeProgress;
    if (onProgress != null) {
      safeProgress = (double p) {
        final clamped = p.clamp(0.0, 1.0);
        if (clamped > _lastProgress) {
          _lastProgress = clamped;
          onProgress(clamped);
        }
      };
    }

    // Determine if we need the two-pass composition path.
    // Two-pass is needed when we have video overlays (PVE forbids playbackSpeed
    // in VideoComposition) OR when we need custom backgrounds/audio mixing.
    final needsComposition = needsCustomBackground || needsAudioMix || hasVideoOverlays;

    if (!needsComposition) {
      // ─── Fast Path: Single PVE render with videoSegments ───
      // Supports: trim, crop, speed, color filter, text/image overlays with
      // native animations and opacity.
      VideoQualityConfig? qualityConfig;
      if (targetAspectRatio != null) {
        qualityConfig = VideoQualityConfig.custom(
          bitrate: 5000000,
          resolution: targetRenderSize,
        );
      }

      ExportTransform? transform;
      if (customCropRect != null) {
        transform = ExportTransform(
          x: (customCropRect.left * originalVideoSize.width).toInt(),
          y: (customCropRect.top * originalVideoSize.height).toInt(),
          width: (customCropRect.width * originalVideoSize.width).toInt(),
          height: (customCropRect.height * originalVideoSize.height).toInt(),
        );
      }

      // Visual overlays (Text, Image, Video) are completely handled in Pass 3 via FFmpeg.

      final renderData = VideoRenderData(
        id: renderId,
        videoSegments: segments.map((seg) => VideoSegment(
          video: EditorVideo.file(File(inputPath)),
          startTime: Duration(milliseconds: (seg.sourceStart * 1000).round()),
          endTime: Duration(milliseconds: (seg.sourceEnd * 1000).round()),
          volume: muteAudio ? 0.0 : seg.volume,
          playbackSpeed: seg.speed,
          transition: seg.transitionType != null
              ? pve.ClipTransition(
                  type: _mapTransitionType(seg.transitionType!),
                  duration: Duration(milliseconds: ((seg.transitionDuration ?? 0.8) * 1000).round()),
                )
              : null,
        )).toList(),
        enableAudio: !muteAudio,
        outputFormat: VideoOutputFormat.mp4,
        qualityConfig: qualityConfig,
        transform: transform,
        imageLayers: null,
        colorFilters: colorFilterMatrix != null
            ? [pve.ColorFilter(matrix: colorFilterMatrix)]
            : const [],
      );

      StreamSubscription? progressSub;
      if (safeProgress != null) {
        progressSub = ProVideoEditor.instance.progressStreamById(renderId).listen((m) {
          final hasVisualOverlays = hasTextOverlays || hasImageOverlays || hasVideoOverlays;
          safeProgress!(m.progress * (hasVisualOverlays ? 0.8 : 1.0));
        });
      }

      await ProVideoEditor.instance.renderVideoToFile(
        outputPath,
        renderData,
        nativeLogLevel: NativeLogLevel.error,
      );
      progressSub?.cancel();
      finalPveOutputPath = outputPath;
    } else {

      // ─── Two-Pass Composition Path ───
    // Pass 1: Render base video with trims, crop, speed, color filter.
    //         Uses videoSegments (which supports playbackSpeed).
    // Pass 2: Use VideoComposition to composite the base video with
    //         image/text/video overlays, background color, and audio tracks.

    debugPrint('[Export] Two-pass composition path');

    // ── Pass 1: Base video render ──
    final tempBaseVideoPath =
        '${tempDir.path}/base_${DateTime.now().millisecondsSinceEpoch}.mp4';

    ExportTransform? transform;
    if (customCropRect != null) {
      transform = ExportTransform(
        x: (customCropRect.left * originalVideoSize.width).toInt(),
        y: (customCropRect.top * originalVideoSize.height).toInt(),
        width: (customCropRect.width * originalVideoSize.width).toInt(),
        height: (customCropRect.height * originalVideoSize.height).toInt(),
      );
    }

    final baseRenderData = VideoRenderData(
      id: '${renderId}_pass1',
      videoSegments: segments.map((seg) => VideoSegment(
        video: EditorVideo.file(File(inputPath)),
        startTime: Duration(milliseconds: (seg.sourceStart * 1000).round()),
        endTime: Duration(milliseconds: (seg.sourceEnd * 1000).round()),
        volume: muteAudio ? 0.0 : seg.volume,
        playbackSpeed: seg.speed,
        transition: seg.transitionType != null
            ? pve.ClipTransition(
                type: _mapTransitionType(seg.transitionType!),
                duration: Duration(milliseconds: ((seg.transitionDuration ?? 0.8) * 1000).round()),
              )
            : null,
      )).toList(),
      enableAudio: !muteAudio,
      outputFormat: VideoOutputFormat.mp4,
      transform: transform,
      imageLayers: const [],
      colorFilters: colorFilterMatrix != null
          ? [pve.ColorFilter(matrix: colorFilterMatrix)]
          : const [],
    );

    StreamSubscription? pass1Sub;
    if (safeProgress != null) {
      pass1Sub = ProVideoEditor.instance.progressStreamById('${renderId}_pass1').listen((m) {
        safeProgress!(m.progress * (hasTextOverlays ? 0.4 : 0.5));
      });
    }

    await ProVideoEditor.instance.renderVideoToFile(
      tempBaseVideoPath,
      baseRenderData,
      nativeLogLevel: NativeLogLevel.error,
    );
    pass1Sub?.cancel();

    // After Pass 1, check if the base video has an audio stream
    final bool hasBaseAudio = !muteAudio && await _hasAudioStream(tempBaseVideoPath);

    // ── Pass 2: Composition render ──
    final targetW = targetRenderSize.width.toInt();
    final targetH = targetRenderSize.height.toInt();
    final safeW = targetW % 2 == 0 ? targetW : targetW + 1;
    final safeH = targetH % 2 == 0 ? targetH : targetH + 1;
    final canvasSize = Size(safeW.toDouble(), safeH.toDouble());

    // Build the main video layer (base track from Pass 1)
    final baseVideoSegment = VideoSegment(
      video: EditorVideo.file(File(tempBaseVideoPath)),
    );
    final baseLayer = VideoLayer(
      clips: [baseVideoSegment],
      opacity: 1.0,
      // If we need to fit into a custom aspect ratio canvas, use SegmentTransform
      transform: needsCustomBackground
          ? SegmentTransform(
              offset: Offset.zero,
              size: canvasSize,
              fit: SegmentFit.contain,
            )
          : null,
    );

    // Collect all layers and audio tracks for the composition
    final List<VideoLayer> compositionLayers = [baseLayer];
    final List<VideoAudioTrack> pveAudioTracks = [];

    // Build video overlay layers
    if (hasVideoOverlays) {
      for (final overlay in videoOverlays) {
        if (overlay.timelineStart >= overlay.timelineEnd) continue;

        final sourceStartSec = overlay.sourceStart;
        final timelineDurationSec = math.max(
          0.0,
          (overlay.timelineEnd.inMilliseconds - overlay.timelineStart.inMilliseconds) / 1000.0,
        );
        final effectiveSourceEndSec = math.min(
          overlay.sourceEnd,
          sourceStartSec + timelineDurationSec,
        );

        if (effectiveSourceEndSec <= sourceStartSec) continue;

        // Add the video overlay's audio to the composition mixer
        if (!overlay.isMuted && overlay.volume > 0 && await _hasAudioStream(overlay.videoPath)) {
          pveAudioTracks.add(VideoAudioTrack(
            path: overlay.videoPath,
            volume: overlay.volume.clamp(0.0, 2.0),
            audioStartTime: Duration(milliseconds: (sourceStartSec * 1000).round()),
            audioEndTime: Duration(milliseconds: (effectiveSourceEndSec * 1000).round()),
            startTime: overlay.timelineStart,
          ));
        }
      }
    }

    // Map imported audio tracks to PVE's VideoAudioTrack
    for (final track in importedAudioTracks) {
      if (track.sourceEnd <= track.sourceStart || track.volume <= 0) continue;
      pveAudioTracks.add(VideoAudioTrack(
        path: track.filePath,
        volume: track.volume.clamp(0.0, 2.0),
        audioStartTime: Duration(milliseconds: (track.sourceStart * 1000).round()),
        audioEndTime: Duration(milliseconds: (track.sourceEnd * 1000).round()),
        startTime: Duration(milliseconds: (track.timelineStart * 1000).round()),
      ));
    }

    if (hasBaseAudio) {
      pveAudioTracks.add(VideoAudioTrack(
        path: tempBaseVideoPath,
        volume: 1.0,
        audioStartTime: Duration.zero,
        audioEndTime: Duration(milliseconds: (videoDurationSeconds * 1000).round()),
        startTime: Duration.zero,
      ));
    }

    final composition = VideoComposition(
      layers: compositionLayers,
      canvasSize: canvasSize,
      backgroundColor: backgroundColor,
    );

    final compositionRenderData = VideoRenderData(
      id: renderId,
      composition: composition,
      imageLayers: null,
      enableAudio: !muteAudio || pveAudioTracks.isNotEmpty,
      outputFormat: VideoOutputFormat.mp4,
      audioTracks: pveAudioTracks,
      maxFrameRate: targetFps,
    );

    StreamSubscription? pass2Sub;
    if (safeProgress != null) {
      pass2Sub = ProVideoEditor.instance.progressStreamById(renderId).listen((m) {
        final hasVisualOverlays = hasTextOverlays || hasImageOverlays || hasVideoOverlays;
        final base = hasVisualOverlays ? 0.4 : 0.5;
        final range = hasVisualOverlays ? 0.4 : 0.5;
        safeProgress!(base + (m.progress * range));
      });
    }

    await ProVideoEditor.instance.renderVideoToFile(
      outputPath,
      compositionRenderData,
      nativeLogLevel: NativeLogLevel.error,
    );
    
    pass2Sub?.cancel();

    // Clean up the temp base video from Pass 1
    await FileUtils.deleteFile(tempBaseVideoPath);
    }
    
    // ─── Pass 3: Visual Overlays (FFmpeg complex_filter) ───
    final hasVisualOverlays = hasTextOverlays || hasImageOverlays || hasVideoOverlays;
    if (hasVisualOverlays) {
      debugPrint('[Export] Applying visual overlays via FFmpeg complex_filter');
      final pass3OutputPath = await FFmpegOverlayBuilder.applyVisualOverlaysViaFFmpeg(
        inputVideoPath: finalPveOutputPath,
        textOverlays: textOverlays ?? [],
        imageOverlays: imageOverlays ?? [],
        videoOverlays: videoOverlays ?? [],
        videoSize: targetRenderSize,
        previewSize: previewCanvasSize,
        videoDurationSeconds: videoDurationSeconds,
        onProgress: safeProgress != null 
            ? (p) => safeProgress!(0.8 + (p * 0.2))
            : null,
      );
      
      // If we created a new file, we can optionally delete the intermediate PVE output.
      if (pass3OutputPath != finalPveOutputPath) {
        await FileUtils.deleteFile(finalPveOutputPath);
      }
      return pass3OutputPath;
    }

    return finalPveOutputPath;
  }

  double _segmentsDurationSeconds(List<app.VideoSegment> segments) {
    return segments.fold(
      0.0,
      (sum, segment) => sum + segment.duration,
    );
  }

  double _maxAudioEndSeconds(List<AudioTrackModel> audioTracks) {
    return audioTracks.fold(
      0.0,
      (maxEnd, track) => math.max(maxEnd, track.timelineEnd),
    );
  }

  Future<bool> _hasAudioStream(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final information = session.getMediaInformation();
      final streams = information?.getStreams();
      if (streams == null) return false;
      for (final stream in streams) {
        if (stream.getType() == 'audio') return true;
      }
      return false;
    } catch (e) {
      debugPrint('[FFprobe] Audio stream check failed: $e');
      return false;
    }
  }

  Future<List<Uint8List>> generateThumbnails({
    required String inputPath,
    required double durationSeconds,
    int count = 10,
  }) async {
    final List<Duration> timestamps = [];
    final double step = durationSeconds / count;
    
    // Generate evenly spaced timestamps
    for (int i = 0; i < count; i++) {
      // Offset slightly from 0 and max duration to avoid black frames at absolute edges
      double time = (i * step) + (step / 2);
      timestamps.add(Duration(milliseconds: (time * 1000).round()));
    }

    final configs = ThumbnailConfigs(
      video: EditorVideo.file(File(inputPath)),
      outputSize: const Size(400, 240), // High resolution for crisp display
      timestamps: timestamps,
      jpegQuality: 90, // Maximize quality
    );

    return await ProVideoEditor.instance.getThumbnails(configs);
  }

}
