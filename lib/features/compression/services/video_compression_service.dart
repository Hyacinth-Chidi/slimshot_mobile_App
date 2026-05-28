import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/statistics.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/log.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/stream_information.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../logic/compression_presets.dart';

class VideoCompressionService {
  /// Extract video metadata using ffprobe.
  Future<VideoMetadata?> getVideoMetadata(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final information = session.getMediaInformation();

      if (information == null) return null;

      final streams = information.getStreams();
      StreamInformation? videoStream;

      if (streams.isNotEmpty) {
        for (final s in streams) {
          if (s.getType() == 'video') {
            videoStream = s;
            break;
          }
        }
      }

      if (videoStream == null) return null;

      final width = videoStream.getWidth()?.toInt() ?? 0;
      final height = videoStream.getHeight()?.toInt() ?? 0;
      final codec = videoStream.getCodec() ?? 'unknown';

      int bitrateKbps = 0;
      final bitrateStr = videoStream.getBitrate() ?? information.getBitrate();
      if (bitrateStr != null) {
        bitrateKbps = (int.tryParse(bitrateStr) ?? 0) ~/ 1000;
      }

      double durationSecs = 0;
      final durationStr = information.getDuration();
      if (durationStr != null) {
        durationSecs = double.tryParse(durationStr) ?? 0;
      }

      final metadata = VideoMetadata(
        width: width,
        height: height,
        bitrateKbps: bitrateKbps,
        codec: codec,
        durationSecs: durationSecs,
      );

      debugPrint(
        '📊 Video Analysis: ${metadata.width}x${metadata.height}, '
        '${metadata.bitrateKbps}kbps, codec: ${metadata.codec}, '
        'duration: ${metadata.durationSecs}s',
      );

      return metadata;
    } catch (e) {
      debugPrint('FFprobe error: $e');
      return null;
    }
  }

  /// Build the FFmpeg command based on preset, metadata, and WhatsApp toggle.
  String _buildCommand({
    required String inputPath,
    required String outputPath,
    required CompressionPreset preset,
    required VideoMetadata metadata,
    required bool whatsAppOptimize,
    required bool removeMetadata,
    required String targetFormat,
  }) {
    final StringBuffer cmd = StringBuffer('-y -i "$inputPath" ');

    if (removeMetadata) {
      cmd.write('-map_metadata -1 ');
    }

    switch (preset.id) {
      case 'best_quality':
        cmd.write('-c:v libx264 -preset fast -crf 23 -profile:v high ');
        break;

      case 'smart':
        final int maxRate = _smartMaxBitrate(metadata);
        cmd.write(
          '-c:v libx264 -preset superfast -crf 26 '
          '-maxrate ${maxRate}k -bufsize ${maxRate * 2}k ',
        );
        break;

      case 'smallest':
        final int maxRate = _smallestMaxBitrate(metadata);
        cmd.write(
          '-c:v libx264 -preset ultrafast -crf 32 '
          '-maxrate ${maxRate}k -bufsize ${maxRate * 2}k ',
        );
        break;

      default:
        cmd.write('-c:v libx264 -preset superfast -crf 25 ');
    }

    if (targetFormat == 'webm') {
      cmd.clear();
      cmd.write('-y -i "$inputPath" ');
      if (removeMetadata) cmd.write('-map_metadata -1 ');
      
      switch (preset.id) {
        case 'best_quality':
          cmd.write('-c:v libvpx-vp9 -crf 30 -b:v 0 -cpu-used 4 ');
          break;
        case 'smallest':
          cmd.write('-c:v libvpx-vp9 -crf 45 -b:v 0 -cpu-used 8 ');
          break;
        default:
          cmd.write('-c:v libvpx-vp9 -crf 35 -b:v 0 -cpu-used 6 ');
      }
    }

    if (whatsAppOptimize) {
      final scaleFilter = _shouldDownscaleForWhatsapp(metadata)
          ? '-vf "scale=\'min(1280,iw)\':-2" '
          : '';

      cmd.write(
        '$scaleFilter-pix_fmt yuv420p -profile:v baseline -level 3.1 -r 30 ',
      );
    }

    if (targetFormat == 'webm') {
      cmd.write('-c:a libopus -b:a 96k ');
    } else {
      cmd.write('-c:a aac -b:a 128k ');
    }

    if (targetFormat == 'mp4') {
      cmd.write('-movflags +faststart ');
    }

    cmd.write('"$outputPath"');

    return cmd.toString();
  }

  bool _shouldDownscaleForWhatsapp(VideoMetadata metadata) {
    final maxDim = metadata.width > metadata.height
        ? metadata.width
        : metadata.height;
    return maxDim > 1280;
  }

  /// Max bitrate cap for "Smart Compress" mode (kbps).
  int _smartMaxBitrate(VideoMetadata metadata) {
    switch (metadata.resolutionTier) {
      case '4K':
        return 4000;
      case '1080p':
        return 2500;
      case '720p':
        return 1500;
      default:
        return 1000;
    }
  }

  /// Max bitrate cap for "Smallest Size" mode (kbps).
  int _smallestMaxBitrate(VideoMetadata metadata) {
    switch (metadata.resolutionTier) {
      case '4K':
        return 2500;
      case '1080p':
        return 1500;
      case '720p':
        return 1000;
      default:
        return 600;
    }
  }

  /// Compress a video using the smart engine.
  ///
  /// Returns the output path on success, `null` on failure,
  /// or the original [inputPath] if skipping compression.
  Future<String?> compressVideo({
    required String inputPath,
    required CompressionPreset preset,
    VideoMetadata? metadata,
    bool whatsAppOptimize = false,
    bool removeMetadata = true,
    String targetFormat = 'mp4',
    Function(double progress)? onProgress,
  }) async {
    try {
      if (preset.id == 'best_quality' &&
          metadata != null &&
          metadata.isAlreadyOptimized) {
        debugPrint('⏭ Video already optimized — skipping compression');
        return inputPath; // Return original file
      }


      final appDir = await getTemporaryDirectory();
      final String outputPath =
          '${appDir.path}/slimshot_temp_${const Uuid().v4()}.$targetFormat';

      final effectiveMetadata =
          metadata ??
          const VideoMetadata(
            width: 1920,
            height: 1080,
            bitrateKbps: 5000,
            codec: 'h264',
            durationSecs: 0,
          );

      final String command = _buildCommand(
        inputPath: inputPath,
        outputPath: outputPath,
        preset: preset,
        metadata: effectiveMetadata,
        whatsAppOptimize: whatsAppOptimize,
        removeMetadata: removeMetadata,
        targetFormat: targetFormat,
      );

      debugPrint('🎬 FFmpeg command: ffmpeg $command');

      final Completer<String?> completer = Completer();

      await FFmpegKit.executeAsync(
        command,
        (FFmpegSession session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            debugPrint('✅ FFmpeg compression succeeded');

            final inputFile = File(inputPath);
            final outputFile = File(outputPath);
            if (await outputFile.length() >= await inputFile.length()) {
              debugPrint('⚠️ Output larger than input — returning original');
              await outputFile.delete();
              completer.complete(inputPath);
            } else {
              completer.complete(outputPath);
            }
          } else {
            final output = await session.getOutput();
            debugPrint('❌ FFmpeg compression failed: $output');
            completer.complete(null);
          }
        },
        (Log log) {
        },
        (Statistics statistics) {
          if (onProgress != null) {
            final timeMs = statistics.getTime();
            if (timeMs > 0) {
              if (effectiveMetadata.durationSecs > 0) {
                final progressPct =
                    (timeMs / (effectiveMetadata.durationSecs * 1000)) * 100;
                onProgress(progressPct.clamp(0, 99));
              } else {
                final progressPct = (timeMs / 60000) * 100;
                onProgress(progressPct.clamp(0, 95));
              }
            }
          }
        },
      );

      return completer.future;
    } catch (e) {
      debugPrint('FFmpeg error: $e');
      return null;
    }
  }

  Future<void> cancelCompression() async {
    await FFmpegKit.cancel();
  }
}
