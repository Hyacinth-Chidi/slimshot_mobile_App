import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../logic/compression_presets.dart';
import '../logic/status_plan.dart';

/// What the compressor does with one video.
sealed class VideoJob {
  const VideoJob();
}

/// Hand the input back as it is: already well compressed for the preset.
class KeepOriginal extends VideoJob {
  const KeepOriginal();
}

/// Run [command]. With [keepIfLarger] the result stands even when it is
/// bigger than the input — a WhatsApp Status file's shape matters more than
/// its size; otherwise a bigger result gives the original back.
class RunFfmpeg extends VideoJob {
  const RunFfmpeg(this.command, {required this.keepIfLarger});
  final String command;
  final bool keepIfLarger;
}

class VideoCompressionService {
  /// Extract video metadata using ffprobe.
  Future<VideoMetadata?> getVideoMetadata(String inputPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final information = session.getMediaInformation();

      if (information == null) return null;

      final metadata = VideoMetadata.fromProbe(
        Map<String, dynamic>.from(information.getAllProperties() ?? const {}),
      );
      if (metadata.width == 0) return null;

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

  /// The job for one video. With [whatsAppStatus] the presets and the format
  /// step aside: the file is made in the shape WhatsApp Status keeps
  /// ([statusPlan]), copied when it already is, and never handed back as it
  /// was — a small 1080×1920 original is exactly the file WhatsApp blurs.
  VideoJob jobFor({
    required String inputPath,
    required String outputPath,
    required CompressionPreset preset,
    required VideoMetadata? metadata,
    required bool whatsAppStatus,
    required bool removeMetadata,
    required String targetFormat,
  }) {
    if (whatsAppStatus) {
      return RunFfmpeg(
        statusCommand(
          statusPlan(metadata),
          input: inputPath,
          output: outputPath,
          removeMetadata: removeMetadata,
        ),
        keepIfLarger: true,
      );
    }
    if (preset.id == 'best_quality' &&
        metadata != null &&
        metadata.isAlreadyOptimized) {
      return const KeepOriginal();
    }
    return RunFfmpeg(
      _buildCommand(
        inputPath: inputPath,
        outputPath: outputPath,
        preset: preset,
        metadata: metadata ??
            const VideoMetadata(
              width: 1920,
              height: 1080,
              bitrateKbps: 5000,
              codec: 'h264',
              durationSecs: 0,
            ),
        removeMetadata: removeMetadata,
        targetFormat: targetFormat,
      ),
      keepIfLarger: false,
    );
  }

  /// The output file's extension: always MP4 for WhatsApp Status.
  String outputExtension({
    required bool whatsAppStatus,
    required String targetFormat,
  }) =>
      whatsAppStatus ? 'mp4' : targetFormat;

  /// The preset's FFmpeg command.
  String _buildCommand({
    required String inputPath,
    required String outputPath,
    required CompressionPreset preset,
    required VideoMetadata metadata,
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
      final inputFile = File(inputPath);
      final appDir = await getTemporaryDirectory();
      final extension = outputExtension(
        whatsAppStatus: whatsAppOptimize,
        targetFormat: targetFormat,
      );
      final String outputPath =
          '${appDir.path}/slimshot_temp_${const Uuid().v4()}.$extension';

      final job = jobFor(
        inputPath: inputPath,
        outputPath: outputPath,
        preset: preset,
        metadata: metadata,
        whatsAppStatus: whatsAppOptimize,
        removeMetadata: removeMetadata,
        targetFormat: targetFormat,
      );
      final RunFfmpeg run;
      switch (job) {
        case KeepOriginal():
          debugPrint('⏭ Video already optimized — skipping compression');
          return inputPath;
        case RunFfmpeg():
          run = job;
      }
      final command = run.command;
      final durationSecs = metadata?.durationSecs ?? 0;

      debugPrint('🎬 FFmpeg command: ffmpeg $command');

      final Completer<String?> completer = Completer();

      await FFmpegKit.executeAsync(
        command,
        (FFmpegSession session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            debugPrint('✅ FFmpeg compression succeeded');

            final outputFile = File(outputPath);

            if (!run.keepIfLarger &&
                await outputFile.length() >= await inputFile.length()) {
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
              if (durationSecs > 0) {
                final progressPct =
                    (timeMs / (durationSecs * 1000)) * 100;
                onProgress(progressPct.clamp(0, 99));
              } else {
                final progressPct = (timeMs / 60000) * 100;
                onProgress(progressPct.clamp(0, 95));
              }
            }
          }
        },
      );

      // Awaited rather than returned: an unawaited return escapes the catch
      // below, so a rejected future would bypass the null this promises. The
      // completer only ever completes with a value today, which makes this
      // latent rather than live — and exactly the kind of thing that becomes
      // live the day someone adds a completeError.
      return await completer.future;
    } catch (e) {
      debugPrint('FFmpeg error: $e');
      return null;
    }
  }

  Future<void> cancelCompression() async {
    await FFmpegKit.cancel();
  }
}
