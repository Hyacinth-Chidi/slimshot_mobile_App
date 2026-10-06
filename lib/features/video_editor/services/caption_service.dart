import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/captions/caption_transcript.dart';
import 'caption_errors.dart';

/// What an upload took, and the balance after it.
class CreditCharge {
  const CreditCharge({required this.credits, required this.balance});

  final int credits;
  final int balance;
}

/// A caption job the server has accepted.
class CaptionJobStart {
  const CaptionJobStart({
    required this.jobId,
    required this.pollAfter,
    this.charged,
  });

  final String jobId;
  final Duration pollAfter;

  /// Absent for a free job and for a resend of an upload the server still
  /// has: nothing was taken.
  final CreditCharge? charged;
}

/// Auto captions on the server: upload the audio, then poll until the words
/// arrive.
class CaptionService {
  CaptionService(
    this._api, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
    int maxUploadBytes = defaultMaxUploadBytes,
  })  : _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now,
        _maxUploadBytes = maxUploadBytes;

  final SlimshotApi _api;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;
  final int _maxUploadBytes;

  /// The server's own limit. Uncompressed audio is about 2 MB a minute, so
  /// this is some 26 minutes of timeline.
  static const int defaultMaxUploadBytes = 50 * 1024 * 1024;

  /// Minutes of speech, uncompressed (about 2 MB a minute), on a slow
  /// connection.
  static const Duration uploadTimeout = Duration(minutes: 5);

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
    final file = File(audioPath);
    final length = await file.length();
    // What the server would refuse is not sent: the whole upload would be
    // spent to be told no.
    if (length > _maxUploadBytes) {
      throw const SlimshotApiException('PAYLOAD_TOO_LARGE');
    }
    final data = await _api.send(
      () {
        final request = http.MultipartRequest('POST', _api.uri('/captions'))
          ..headers['Idempotency-Key'] = idempotencyKey
          ..files.add(
            // Streamed from the file, not held in memory; opened again
            // for the one retry, since a stream is read once.
            http.MultipartFile(
              'audio',
              file.openRead(),
              length,
              filename: 'captions.wav',
              contentType: MediaType('audio', 'wav'),
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
    return CaptionJobStart(
      jobId: jobId,
      pollAfter: _pollAfter(data),
      charged: _charged(data['charged']),
    );
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
          throw CaptionJobFailed(
            code is String ? code : 'PROVIDER_FAILED',
            message is String ? message : '',
          );
        default:
          wait = _pollAfter(data);
      }
    }
  }

  static CreditCharge? _charged(Object? value) {
    if (value is! Map) return null;
    final credits = value['credits'];
    final balance = value['balance'];
    if (credits is! num || balance is! num) return null;
    return CreditCharge(credits: credits.toInt(), balance: balance.toInt());
  }

  static Duration _pollAfter(Map<String, dynamic> data) {
    final ms = data['pollAfterMs'];
    return ms is num && ms.isFinite && ms > 0
        ? Duration(milliseconds: ms.toInt())
        : defaultPollAfter;
  }
}
