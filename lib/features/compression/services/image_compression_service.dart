import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../logic/compression_presets.dart';

class ImageCompressionService {
  Future<String?> compressImage({
    required String inputPath,
    required CompressionPreset preset,
    bool removeMetadata = true,
    String targetFormat = 'jpg',
    int? targetSizeBytes,
  }) async {
    try {
      final appDir = await getTemporaryDirectory();

      CompressFormat compressFormat = CompressFormat.jpeg;
      String outputExt = '.jpg';

      if (targetFormat == 'webp') {
        compressFormat = CompressFormat.webp;
        outputExt = '.webp';
      } else if (targetFormat == 'png') {
        compressFormat = CompressFormat.png;
        outputExt = '.png';
      }

      final qualityPos = (preset.quality * 100).round();
      final maxDimension = _maxDimensionForPreset(preset);

      if (targetSizeBytes != null) {
        final inputFile = File(inputPath);
        if (await inputFile.length() <= targetSizeBytes) {
          return inputPath;
        }

        return _compressToTargetSize(
          inputPath: inputPath,
          outputExt: outputExt,
          compressFormat: compressFormat,
          initialQuality: qualityPos,
          maxDimension: maxDimension,
          keepExif: !removeMetadata,
          targetSizeBytes: targetSizeBytes,
        );
      }

      final outputPath =
          '${appDir.path}/slimshot_temp_${const Uuid().v4()}$outputExt';
      final result = await _compressOnce(
        inputPath: inputPath,
        outputPath: outputPath,
        quality: qualityPos,
        maxDimension: maxDimension,
        keepExif: !removeMetadata,
        compressFormat: compressFormat,
      );

      return result?.path;
    } catch (e) {
      debugPrint("Error compressing image: $e");
      return null;
    }
  }

  int _maxDimensionForPreset(CompressionPreset preset) {
    if (preset.id == 'best_quality') {
      return 4096;
    }
    if (preset.id == 'smallest') {
      return 1280;
    }
    return 1920;
  }

  Future<XFile?> _compressOnce({
    required String inputPath,
    required String outputPath,
    required int quality,
    required int maxDimension,
    required bool keepExif,
    required CompressFormat compressFormat,
  }) {
    return FlutterImageCompress.compressAndGetFile(
      inputPath,
      outputPath,
      quality: quality,
      minWidth: maxDimension,
      minHeight: maxDimension,
      keepExif: keepExif,
      format: compressFormat,
    );
  }

  Future<String?> _compressToTargetSize({
    required String inputPath,
    required String outputExt,
    required CompressFormat compressFormat,
    required int initialQuality,
    required int maxDimension,
    required bool keepExif,
    required int targetSizeBytes,
  }) async {
    final appDir = await getTemporaryDirectory();
    String? smallestPath;
    int? smallestSize;

    for (final dimension in _dimensionSteps(maxDimension)) {
      for (final quality in _qualitySteps(initialQuality)) {
        final outputPath =
            '${appDir.path}/slimshot_temp_${const Uuid().v4()}$outputExt';
        final result = await _compressOnce(
          inputPath: inputPath,
          outputPath: outputPath,
          quality: quality,
          maxDimension: dimension,
          keepExif: keepExif,
          compressFormat: compressFormat,
        );

        if (result == null) continue;

        final outputFile = File(result.path);
        final outputSize = await outputFile.length();
        if (outputSize <= targetSizeBytes) {
          if (smallestPath != null) {
            await _deleteQuietly(smallestPath);
          }
          return result.path;
        }

        if (smallestSize == null || outputSize < smallestSize) {
          if (smallestPath != null) {
            await _deleteQuietly(smallestPath);
          }
          smallestPath = result.path;
          smallestSize = outputSize;
        } else {
          await _deleteQuietly(result.path);
        }
      }
    }

    if (smallestPath != null) {
      await _deleteQuietly(smallestPath);
    }
    return null;
  }

  List<int> _qualitySteps(int initialQuality) {
    final steps = <int>{
      initialQuality.clamp(35, 95),
      85,
      75,
      65,
      55,
      45,
      35,
      28,
      22,
    }.toList();
    steps.sort((a, b) => b.compareTo(a));
    return steps;
  }

  List<int> _dimensionSteps(int maxDimension) {
    final steps = <int>{
      maxDimension,
      2560,
      1920,
      1600,
      1280,
      1024,
      800,
      640,
      480,
    }.where((dimension) => dimension <= maxDimension).toList();
    steps.sort((a, b) => b.compareTo(a));
    return steps;
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort cleanup for failed target-size attempts.
    }
  }
}
