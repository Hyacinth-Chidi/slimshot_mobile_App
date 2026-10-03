import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/utils/file_utils.dart';
import '../logic/captions/caption_grouping.dart';
import '../logic/captions/caption_highlight.dart';
import '../logic/captions/caption_settings.dart';
import '../logic/captions/caption_transcript.dart';
import 'caption_audio_result.dart';
import 'caption_errors.dart';
import 'caption_service.dart';

/// The name of a run's audio file. It carries the temp prefix so the startup
/// sweep finds it: a run killed part-way never reaches its own cleanup.
String captionAudioFileName(DateTime now) =>
    '${FileUtils.filePrefix}captions_${now.millisecondsSinceEpoch}.wav';

/// Where a run is, for the progress sheet.
enum CaptionStage { preparing, uploading, listening, placing }

/// What the caption sheet asked for.
class CaptionRequest {
  const CaptionRequest({
    this.source = CaptionSource.video,
    this.language,
    this.length = CaptionLength.phrase,
    this.highlight = CaptionHighlight.none,
  });

  final CaptionSource source;

  /// ISO 639-1, or null for Auto detect.
  final String? language;
  final CaptionLength length;

  /// How the new set marks the word being spoken.
  final CaptionHighlight highlight;
}

/// Timeline sound → server → caption drafts, one step at a time and
/// cancellable at every one of them.
///
/// Every step arrives as a function so the order, the cancel and the key rule
/// are tested without a device or a network; the screen wires the real ones.
class CaptionPipeline {
  CaptionPipeline({
    required this.audioPath,
    required this.renderAudio,
    required this.startJob,
    required this.awaitJob,
    required this.onCancel,
    Future<void> Function(String path)? deleteFile,
    String Function()? newKey,
  })  : _deleteFile = deleteFile ?? _deleteQuietly,
        _newKey = newKey ?? const Uuid().v4;

  final Future<String> Function() audioPath;
  final Future<CaptionAudioResult> Function(
    String outputPath,
    CaptionSource source,
    void Function(double progress) onProgress,
  ) renderAudio;
  final Future<CaptionJobStart> Function(
    String audioPath,
    String? language,
    String idempotencyKey,
  ) startJob;
  final Future<CaptionTranscript> Function(
    CaptionJobStart job,
    bool Function() isCancelled,
  ) awaitJob;

  /// Stops whatever is in flight: the native render, the upload.
  final void Function() onCancel;

  final Future<void> Function(String path) _deleteFile;
  final String Function() _newKey;

  String? _key;
  bool _cancelled = false;

  Future<List<CaptionDraft>> run(
    CaptionRequest request, {
    required void Function(CaptionStage stage, double? progress) onProgress,
  }) async {
    _cancelled = false;
    var jobStarted = false;
    final path = await audioPath();
    try {
      onProgress(CaptionStage.preparing, 0);
      final audio = await renderAudio(
        path,
        request.source,
        (p) => onProgress(CaptionStage.preparing, p),
      );
      _throwIfCancelled();
      if (!audio.hasSound) throw const CaptionFailure(CaptionFailure.noSound);

      onProgress(CaptionStage.uploading, null);
      final job = await startJob(path, request.language, _key ??= _newKey());
      jobStarted = true;
      _throwIfCancelled();

      onProgress(CaptionStage.listening, null);
      final transcript = await awaitJob(job, () => _cancelled);
      _throwIfCancelled();

      onProgress(CaptionStage.placing, null);
      final drafts = groupCaptionWords(
        rebuildTranscriptSpacing(transcript.text, transcript.words),
        request.length,
        endLimitSeconds: audio.durationSeconds,
      );
      if (drafts.isEmpty) throw const CaptionFailure(CaptionFailure.noSpeech);
      _key = null;
      return drafts;
    } catch (error) {
      if (_cancelled ||
          error is CaptionAudioCancelled ||
          error is CaptionCancelled) {
        throw const CaptionCancelled();
      }
      // A key names one upload. Once the server holds a job for it, the same
      // key answers with that job — a failed one included — so a retry after
      // it needs a fresh key. A retry after an upload that never landed must
      // reuse its key, or a lost response becomes a second job.
      final uploadLost = !jobStarted &&
          error is SlimshotApiException &&
          error.code == SlimshotApiException.network;
      if (!uploadLost) _key = null;
      rethrow;
    } finally {
      await _deleteFile(path);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    onCancel();
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const CaptionCancelled();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone, or never written: nothing to clean up.
    }
  }
}
