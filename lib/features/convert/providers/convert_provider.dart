import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:uuid/uuid.dart';

class ConvertState {
  final bool isProcessing;
  final double progress;
  final String? error;
  final List<XFile> inputFiles;
  final List<String> outputPaths;
  final int currentProcessingIndex;
  final int originalSize;
  final int convertedSize;
  final String targetFormat; // 'jpg', 'png', 'webp'

  const ConvertState({
    this.isProcessing = false,
    this.progress = 0.0,
    this.error,
    this.inputFiles = const [],
    this.outputPaths = const [],
    this.currentProcessingIndex = 0,
    this.originalSize = 0,
    this.convertedSize = 0,
    this.targetFormat = 'webp',
  });

  ConvertState copyWith({
    bool? isProcessing,
    double? progress,
    String? error,
    List<XFile>? inputFiles,
    List<String>? outputPaths,
    int? currentProcessingIndex,
    int? originalSize,
    int? convertedSize,
    String? targetFormat,
  }) {
    return ConvertState(
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      error: error,
      inputFiles: inputFiles ?? this.inputFiles,
      outputPaths: outputPaths ?? this.outputPaths,
      currentProcessingIndex:
          currentProcessingIndex ?? this.currentProcessingIndex,
      originalSize: originalSize ?? this.originalSize,
      convertedSize: convertedSize ?? this.convertedSize,
      targetFormat: targetFormat ?? this.targetFormat,
    );
  }

  String get sourceFormat {
    if (inputFiles.isEmpty) return '';
    final ext = inputFiles.first.path.split('.').last.toLowerCase();
    return ext;
  }
}

class ConvertNotifier extends StateNotifier<ConvertState> {
  ConvertNotifier() : super(const ConvertState());

  void reset() {
    if (state.outputPaths.isNotEmpty) {
      for (var path in state.outputPaths) {
        FileUtils.deleteFile(path);
      }
    }
    state = const ConvertState();
  }

  Future<void> setInputFiles(List<XFile> files) async {
    int totalSize = 0;
    for (var file in files) {
      totalSize += await file.length();
    }
    state = ConvertState(inputFiles: files, originalSize: totalSize);
  }

  void setTargetFormat(String format) {
    state = state.copyWith(targetFormat: format);
  }

  Future<void> convertFiles() async {
    if (state.inputFiles.isEmpty) return;

    state = state.copyWith(
      isProcessing: true,
      progress: 0,
      error: null,
      outputPaths: [],
      currentProcessingIndex: 0,
    );

    try {
      final appDir = await getTemporaryDirectory();
      final List<String> results = [];
      int totalConverted = 0;

      CompressFormat compressFormat;
      String outputExt;
      switch (state.targetFormat) {
        case 'png':
          compressFormat = CompressFormat.png;
          outputExt = '.png';
          break;
        case 'jpg':
          compressFormat = CompressFormat.jpeg;
          outputExt = '.jpg';
          break;
        case 'webp':
        default:
          compressFormat = CompressFormat.webp;
          outputExt = '.webp';
          break;
      }

      for (int i = 0; i < state.inputFiles.length; i++) {
        if (!state.isProcessing) break;
        state = state.copyWith(
          currentProcessingIndex: i,
          progress: ((i / state.inputFiles.length) * 90).toDouble(),
        );

        final file = state.inputFiles[i];
        final outputPath =
            '${appDir.path}/slimshot_temp_convert_${const Uuid().v4()}$outputExt';

        final result = await FlutterImageCompress.compressAndGetFile(
          file.path,
          outputPath,
          quality: 95,
          keepExif: false,
          format: compressFormat,
        );

        if (result != null) {
          totalConverted += await result.length();
          results.add(result.path);
        } else {
          throw Exception('Failed to convert ${file.name}');
        }
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 100,
        outputPaths: results,
        convertedSize: totalConverted,
      );
    } catch (e) {
      debugPrint('ConvertNotifier error: $e');
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  void cancel() {
    state = ConvertState(
      inputFiles: state.inputFiles,
      originalSize: state.originalSize,
      targetFormat: state.targetFormat,
    );
  }
}

final convertProvider =
    StateNotifierProvider<ConvertNotifier, ConvertState>(
      (ref) => ConvertNotifier(),
    );
