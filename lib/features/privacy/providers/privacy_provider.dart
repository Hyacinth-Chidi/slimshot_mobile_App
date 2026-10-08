import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/core/utils/file_utils.dart';

import '../logic/photo_metadata.dart';
import '../services/photo_metadata_service.dart';
import '../services/photo_stripper.dart';

export '../services/photo_stripper.dart' show PhotoStripper;

class PrivacyState {
  final bool isProcessing;
  final double progress;
  final String? error;
  final List<XFile> inputFiles;
  final List<String> outputPaths;
  final int currentProcessingIndex;
  final int originalSize;
  final int strippedSize;

  /// What each picked photo carries, read when they were picked; null while
  /// still being read. An entry is null where a file could not be read.
  final List<PhotoMetadata?>? found;

  /// What each cleaned file still carries, read back after the strip — the
  /// report shows this, never an assumption that the strip worked.
  final List<PhotoMetadata?>? remaining;

  const PrivacyState({
    this.isProcessing = false,
    this.progress = 0.0,
    this.error,
    this.inputFiles = const [],
    this.outputPaths = const [],
    this.currentProcessingIndex = 0,
    this.originalSize = 0,
    this.strippedSize = 0,
    this.found,
    this.remaining,
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
    List<PhotoMetadata?>? found,
    List<PhotoMetadata?>? remaining,
    bool clearRemaining = false,
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
      found: found ?? this.found,
      remaining: clearRemaining ? null : remaining ?? this.remaining,
    );
  }
}

class PrivacyNotifier extends StateNotifier<PrivacyState> {
  PrivacyNotifier({
    required PhotoMetadataService reader,
    required PhotoStripper stripper,
  })  : _reader = reader,
        _stripper = stripper,
        super(const PrivacyState());

  final PhotoMetadataService _reader;
  final PhotoStripper _stripper;

  /// Bumped by each run and each cancel, so a cancelled run's late results
  /// are never written.
  int _run = 0;

  void reset() {
    _run++;
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
    final found = await Future.wait([for (final f in files) _reader.read(f.path)]);
    if (!identical(state.inputFiles, files)) return; // replaced meanwhile
    state = state.copyWith(found: found);
  }

  Future<void> stripMetadata() async {
    if (state.inputFiles.isEmpty) return;
    final run = ++_run;
    final files = state.inputFiles;

    state = state.copyWith(
      isProcessing: true,
      progress: 0,
      error: null,
      outputPaths: [],
      currentProcessingIndex: 0,
      clearRemaining: true,
    );

    try {
      final results = <String>[];
      final remaining = <PhotoMetadata?>[];
      var totalStripped = 0;

      for (var i = 0; i < files.length; i++) {
        state = state.copyWith(
          currentProcessingIndex: i,
          progress: (i / files.length) * 100,
        );
        final path = await _stripper.strip(files[i].path);
        if (run != _run) return; // cancelled
        results.add(path);
        totalStripped += await XFile(path).length();
        remaining.add(await _reader.read(path));
        if (run != _run) return;
      }

      state = state.copyWith(
        isProcessing: false,
        progress: 100,
        outputPaths: results,
        strippedSize: totalStripped,
        remaining: remaining,
      );
    } catch (e) {
      debugPrint('PrivacyNotifier error: $e');
      if (run != _run) return;
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  void cancel() {
    _run++;
    state = PrivacyState(
      inputFiles: state.inputFiles,
      originalSize: state.originalSize,
      found: state.found,
    );
  }
}

final privacyProvider = StateNotifierProvider<PrivacyNotifier, PrivacyState>(
  (ref) => PrivacyNotifier(
    reader: ref.watch(photoMetadataServiceProvider),
    stripper: ref.watch(photoStripperProvider),
  ),
);
