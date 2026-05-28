import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:uuid/uuid.dart';

class PrivacyState {
  final bool isProcessing;
  final double progress;
  final String? error;
  final List<XFile> inputFiles;
  final List<String> outputPaths;
  final int currentProcessingIndex;
  final int originalSize;
  final int strippedSize;

  const PrivacyState({
    this.isProcessing = false,
    this.progress = 0.0,
    this.error,
    this.inputFiles = const [],
    this.outputPaths = const [],
    this.currentProcessingIndex = 0,
    this.originalSize = 0,
    this.strippedSize = 0,
  });

  PrivacyState copyWith({
    bool? isProcessing,
    double? progress,
    String? error,
    List<XFile>? inputFiles,
    List<String>? outputPaths,
    int? currentProcessingIndex,
    int? originalSize,
    int? strippedSize,
  }) {
    return PrivacyState(
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      error: error,
      inputFiles: inputFiles ?? this.inputFiles,
      outputPaths: outputPaths ?? this.outputPaths,
      currentProcessingIndex:
          currentProcessingIndex ?? this.currentProcessingIndex,
      originalSize: originalSize ?? this.originalSize,
      strippedSize: strippedSize ?? this.strippedSize,
    );
  }
}

class PrivacyNotifier extends StateNotifier<PrivacyState> {
  PrivacyNotifier() : super(const PrivacyState());

  void reset() {
    if (state.outputPaths.isNotEmpty) {
      for (var path in state.outputPaths) {
        FileUtils.deleteFile(path);
      }
    }
    state = const PrivacyState();
  }

  Future<void> setInputFiles(List<XFile> files) async {
    int totalSize = 0;
    for (var file in files) {
      totalSize += await file.length();
    }
    state = PrivacyState(inputFiles: files, originalSize: totalSize);
  }

  Future<void> stripMetadata() async {
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
      int totalStripped = 0;

      for (int i = 0; i < state.inputFiles.length; i++) {
        if (!state.isProcessing) break;
        state = state.copyWith(
          currentProcessingIndex: i,
          progress: ((i / state.inputFiles.length) * 90).toDouble(),
        );

        final file = state.inputFiles[i];
        final inputPath = file.path;
        final ext = inputPath.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
        final format = ext == '.png' ? CompressFormat.png : CompressFormat.jpeg;
        final outputPath =
            '${appDir.path}/slimshot_temp_privacy_${const Uuid().v4()}$ext';

        final result = await FlutterImageCompress.compressAndGetFile(
          inputPath,
          outputPath,
          quality: 100, // Lossless - preserve quality, only strip metadata
          keepExif: false,
          format: format,
        );

        if (result != null) {
          totalStripped += await result.length();
          results.add(result.path);
        } else {
          throw Exception('Failed to strip metadata from ${file.name}');
        }
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 100,
        outputPaths: results,
        strippedSize: totalStripped,
      );
    } catch (e) {
      debugPrint('PrivacyNotifier error: $e');
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  void cancel() {
    state = PrivacyState(
      inputFiles: state.inputFiles,
      originalSize: state.originalSize,
    );
  }
}

final privacyProvider =
    StateNotifierProvider<PrivacyNotifier, PrivacyState>(
      (ref) => PrivacyNotifier(),
    );
