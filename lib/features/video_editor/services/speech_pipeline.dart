import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/services/slimshot_api.dart';
import '../../account/models/account_models.dart';
import '../logic/speech/speech_request.dart';
import '../logic/speech/voice_clip.dart';
import 'speech_errors.dart';
import 'speech_service.dart';

/// Where a run is, for the sheet.
enum SpeechStage { speaking, downloading }

/// A Generate's texts → the server → voice files on the phone, one step at
/// a time and cancellable at every one of them.
///
/// Every step arrives as a function so the order, the cancel and the key rule
/// are tested without a network; the editor wires the real ones. The rules
/// are Auto captions' (`CaptionPipeline`), because the purchase is the same
/// kind: priced silently, a key held until the server is known to hold a
/// failed job for it, a refund said when a paid job fails.
class SpeechPipeline {
  SpeechPipeline({
    required this.quotePrice,
    required this.startJob,
    required this.awaitJob,
    required this.download,
    required this.onCancel,
    this.onCharged,
    Future<void> Function(String path)? deleteFile,
    String Function()? newKey,
  })  : _deleteFile = deleteFile ?? _deleteQuietly,
        _newKey = newKey ?? const Uuid().v4;

  /// What the texts will cost — always asked, never worked out.
  final Future<CreditQuote> Function(int characters) quotePrice;

  final Future<SpeechJobStart> Function(
    String voiceId,
    List<SpeechItem> items,
    String idempotencyKey,
  ) startJob;

  final Future<List<SpokenItem>> Function(
    SpeechJobStart job,
    bool Function() isCancelled,
  ) awaitJob;

  /// Saves the voice of [itemId] for the text [textId] into the project and
  /// returns its path.
  final Future<String> Function(String jobId, String itemId, String textId)
      download;

  /// Stops whatever is in flight.
  final void Function() onCancel;

  /// The balance a request's charge left, for the home pill.
  final void Function(int balance)? onCharged;

  final Future<void> Function(String path) _deleteFile;
  final String Function() _newKey;

  String? _key;

  /// The request the held key was made for: a key is good for that request
  /// alone, since the server answers a held key with the job it already has.
  String? _keyRequest;

  /// Whether the held key's request was priced or charged, so a failed job
  /// under it says its credits came back even when the answer that carried
  /// the charge was lost.
  bool _keyPaid = false;

  bool _cancelled = false;

  /// The price is checked silently (the owner's call for Auto captions,
  /// applied to the same kind of purchase): a run the balance covers goes
  /// straight on. [onShortfall] is told when it does not, and answers whether
  /// the run may go on after all (an ad earned the difference); without one,
  /// a short run never starts.
  Future<List<VoiceClip>> run(
    String voiceId,
    SpeechReady plan, {
    required void Function(SpeechStage stage) onProgress,
    Future<bool> Function(CreditQuote quote)? onShortfall,
  }) async {
    _cancelled = false;
    // The server's ids are the request's own, by position: valid whatever a
    // text's id looks like, and the same for a resend of the same plan.
    final items = [
      for (final (i, target) in plan.targets.indexed)
        SpeechItem(id: 't$i', text: target.text),
    ];
    final request = jsonEncode({
      'voiceId': voiceId,
      'items': [for (final item in items) item.toJson()],
    });
    if (_key != null && _keyRequest != request) _forgetKey();

    final saved = <String>[];
    try {
      onProgress(SpeechStage.speaking);
      // A held key is a request the user already said Generate to, which may
      // have landed and been charged. The server charges at most once per
      // key and a resend gets that job back for nothing, so it is not priced
      // again: a fresh quote could read the balance the request already took
      // and strand the credits it paid.
      var priced = false;
      if (_key == null) {
        final quote = await quotePrice(plan.characters);
        _throwIfCancelled();
        if (!quote.isFree && !quote.enough) {
          final covered = onShortfall != null && await onShortfall(quote);
          if (!covered || _cancelled) throw const SpeechCancelled();
        }
        priced = !quote.isFree;
      }

      final job = await _start(voiceId, items, request, priced: priced);
      final charged = job.charged;
      if (charged != null) {
        if (charged.credits > 0) _keyPaid = true;
        onCharged?.call(charged.balance);
      }
      _throwIfCancelled();

      final spoken = await awaitJob(job, () => _cancelled);
      _throwIfCancelled();
      final byId = {for (final s in spoken) s.id: s};
      final voices = [
        for (final item in items)
          byId[item.id] ??
              (throw const SlimshotApiException(
                SlimshotApiException.badResponse,
                'A voice is missing.',
              )),
      ];

      onProgress(SpeechStage.downloading);
      final clips = <VoiceClip>[];
      for (final (i, target) in plan.targets.indexed) {
        final path = await download(job.jobId, items[i].id, target.textId);
        saved.add(path);
        _throwIfCancelled();
        clips.add(VoiceClip(
          textId: target.textId,
          filePath: path,
          durationSeconds: voices[i].durationSeconds,
          startSeconds: target.startSeconds,
        ));
      }
      _forgetKey();
      return clips;
    } catch (error) {
      // Voices that arrived for a run that will not place them.
      for (final path in saved) {
        await _deleteFile(path);
      }
      if (_cancelled || error is SpeechCancelled) throw const SpeechCancelled();
      final paid = _keyPaid;
      // A key names one request, and is kept until the server is known to
      // hold a failed job for it. Kept, a resend is free: the server answers
      // with the job it has — a finished one's voices are its for an hour,
      // so a download that failed is fetched again under the same key — or
      // never saw the key, or refuses it (and `_start` takes a fresh one).
      // Only a failed job needs a fresh key: the same key would answer with
      // that failure.
      if (error is SpeechJobFailed ||
          (error is SlimshotApiException &&
              error.code == 'IDEMPOTENCY_KEY_REUSED')) {
        _forgetKey();
      }
      // The server refunds a failed paid job itself; say so.
      if (paid && error is SpeechJobFailed) {
        throw const SpeechFailure(SpeechFailure.refunded);
      }
      rethrow;
    }
  }

  /// Starts under this run's key. A key whose job is gone is refused with
  /// nothing charged; it is replaced once, and a second refusal is the
  /// server's to explain.
  Future<SpeechJobStart> _start(
    String voiceId,
    List<SpeechItem> items,
    String request, {
    required bool priced,
  }) async {
    if (_key == null) {
      _key = _newKey();
      _keyRequest = request;
      _keyPaid = priced;
    }
    try {
      return await startJob(voiceId, items, _key!);
    } on SlimshotApiException catch (e) {
      if (e.code != 'IDEMPOTENCY_KEY_REUSED') rethrow;
      _key = _newKey();
      return startJob(voiceId, items, _key!);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    onCancel();
  }

  void _forgetKey() {
    _key = null;
    _keyRequest = null;
    _keyPaid = false;
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const SpeechCancelled();
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone, or never written: nothing to clean up.
    }
  }
}
