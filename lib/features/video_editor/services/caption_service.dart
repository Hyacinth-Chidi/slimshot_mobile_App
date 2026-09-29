import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/captions/caption_transcript.dart';
import 'caption_errors.dart';

/// A caption job the server has accepted.
class CaptionJobStart {
  const CaptionJobStart({required this.jobId, required this.pollAfter});

  final String jobId;
  final Duration pollAfter;
}

/// Auto captions on the server: upload the audio, then poll until the words
/// arrive.
class CaptionService {
  CaptionService(
    this._api, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  })  : _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final SlimshotApi _api;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  /// Minutes of speech on a slow connection.
  static const Duration uploadTimeout = Duration(seconds: 120);

  /// How long a job may take before the app stops asking. The server keeps a
  /// finished result for 180s, so a job that is merely late is never given up
  /// on early.
  static const Duration pollLimit = Duration(minutes: 10);

  static const Duration defaultPollAfter = Duration(milliseconds: 1500);

  /// Polls that may fail in a row before the job is given up on. One dropped
  /// request on a mobile connection says nothing about a job the server is
  /// still working on, and giving up on it means uploading it again.
  static const int maxPollFailures = 3;

  /// Uploads [audioPath] and returns the job. [idempotencyKey] names this
  /// upload: sent again with the same key, the server answers with the same
  /// job instead of starting a second one.
  Future<CaptionJobStart> start({
    required String audioPath,
    String? language,
    required String idempotencyKey,
  }) async {
    final bytes = await File(audioPath).readAsBytes();
    final data = await _api.send(
      () {
        final request = http.MultipartRequest('POST', _api.uri('/captions'))
          ..headers['Idempotency-Key'] = idempotencyKey
          ..files.add(
            http.MultipartFile.fromBytes(
              'audio',
              bytes,
              filename: 'captions.m4a',
              contentType: MediaType('audio', 'mp4'),
            ),
          );
        if (language != null) request.fields['language'] = language;
        return request;
      },
      timeout: uploadTimeout,
    );
    final jobId = data['jobId'];
    if (jobId is! String || jobId.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No job id.',
      );
    }
    return CaptionJobStart(jobId: jobId, pollAfter: _pollAfter(data));
  }

  /// Polls [job] until its words arrive, at the pace the server asks for.
  Future<CaptionTranscript> result(
    CaptionJobStart job, {
    required bool Function() isCancelled,
  }) async {
    final began = _clock();
    var wait = job.pollAfter;
    var failures = 0;
    while (true) {
      if (isCancelled()) throw const CaptionCancelled();
      if (_clock().difference(began) >= pollLimit) {
        throw const SlimshotApiException(kCaptionPollTimeout);
      }
      await _delay(wait);
      if (isCancelled()) throw const CaptionCancelled();

      final Map<String, dynamic> data;
      try {
        data = await _api.send(
          () => http.Request('GET', _api.uri('/captions/${job.jobId}')),
        );
        failures = 0;
      } on SlimshotApiException catch (e) {
        if (e.code != SlimshotApiException.network ||
            ++failures >= maxPollFailures) {
          rethrow;
        }
        continue;
      }
      switch (data['status']) {
        case 'completed':
          final result = data['result'];
          if (result is! Map) {
            throw const SlimshotApiException(
              SlimshotApiException.badResponse,
              'No result.',
            );
          }
          return CaptionTranscript.fromJson(Map<String, dynamic>.from(result));
        case 'failed':
          final error = data['error'];
          final code = error is Map ? error['code'] : null;
          final message = error is Map ? error['message'] : null;
          throw SlimshotApiException(
            code is String ? code : 'PROVIDER_FAILED',
            message is String ? message : '',
          );
        default:
          wait = _pollAfter(data);
      }
    }
  }

  static Duration _pollAfter(Map<String, dynamic> data) {
    final ms = data['pollAfterMs'];
    return ms is num && ms > 0
        ? Duration(milliseconds: ms.toInt())
        : defaultPollAfter;
  }
}
