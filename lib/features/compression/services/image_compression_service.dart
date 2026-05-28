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
      

      final String outputPath =
          '${appDir.path}/slimshot_temp_${const Uuid().v4()}$outputExt';

      final int qualityPos = (preset.quality * 100).round();

      int maxDimension = 1920; // Default (Smart)

      if (preset.id == 'best_quality') {
        maxDimension = 4096; // Effectively keeping original on mobile
      } else if (preset.id == 'smallest') {
        maxDimension = 1280; // Aggressive downscale
      }

      var result = await FlutterImageCompress.compressAndGetFile(
        inputPath,
        outputPath,
        quality: qualityPos,
        minWidth: maxDimension,
        minHeight: maxDimension,
        keepExif: !removeMetadata,
        format: compressFormat,
      );

      return result?.path;
    } catch (e) {
      debugPrint("Error compressing image: $e");
      return null;
    }
  }
}
