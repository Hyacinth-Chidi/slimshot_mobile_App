import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../core/utils/file_utils.dart';

/// Renders the proxy files playback needs.
///
/// **This is the editor's last FFmpeg dependency.** Export, overlays and text
/// all render natively now (`export/VideoExportEngine.kt` +
/// `TextOverlayRasterizer`); what remains here is proxy preparation, where a
/// clip is rewritten to a file the player can walk forward:
///
/// - a **reverse proxy**, because no decoder plays backwards, and
/// - a **playback proxy**, a clip re-encoded with a keyframe at zero.
///
/// Both use `libx264` software encoding, which is slow on exactly the hardware
/// this app targets. Replacing them with `ExportClipDecoder` +
/// `VideoFrameEncoder` (hardware, already built for export) is the last step
/// to an FFmpeg-free editor; FFmpeg then belongs only to the compression
/// feature, which is its permanent home.
class VideoEditorService {

  Future<String> createClipPlaybackProxy({
    required String inputPath,
    required double sourceStart,
    required double sourceEnd,
    void Function(double progress)? onProgress,
    Directory? outputDir,
  }) async {
    final duration = sourceEnd - sourceStart;
    if (duration <= 0) {
      throw ArgumentError('Playback proxy duration must be greater than zero.');
    }

    // Into the draft's own folder when the caller has one — the temp
    // directory is swept by prefix at startup, which is how a reopened draft
    // came to point at proxies that no longer existed.
    final dir = outputDir ?? await getTemporaryDirectory();
    final outputPath =
        '${dir.path}/${FileUtils.filePrefix}clip_proxy_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final hasAudio = await _hasAudioStream(inputPath);

    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-ss',
      sourceStart.toStringAsFixed(3),
      '-t',
      duration.toStringAsFixed(3),
      '-map',
      '0:v:0',
      if (hasAudio) ...[
        '-map',
        '0:a:0?',
      ],
      '-vf',
      'setpts=PTS-STARTPTS',
      if (hasAudio) ...[
        '-af',
        'asetpts=PTS-STARTPTS',
      ] else
        '-an',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
      '-force_key_frames',
      '0',
      if (hasAudio) ...[
        '-c:a',
        'aac',
        '-b:a',
        '128k',
      ],
      '-movflags',
      '+faststart',
      outputPath,
    ];

    debugPrint('[ClipPlaybackProxy] FFmpeg args: $args');
    final completer = Completer<ReturnCode?>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        completer.complete(await session.getReturnCode());
      },
      null,
      (statistics) {
        final progress = statistics.getTime() / (duration * 1000);
        onProgress?.call(progress.clamp(0.0, 1.0).toDouble());
      },
    );

    final returnCode = await completer.future;
    if (ReturnCode.isSuccess(returnCode)) {
      final file = File(outputPath);
      if (await file.exists()) {
        onProgress?.call(1.0);
        return outputPath;
      }
    }

    await FileUtils.deleteFile(outputPath);
    final logs = await session.getLogsAsString();
    throw Exception('Clip playback proxy failed: $logs');
  }

  Future<String> createReverseProxy({
    required String inputPath,
    required double sourceStart,
    required double sourceEnd,
    void Function(double progress)? onProgress,
    Directory? outputDir,
  }) async {
    final duration = sourceEnd - sourceStart;
    if (duration <= 0) {
      throw ArgumentError('Reverse proxy duration must be greater than zero.');
    }

    final dir = outputDir ?? await getTemporaryDirectory();
    final outputPath =
        '${dir.path}/${FileUtils.filePrefix}reverse_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final hasAudio = await _hasAudioStream(inputPath);

    final args = <String>[
      '-y',
      '-ss',
      sourceStart.toStringAsFixed(3),
      '-t',
      duration.toStringAsFixed(3),
      '-i',
      inputPath,
      '-vf',
      'reverse,setpts=PTS-STARTPTS',
      if (hasAudio) ...[
        '-af',
        'areverse,asetpts=PTS-STARTPTS',
      ] else
        '-an',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-pix_fmt',
      'yuv420p',
      if (hasAudio) ...[
        '-c:a',
        'aac',
        '-b:a',
        '128k',
      ],
      '-movflags',
      '+faststart',
      outputPath,
    ];

    debugPrint('[ReverseProxy] FFmpeg args: $args');
    final completer = Completer<ReturnCode?>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        completer.complete(await session.getReturnCode());
      },
      null,
      (statistics) {
        final progress = statistics.getTime() / (duration * 1000);
        onProgress?.call(progress.clamp(0.0, 1.0).toDouble());
      },
    );

    final returnCode = await completer.future;
    if (ReturnCode.isSuccess(returnCode)) {
      final file = File(outputPath);
      if (await file.exists()) {
        onProgress?.call(1.0);
        return outputPath;
      }
    }

    await FileUtils.deleteFile(outputPath);
    final logs = await session.getLogsAsString();
    throw Exception('Reverse proxy failed: $logs');
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
}
