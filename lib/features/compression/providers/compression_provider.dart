import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../services/video_compression_service.dart';
import '../services/image_compression_service.dart';
import '../logic/compression_presets.dart';
import 'package:slimshotai/core/utils/file_utils.dart';

class CompressionState {
  final bool isProcessing;
  final double progress; // 0.0 - 100.0 for current file
  final String? error;
  final List<XFile> inputFiles;
  final List<String> outputPaths;
  final int currentProcessingIndex;
  final int originalSize;
  final int compressedSize;
  final CompressionPreset? selectedPreset;
  final VideoMetadata? videoMetadata; // For the *first* video previewed
  final bool whatsAppOptimize;
  final List<bool> skippedCompressions; // true if video was already optimized
  final bool removeMetadata;
  final String targetImageFormat; // 'jpg', 'png', 'webp'
  final String targetVideoFormat; // 'mp4', 'webm'

  const CompressionState({
    this.isProcessing = false,
    this.progress = 0.0,
    this.error,
    this.inputFiles = const [],
    this.outputPaths = const [],
    this.currentProcessingIndex = 0,
    this.originalSize = 0,
    this.compressedSize = 0,
    this.selectedPreset,
    this.videoMetadata,
    this.whatsAppOptimize = false,
    this.skippedCompressions = const [],
    this.removeMetadata = true,
    this.targetImageFormat = 'jpg',
    this.targetVideoFormat = 'mp4',
  });

  CompressionState copyWith({
    bool? isProcessing,
    double? progress,
    String? error,
    List<XFile>? inputFiles,
    List<String>? outputPaths,
    int? currentProcessingIndex,
    int? originalSize,
    int? compressedSize,
    CompressionPreset? selectedPreset,
    VideoMetadata? videoMetadata,
    bool? whatsAppOptimize,
    List<bool>? skippedCompressions,
    bool? removeMetadata,
    String? targetImageFormat,
    String? targetVideoFormat,
  }) {
    return CompressionState(
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      error: error, // Nullable update
      inputFiles: inputFiles ?? this.inputFiles,
      outputPaths: outputPaths ?? this.outputPaths,
      currentProcessingIndex: currentProcessingIndex ?? this.currentProcessingIndex,
      originalSize: originalSize ?? this.originalSize,
      compressedSize: compressedSize ?? this.compressedSize,
      selectedPreset: selectedPreset ?? this.selectedPreset,
      videoMetadata: videoMetadata ?? this.videoMetadata,
      whatsAppOptimize: whatsAppOptimize ?? this.whatsAppOptimize,
      skippedCompressions: skippedCompressions ?? this.skippedCompressions,
      removeMetadata: removeMetadata ?? this.removeMetadata,
      targetImageFormat: targetImageFormat ?? this.targetImageFormat,
      targetVideoFormat: targetVideoFormat ?? this.targetVideoFormat,
    );
  }
}

class CompressionNotifier extends StateNotifier<CompressionState> {
  final VideoCompressionService _videoService;
  final ImageCompressionService _imageService;

  CompressionNotifier(this._videoService, this._imageService)
    : super(const CompressionState());

  /// The run whose results may reach the screen. Each compression takes the
  /// next number and Cancel retires the current one, so a run only ever
  /// writes state while it is [_isCurrent]. Every run used to ask "is *a*
  /// compression running?" — and a cancelled one, its FFmpeg call ending late
  /// as a failure, saw the restarted run's "running", marked it failed and
  /// stopped, and its progress landed on the new run's ring.
  int _run = 0;

  bool _isCurrent(int run) => mounted && run == _run;

  void setInputFiles(List<XFile> files, {CompressionPreset? defaultPreset}) async {
    int totalSize = 0;
    for (var file in files) {
      totalSize += await file.length();
    }
    state = CompressionState(
      inputFiles: files,
      originalSize: totalSize,
      selectedPreset: defaultPreset,
    );
  }

  /// Analyze the first video metadata after file is set. Called from the screen.
  Future<void> analyzeFirstVideo() async {
    if (state.inputFiles.isEmpty) return;
    final metadata = await _videoService.getVideoMetadata(state.inputFiles.first.path);
    if (metadata != null) {
      state = state.copyWith(videoMetadata: metadata);
    }
  }

  void selectPreset(CompressionPreset preset) {
    state = state.copyWith(selectedPreset: preset);
  }

  void toggleWhatsAppOptimize() {
    state = state.copyWith(whatsAppOptimize: !state.whatsAppOptimize);
  }

  void toggleRemoveMetadata() {
    state = state.copyWith(removeMetadata: !state.removeMetadata);
  }

  void setTargetImageFormat(String format) {
    state = state.copyWith(targetImageFormat: format);
  }

  void setTargetVideoFormat(String format) {
    state = state.copyWith(targetVideoFormat: format);
  }

