import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../utils/font_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';

class FFmpegOverlayBuilder {
  static Future<String> applyVisualOverlaysViaFFmpeg({
    required String inputVideoPath,
    required List<TextOverlayModel> textOverlays,
    required List<ImageOverlayModel> imageOverlays,
    required List<VideoOverlayModel> videoOverlays,
    required Size videoSize,
    required Size previewSize,
    required double videoDurationSeconds,
    required void Function(double)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final finalOutputPath = '${tempDir.path}/${FileUtils.filePrefix}editor_visuals_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final List<String> tempFilesToClean = [];
    final List<String> overlayFilters = [];
    final List<String> inputs = ['-i', inputVideoPath];
    int inputIndex = 1;

    // Collect and sort all overlays
    final sortedOverlays = <({int laneIndex, dynamic model, String type})>[];

    for (final text in textOverlays) {
      sortedOverlays.add((laneIndex: text.laneIndex, model: text, type: 'text'));
    }
    for (final img in imageOverlays) {
      sortedOverlays.add((laneIndex: img.laneIndex, model: img, type: 'image'));
    }
    for (final vid in videoOverlays) {
      sortedOverlays.add((laneIndex: vid.laneIndex, model: vid, type: 'video'));
    }

    // Sort strictly by laneIndex
    sortedOverlays.sort((a, b) => a.laneIndex.compareTo(b.laneIndex));

    for (final item in sortedOverlays) {
      final type = item.type;
      final dynamic overlay = item.model;

      if (type == 'text') {
        if (overlay.startTime >= overlay.endTime) continue;
        final pngData = await _createTextPngForFFmpeg(overlay, videoSize, previewSize);
        if (pngData == null) continue;
        tempFilesToClean.add(pngData.imagePath);

        final duration = (overlay.endTime.inMilliseconds - overlay.startTime.inMilliseconds) / 1000.0;
        final start = (overlay.startTime.inMilliseconds / 1000.0);
        final end = math.min(start + duration, videoDurationSeconds);

        inputs.addAll(['-loop', '1', '-t', duration.toStringAsFixed(3), '-i', pngData.imagePath]);
        final inStream = inputIndex == 1 ? '[0:v]' : '[v${inputIndex - 1}]';
        final outStream = inputIndex == sortedOverlays.length ? '[vout]' : '[v$inputIndex]';

        final prepStream = '[prep$inputIndex]';
        String prepFilter = '[$inputIndex:v]format=rgba';
        
        // Fades
        if (overlay.inAnimation == 'fade_in' || overlay.inAnimation == 'fade') {
          prepFilter += ",fade=t=in:st=0:d=${overlay.animationInDuration}:alpha=1";
        }
        if (overlay.outAnimation == 'fade_out' || overlay.outAnimation == 'fade') {
          prepFilter += ",fade=t=out:st=${math.max(0, duration - overlay.animationOutDuration)}:d=${overlay.animationOutDuration}:alpha=1";
        }
        
        // Sync PTS to absolute start time so the overlay frame timelines perfectly match the main video
        prepFilter += ',setpts=PTS+${start}/TB';
        
        final cx = pngData.dx + pngData.width / 2;
        final cy = pngData.dy + pngData.height / 2;
        final anims = _buildAnimationExpressions(
          start: start,
          end: end,
          inAnimation: overlay.inAnimation,
          outAnimation: overlay.outAnimation,
          inDuration: overlay.animationInDuration,
          outDuration: overlay.animationOutDuration,
          cx: cx,
          cy: cy,
          videoSize: videoSize,
        );

        if (anims.scaleExpr != '1') {
          prepFilter += ",scale=w='iw*max(0.01,${anims.scaleExpr})':h='ih*max(0.01,${anims.scaleExpr})':eval=frame";
        }
        prepFilter += prepStream;
        overlayFilters.add(prepFilter);
        
        overlayFilters.add("$inStream$prepStream" "overlay=x='${anims.xExpr}':y='${anims.yExpr}':format=auto:enable='between(t,${start.toStringAsFixed(3)},${end.toStringAsFixed(3)})'$outStream");
        
        inputIndex++;
      } 
      else if (type == 'image') {
        if (overlay.startTime >= overlay.endTime) continue;
        final pngData = await _createImagePngForFFmpeg(overlay, videoSize, previewSize);
        if (pngData == null) continue;
        tempFilesToClean.add(pngData.imagePath);

        final duration = (overlay.endTime.inMilliseconds - overlay.startTime.inMilliseconds) / 1000.0;
        final start = (overlay.startTime.inMilliseconds / 1000.0);
        final end = math.min(start + duration, videoDurationSeconds);

        inputs.addAll(['-loop', '1', '-t', duration.toStringAsFixed(3), '-i', pngData.imagePath]);
        final inStream = inputIndex == 1 ? '[0:v]' : '[v${inputIndex - 1}]';
        final outStream = inputIndex == sortedOverlays.length ? '[vout]' : '[v$inputIndex]';

        final prepStream = '[prep$inputIndex]';
        String prepFilter = '[$inputIndex:v]format=rgba';
        
        // Fades
        if (overlay.animationIn == 'fade_in') {
          prepFilter += ",fade=t=in:st=0:d=${overlay.animationInDuration}:alpha=1";
        }
        if (overlay.animationOut == 'fade_out') {
          prepFilter += ",fade=t=out:st=${math.max(0, duration - overlay.animationOutDuration)}:d=${overlay.animationOutDuration}:alpha=1";
        }
        
        // Sync PTS to absolute start time so the overlay frame timelines perfectly match the main video
        prepFilter += ",setpts=PTS+${start}/TB";
        
        final cx = pngData.dx + pngData.width / 2;
        final cy = pngData.dy + pngData.height / 2;
        final anims = _buildAnimationExpressions(
          start: start,
          end: end,
          inAnimation: overlay.animationIn,
          outAnimation: overlay.animationOut,
          inDuration: overlay.animationInDuration,
          outDuration: overlay.animationOutDuration,
          cx: cx,
          cy: cy,
          videoSize: videoSize,
        );

        if (anims.scaleExpr != '1') {
          prepFilter += ",scale=w='iw*max(0.01,${anims.scaleExpr})':h='ih*max(0.01,${anims.scaleExpr})':eval=frame";
        }
        prepFilter += prepStream;
        overlayFilters.add(prepFilter);
        
        overlayFilters.add("$inStream$prepStream" "overlay=x='${anims.xExpr}':y='${anims.yExpr}':format=auto:enable='between(t,${start.toStringAsFixed(3)},${end.toStringAsFixed(3)})'$outStream");
        
        inputIndex++;
      }
      else if (type == 'video') {
        if (overlay.timelineStart >= overlay.timelineEnd) continue;
        
        final duration = (overlay.timelineEnd.inMilliseconds - overlay.timelineStart.inMilliseconds) / 1000.0;
        final start = (overlay.timelineStart.inMilliseconds / 1000.0);
        final end = math.min(start + duration, videoDurationSeconds);
        final sourceStart = overlay.sourceStart;

        inputs.addAll(['-ss', sourceStart.toStringAsFixed(3), '-t', duration.toStringAsFixed(3), '-i', overlay.videoPath]);
        final inStream = inputIndex == 1 ? '[0:v]' : '[v${inputIndex - 1}]';
        final outStream = inputIndex == sortedOverlays.length ? '[vout]' : '[v$inputIndex]';

        // Setup scale based on the preview size logic
        final refSize = previewSize;
        final scaleX = refSize.width > 0 ? videoSize.width / refSize.width : 1.0;
        final scaleY = refSize.height > 0 ? videoSize.height / refSize.height : 1.0;
        final renderScale = overlay.scale * math.min(scaleX, scaleY);
        
        // We will scale dynamically in FFmpeg using iw*renderScale and ih*renderScale
        final prepStream = '[prep$inputIndex]';
        String prepFilter = '[$inputIndex:v]format=rgba';
        
        if (overlay.opacity < 1.0) {
          prepFilter += ",colorchannelmixer=aa=${overlay.opacity}";
        }
        
        final maxVideoBound = 240 * renderScale;
        prepFilter += ",scale=w=${maxVideoBound}:h=${maxVideoBound}:force_original_aspect_ratio=decrease";
        
        if (overlay.rotation != 0) {
          prepFilter += ",rotate=${overlay.rotation}:c=none:ow='hypot(iw,ih)':oh='hypot(iw,ih)'";
        }
        
        // Fades
        if (overlay.animationIn == 'fade_in') {
          prepFilter += ",fade=t=in:st=0:d=${overlay.animationInDuration}:alpha=1";
        }
        if (overlay.animationOut == 'fade_out') {
          prepFilter += ",fade=t=out:st=${math.max(0, duration - overlay.animationOutDuration)}:d=${overlay.animationOutDuration}:alpha=1";
        }
        
        // Sync PTS to absolute start time so the overlay frame timelines perfectly match the main video
        prepFilter += ",setpts=PTS+${start}/TB";

        final cx = videoSize.width / 2 + overlay.position.dx * scaleX;
        final cy = videoSize.height / 2 + overlay.position.dy * scaleY;
        final anims = _buildAnimationExpressions(
          start: start,
          end: end,
          inAnimation: overlay.animationIn,
          outAnimation: overlay.animationOut,
          inDuration: overlay.animationInDuration,
          outDuration: overlay.animationOutDuration,
          cx: cx,
          cy: cy,
          videoSize: videoSize,
        );

        if (anims.scaleExpr != '1') {
          prepFilter += ",scale=w='iw*max(0.01,${anims.scaleExpr})':h='ih*max(0.01,${anims.scaleExpr})':eval=frame";
        }
        prepFilter += prepStream;
        overlayFilters.add(prepFilter);
        
        overlayFilters.add("$inStream$prepStream" "overlay=x='${anims.xExpr}':y='${anims.yExpr}':format=auto:enable='between(t,${start.toStringAsFixed(3)},${end.toStringAsFixed(3)})'$outStream");
        
        inputIndex++;
      }
    }

    if (overlayFilters.isEmpty) {
      return inputVideoPath;
    }

    final complexFilter = overlayFilters.join(';');

    // Ensure the output file is deleted before running
    if (await File(finalOutputPath).exists()) {
      await File(finalOutputPath).delete();
    }

    // Use libx264 but with ultrafast preset to maximize speed on mobile CPUs
    // We cannot use MediaCodec hardware encoding because it causes native segfaults
    // on certain lower-end Android chips (e.g. Unisoc), crashing the entire app.
    final args = [
      '-y',
      ...inputs,
      '-filter_complex', complexFilter,
      '-map', '[vout]',
      '-map', '0:a?',
      '-c:v', 'libx264',
      '-preset', 'ultrafast',
      '-crf', '18', // High quality
      '-pix_fmt', 'yuv420p', // Force YUV420p for mobile playback compatibility
      '-c:a', 'copy',
      finalOutputPath
    ];

    debugPrint('[FFmpeg] Executing command for unified visual overlays: $args');

    final completer = Completer<ReturnCode?>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final rc = await session.getReturnCode();
        completer.complete(rc);
      },
      null, // logCallback
      (statistics) {
        if (onProgress != null && videoDurationSeconds > 0) {
          final timeInMs = statistics.getTime();
          var progress = timeInMs / (videoDurationSeconds * 1000);
          onProgress(progress.clamp(0.0, 1.0));
        }
      },
    );

