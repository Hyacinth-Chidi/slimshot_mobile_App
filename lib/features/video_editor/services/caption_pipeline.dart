import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/utils/file_utils.dart';
import '../../account/models/account_models.dart';
import '../logic/captions/caption_grouping.dart';
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
enum CaptionStage { preparing, pricing, uploading, listening, placing }

/// What the caption sheet asked for.
class CaptionRequest {
  const CaptionRequest({
    this.source = CaptionSource.video,
    this.language,
    this.length = CaptionLength.phrase,
  });

  final CaptionSource source;

  /// ISO 639-1, or null for Auto detect.
  final String? language;
  final CaptionLength length;
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
    required this.quotePrice,
    required this.startJob,
    required this.awaitJob,
    required this.onCancel,
    this.onCharged,
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

  /// What the rendered audio will cost — always asked, never worked out.
  final Future<CreditQuote> Function(double durationSeconds) quotePrice;

  /// The balance an upload's charge left, for the home pill.
  final void Function(int balance)? onCharged;

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

  /// [confirmPrice] is asked before a paid upload; without one a paid run
  /// never uploads. A free run is not asked.
  Future<List<CaptionDraft>> run(
    CaptionRequest request, {
    required void Function(CaptionStage stage, double? progress) onProgress,
    Future<bool> Function(CreditQuote quote)? confirmPrice,
  }) async {
    _cancelled = false;
    var jobStarted = false;
    var paid = false;
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

      onProgress(CaptionStage.pricing, null);
      final quote = await quotePrice(audio.durationSeconds);
      _throwIfCancelled();
      if (!quote.isFree) {
        final approved = confirmPrice != null && await confirmPrice(quote);
        if (!approved || _cancelled) {
          // Nothing was uploaded for this audio, so no key belongs to it.
          _key = null;
          throw const CaptionCancelled();
        }
      }

      onProgress(CaptionStage.uploading, null);
      final job = await _upload(path, request.language);
      jobStarted = true;
      final charged = job.charged;
      if (charged != null) {
        paid = charged.credits > 0;
        onCharged?.call(charged.balance);
      }
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
      // The server refunds a failed paid job itself; say so.
      if (paid && error is CaptionJobFailed) {
        throw const CaptionFailure(CaptionFailure.refunded);
      }
      rethrow;
    } finally {
      await _deleteFile(path);
    }
  }

  /// Uploads under this run's key. A key that already paid for an earlier
  /// upload whose job is gone is refused with nothing charged; it is replaced
  /// once, and a second refusal is the server's to explain.
  Future<CaptionJobStart> _upload(String path, String? language) async {
    try {
      return await startJob(path, language, _key ??= _newKey());
    } on SlimshotApiException catch (e) {
      if (e.code != 'IDEMPOTENCY_KEY_REUSED') rethrow;
      _key = _newKey();
      return startJob(path, language, _key!);
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