  Future<void> compressVideo() async {
    if (state.inputFiles.isEmpty || state.selectedPreset == null) return;
    final run = ++_run;

    state = state.copyWith(
      isProcessing: true,
      progress: 0,
      error: null,
      skippedCompressions: [],
      outputPaths: [],
      currentProcessingIndex: 0,
      compressedSize: 0,
    );

    try {
      List<String> results = [];
      List<bool> skipped = [];
      int totalCompressed = 0;

      for (int i = 0; i < state.inputFiles.length; i++) {
        if (!_isCurrent(run)) break; // Cancelled

        state = state.copyWith(currentProcessingIndex: i, progress: 5);
        final file = state.inputFiles[i];

        VideoMetadata? currentMetadata = i == 0 ? state.videoMetadata : await _videoService.getVideoMetadata(file.path);
        if (!_isCurrent(run)) break;

        final resultPath = await _videoService.compressVideo(
          inputPath: file.path,
          preset: state.selectedPreset!,
          metadata: currentMetadata,
          whatsAppOptimize: state.whatsAppOptimize,
          removeMetadata: state.removeMetadata,
          targetFormat: state.targetVideoFormat,
          onProgress: (progressPct) {
            if (_isCurrent(run) && state.currentProcessingIndex == i) {
              final p = progressPct.clamp(5.0, 95.0);
              state = state.copyWith(progress: p);
            }
          },
        );

        if (!_isCurrent(run)) {
          // Finished, or ended as a failure, after Cancel: nobody wants it.
          if (resultPath != null && resultPath != file.path) {
            FileUtils.deleteFile(resultPath);
          }
          break;
        }
        if (resultPath != null) {
          final compressedFile = XFile(resultPath);
          totalCompressed += await compressedFile.length();
          results.add(resultPath);
          skipped.add(resultPath == file.path);
        } else {
          throw Exception('Compression failed for file ${file.name}');
        }
      }

      if (_isCurrent(run)) {
        state = state.copyWith(
          isProcessing: false,
          progress: 100,
          outputPaths: results,
          compressedSize: totalCompressed,
          skippedCompressions: skipped,
        );
      } else {
        for (var i = 0; i < results.length; i++) {
          if (!skipped[i]) FileUtils.deleteFile(results[i]);
        }
      }
    } catch (e) {
      if (_isCurrent(run)) {
        state = state.copyWith(isProcessing: false, error: e.toString());
      }
    }
  }

  Future<void> compressImage() async {
    if (state.inputFiles.isEmpty || state.selectedPreset == null) return;
    final run = ++_run;

    state = state.copyWith(
      isProcessing: true, 
      progress: 0, 
      error: null,
      outputPaths: [],
      currentProcessingIndex: 0,
      compressedSize: 0,
    );

    try {
      List<String> results = [];
      int totalCompressed = 0;

      for (int i = 0; i < state.inputFiles.length; i++) {
        if (!_isCurrent(run)) break; // Cancelled
        
        state = state.copyWith(currentProcessingIndex: i, progress: 20);
        final file = state.inputFiles[i];

        final resultPath = await _imageService.compressImage(
          inputPath: file.path,
          preset: state.selectedPreset!,
          removeMetadata: state.removeMetadata,
          targetFormat: state.targetImageFormat,
        );

        if (!_isCurrent(run)) {
          if (resultPath != null) FileUtils.deleteFile(resultPath);
          break;
        }
        state = state.copyWith(progress: 80);

        if (resultPath != null) {
          final compressedFile = XFile(resultPath);
          totalCompressed += await compressedFile.length();
          results.add(resultPath);
        } else {
          throw Exception('Compression failed for file ${file.name}');
        }
      }

      if (_isCurrent(run)) {
        state = state.copyWith(
          isProcessing: false,
          progress: 100,
          outputPaths: results,
          compressedSize: totalCompressed,
        );
      } else {
        for (final path in results) {
          FileUtils.deleteFile(path);
        }
      }
    } catch (e) {
      if (_isCurrent(run)) {
        state = state.copyWith(isProcessing: false, error: e.toString());
      }
    }
  }

  Future<void> cancelCompression() async {
    // Retired before anything is awaited, so nothing the cancelled run does
    // from here on reaches the screen.
    _run++;
    await _videoService.cancelCompression();
    if (!mounted) return;
    state = CompressionState(
      inputFiles: state.inputFiles,
      originalSize: state.originalSize,
      selectedPreset: state.selectedPreset,
      videoMetadata: state.videoMetadata,
      whatsAppOptimize: state.whatsAppOptimize,
      removeMetadata: state.removeMetadata,
      targetImageFormat: state.targetImageFormat,
      targetVideoFormat: state.targetVideoFormat,
    );
  }

  void reset() {
    _run++;
    if (state.outputPaths.isNotEmpty) {
      for (var path in state.outputPaths) {
        FileUtils.deleteFile(path);
      }
    }
    state = const CompressionState();
  }
}

final videoCompressionServiceProvider = Provider(
  (ref) => VideoCompressionService(),
);
final imageCompressionServiceProvider = Provider(
  (ref) => ImageCompressionService(),
);

final compressionProvider =
    StateNotifierProvider<CompressionNotifier, CompressionState>((ref) {
      return CompressionNotifier(
        ref.watch(videoCompressionServiceProvider),
        ref.watch(imageCompressionServiceProvider),
      );
    });