    ReturnCode? returnCode;
    try {
      returnCode = await completer.future;
    } finally {
      for (final path in tempFilesToClean) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('[FFmpegOverlayBuilder] Error deleting temp file $path: $e');
        }
      }
    }

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint('[FFmpeg] Unified visual overlay successful');
      return finalOutputPath;
    } else {
      final logs = await session.getLogsAsString();
      debugPrint('[FFmpeg] Unified overlay failed. Logs: $logs');
      throw Exception('FFmpeg Unified overlay failed: $logs');
    }
  }

  static Future<({String imagePath, double dx, double dy, double width, double height})?> _createImagePngForFFmpeg(
    ImageOverlayModel overlay,
    Size videoSize,
    Size previewCanvasSize,
  ) async {
    final refSize = previewCanvasSize;
    final scaleX = refSize.width > 0 ? videoSize.width / refSize.width : 1.0;
    final scaleY = refSize.height > 0 ? videoSize.height / refSize.height : 1.0;
    final baseVideoScale = math.min(scaleX, scaleY);
    final renderScale = baseVideoScale * overlay.scale;

    final imgBytes = await File(overlay.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(imgBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // Match the UI's ConstrainedBox(maxWidth: 200, maxHeight: 200) behavior.
    double imageScale = 1.0;
    if (image.width > 200 || image.height > 200) {
      imageScale = math.min(200 / image.width, 200 / image.height);
    }

    final unrotatedW = (image.width * imageScale) * renderScale;
    final unrotatedH = (image.height * imageScale) * renderScale;

    final rad = overlay.rotation;
    final absCos = math.cos(rad).abs();
    final absSin = math.sin(rad).abs();
    
    final edgeBuffer = 4.0;
    final pngW = (unrotatedW * absCos + unrotatedH * absSin + edgeBuffer * 2).ceilToDouble();
    final pngH = (unrotatedW * absSin + unrotatedH * absCos + edgeBuffer * 2).ceilToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.translate(pngW / 2, pngH / 2);
    canvas.rotate(rad);
    canvas.translate(-unrotatedW / 2, -unrotatedH / 2);

    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
      
    if (overlay.opacity < 1.0) {
      paint.color = Colors.white.withOpacity(overlay.opacity);
    }

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, unrotatedW, unrotatedH),
      paint,
    );

    final picture = recorder.endRecording();
    final imgOut = await picture.toImage(pngW.toInt(), pngH.toInt());
    final byteData = await imgOut.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/overlay_img_${overlay.id}_${DateTime.now().millisecondsSinceEpoch}.png');
    await tempFile.writeAsBytes(byteData.buffer.asUint8List());

    final cx = videoSize.width / 2 + overlay.position.dx * scaleX;
    final cy = videoSize.height / 2 + overlay.position.dy * scaleY;
    
    final dx = cx - pngW / 2;
    final dy = cy - pngH / 2;

    return (imagePath: tempFile.path, dx: dx, dy: dy, width: pngW, height: pngH);
  }

  static Future<({String imagePath, double dx, double dy, double width, double height})?> _createTextPngForFFmpeg(
    TextOverlayModel overlay,
    Size videoSize,
    Size previewCanvasSize,
  ) async {
    final refSize = overlay.referenceCanvasSize ?? previewCanvasSize;
    final scaleX = refSize.width > 0 ? videoSize.width / refSize.width : 1.0;
    final scaleY = refSize.height > 0 ? videoSize.height / refSize.height : 1.0;
    final baseVideoScale = math.min(scaleX, scaleY);
    final renderScale = baseVideoScale * overlay.scale;

    final fontSize = 32.0 * renderScale;
    final bgPadH = overlay.backgroundColor != Colors.transparent ? overlay.backgroundPadding * renderScale : 0.0;
    final bgPadV = overlay.backgroundColor != Colors.transparent ? (overlay.backgroundPadding / 2) * renderScale : 0.0;
    final containerPad = 8.0 * renderScale;

    final shadows = overlay.shadowColor != Colors.transparent && overlay.shadowBlurRadius > 0
        ? [
            Shadow(
              color: overlay.shadowColor,
              blurRadius: overlay.shadowBlurRadius * renderScale,
              offset: Offset(
                (overlay.shadowBlurRadius * renderScale) / 2,
                (overlay.shadowBlurRadius * renderScale) / 2,
              ),
            ),
          ]
        : <Shadow>[];

    final baseOuterWidth = overlay.boxWidth ?? refSize.width;
    final outerMaxWidth = math.max(120.0, baseOuterWidth - 32.0) * renderScale;
    final totalPaddingH = bgPadH * 2 + containerPad * 2;
    final innerMaxWidth = math.max(0.0, outerMaxWidth - totalPaddingH);

    final fillPainter = TextPainter(
      text: TextSpan(
        text: overlay.text,
        style: getFontStyle(
          overlay.fontFamily,
          color: overlay.color,
          fontSize: fontSize,
          height: 1.15,
          shadows: shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: overlay.textAlign == 'left' ? TextAlign.left : overlay.textAlign == 'right' ? TextAlign.right : overlay.textAlign == 'justify' ? TextAlign.justify : TextAlign.center,
    );
    fillPainter.layout(minWidth: 0, maxWidth: innerMaxWidth);

    TextPainter? strokePainter;
    if (overlay.strokeColor != Colors.transparent && overlay.strokeWidth > 0) {
      strokePainter = TextPainter(
        text: TextSpan(
          text: overlay.text,
          style: getFontStyle(
            overlay.fontFamily,
            fontSize: fontSize,
            height: 1.15,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = overlay.strokeWidth * renderScale
              ..color = overlay.strokeColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: overlay.textAlign == 'left' ? TextAlign.left : overlay.textAlign == 'right' ? TextAlign.right : overlay.textAlign == 'justify' ? TextAlign.justify : TextAlign.center,
      );
      strokePainter.layout(minWidth: 0, maxWidth: innerMaxWidth);
    }

    final textW = math.max(fillPainter.width, strokePainter?.width ?? 0);
    final textH = math.max(fillPainter.height, strokePainter?.height ?? 0);
    
    final unrotatedW = textW + totalPaddingH;
    final unrotatedH = textH + (bgPadV * 2) + (containerPad * 2);

    final rad = overlay.rotation;
    final absCos = math.cos(rad).abs();
    final absSin = math.sin(rad).abs();
    
    final edgeBuffer = 4.0;
    final pngW = (unrotatedW * absCos + unrotatedH * absSin + edgeBuffer * 2).ceilToDouble();
    final pngH = (unrotatedW * absSin + unrotatedH * absCos + edgeBuffer * 2).ceilToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.translate(pngW / 2, pngH / 2);
    canvas.rotate(rad);
    canvas.translate(-unrotatedW / 2, -unrotatedH / 2);

    if (overlay.backgroundColor != Colors.transparent) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(containerPad, containerPad, textW + bgPadH * 2, textH + bgPadV * 2),
          Radius.circular(overlay.borderRadius * renderScale),
        ),
        Paint()
          ..color = overlay.backgroundColor
          ..isAntiAlias = true,
      );
    }

    final textOrigin = Offset(containerPad + bgPadH, containerPad + bgPadV);
    strokePainter?.paint(canvas, textOrigin);
    fillPainter.paint(canvas, textOrigin);

    final picture = recorder.endRecording();
    final img = await picture.toImage(pngW.toInt(), pngH.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/overlay_text_${overlay.id}_${DateTime.now().millisecondsSinceEpoch}.png');
    await tempFile.writeAsBytes(byteData.buffer.asUint8List());

    final cx = videoSize.width / 2 + overlay.position.dx * scaleX;
    final cy = videoSize.height / 2 + overlay.position.dy * scaleY;
    
    final dx = cx - pngW / 2;
    final dy = cy - pngH / 2;

    return (
      imagePath: tempFile.path,
      dx: dx,
      dy: dy,
      width: pngW,
      height: pngH,
    );
  }

  static ({String scaleExpr, String xExpr, String yExpr}) _buildAnimationExpressions({
    required double start,
    required double end,
    required String? inAnimation,
    required String? outAnimation,
    required double inDuration,
    required double outDuration,
    required double cx,
    required double cy,
    required Size videoSize,
  }) {
    String scaleExpr = '1';
    
    // Zoom IN
    if (inAnimation == 'zoom_in') {
      scaleExpr = "if(lt(t,${start + inDuration}), max(0.001, (t-$start)/$inDuration), $scaleExpr)";
    } else if (inAnimation == 'zoom_out') {
      scaleExpr = "if(lt(t,${start + inDuration}), 2.0 - (t-$start)/$inDuration, $scaleExpr)";
    }
    
    // Zoom OUT
    if (outAnimation == 'zoom_in_out' || outAnimation == 'zoom_in') {
      scaleExpr = "if(gt(t,${end - outDuration}), max(0.001, 1.0 - (t-(${end - outDuration}))/$outDuration), $scaleExpr)";
    } else if (outAnimation == 'zoom_out_out' || outAnimation == 'zoom_out') {
      scaleExpr = "if(gt(t,${end - outDuration}), 1.0 + (t-(${end - outDuration}))/$outDuration, $scaleExpr)";
    }
    
    // Centered overlay position based on dynamic scale width(w) and height(h)
    String xExpr = '${cx.toStringAsFixed(3)} - w/2';
    String yExpr = '${cy.toStringAsFixed(3)} - h/2';
    
    // Slide IN
    if (inAnimation == 'slide_up') {
      yExpr = "if(lt(t,${start + inDuration}), ($yExpr) + ${videoSize.height}*(1-(t-$start)/$inDuration), $yExpr)";
    } else if (inAnimation == 'slide_down') {
      yExpr = "if(lt(t,${start + inDuration}), ($yExpr) - ${videoSize.height}*(1-(t-$start)/$inDuration), $yExpr)";
    } else if (inAnimation == 'slide_left') {
      xExpr = "if(lt(t,${start + inDuration}), ($xExpr) + ${videoSize.width}*(1-(t-$start)/$inDuration), $xExpr)";
    } else if (inAnimation == 'slide_right') {
      xExpr = "if(lt(t,${start + inDuration}), ($xExpr) - ${videoSize.width}*(1-(t-$start)/$inDuration), $xExpr)";
    }

    // Slide OUT
    if (outAnimation == 'slide_up_out' || outAnimation == 'slide_up') {
      yExpr = "if(gt(t,${end - outDuration}), ($yExpr) - ${videoSize.height}*((t-(${end - outDuration}))/$outDuration), $yExpr)";
    } else if (outAnimation == 'slide_down_out' || outAnimation == 'slide_down') {
      yExpr = "if(gt(t,${end - outDuration}), ($yExpr) + ${videoSize.height}*((t-(${end - outDuration}))/$outDuration), $yExpr)";
    } else if (outAnimation == 'slide_left_out' || outAnimation == 'slide_left') {
      xExpr = "if(gt(t,${end - outDuration}), ($xExpr) - ${videoSize.width}*((t-(${end - outDuration}))/$outDuration), $xExpr)";
    } else if (outAnimation == 'slide_right_out' || outAnimation == 'slide_right') {
      xExpr = "if(gt(t,${end - outDuration}), ($xExpr) + ${videoSize.width}*((t-(${end - outDuration}))/$outDuration), $xExpr)";
    }
    
    return (scaleExpr: scaleExpr, xExpr: xExpr, yExpr: yExpr);
  }
}
