import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/services/slimshot_api.dart';
import 'caption_service.dart' show CreditCharge;

export 'caption_service.dart' show CreditCharge;

/// Polling ran for [SpeechService.pollLimit] without an answer.
const String kSpeechPollTimeout = 'SPEECH_POLL_TIMEOUT';

/// The voice run stopped because the user cancelled — never shown as an
/// error.
class SpeechCancelled implements Exception {
  const SpeechCancelled();
}

/// The server finished the job as `failed`: none of its voices was kept, and
/// a paid job's credits are already back by then.
class SpeechJobFailed extends SlimshotApiException {
  const SpeechJobFailed(super.code, [super.message]);
}

/// A voice the owner offers.
class SpeechVoice {
  const SpeechVoice({
    required this.id,
    required this.label,
    required this.sampleUrl,
  });

  final String id;
  final String label;

  /// A short MP3 of the voice, played straight from the server's storage and
  /// free. Never stored: like a font's address it may stop working, and the
  /// list is asked for again whenever the picker opens.
  final String sampleUrl;

  /// A voice as the server lists it, or null when any part is missing — a
  /// voice that cannot be named or heard is not offered.
  static SpeechVoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final label = json['label'];
    final sample = json['sampleUrl'];
    if (id is! String || id.isEmpty) return null;
    if (label is! String || label.trim().isEmpty) return null;
    if (sample is! String) return null;
    final url = Uri.tryParse(sample);
    if (url == null || !(url.isScheme('https') || url.isScheme('http'))) {
      return null;
    }
    return SpeechVoice(id: id, label: label.trim(), sampleUrl: sample);
  }
}

/// One text to speak.
class SpeechItem {
  const SpeechItem({required this.id, required this.text});

  /// The request's own name for the text; the voice is downloaded under it.
  final String id;

  /// Already trimmed: what is sent is exactly what was counted and priced.
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'text': text};
}

/// A speech job the server has accepted.
class SpeechJobStart {
  const SpeechJobStart({
    required this.jobId,
    required this.pollAfter,
    this.charged,
  });

  final String jobId;
  final Duration pollAfter;

  /// Absent for a free request and for a resend of a request the server
  /// still has: nothing was taken.
  final CreditCharge? charged;
}

/// One finished voice: its item id and how long it plays — read from the
/// MP3 itself on the server, so it is the clip's length on the timeline.
class SpokenItem {
  const SpokenItem({required this.id, required this.durationSeconds});

  final String id;
  final double durationSeconds;
}

/// Text to speech on the server (`slimshot_server/docs/app-api/text-to-speech.md`):
/// list the voices, start a job, poll it, download each voice.
class SpeechService {
  SpeechService(
    this._api, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  })  : _delay = delay ?? Future<void>.delayed,
        _clock = clock ?? DateTime.now;

  final SlimshotApi _api;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  /// How long a job may take before the app stops asking.
  static const Duration pollLimit = Duration(minutes: 10);

  static const Duration defaultPollAfter = Duration(milliseconds: 1500);

  /// Polls that may fail in a row before the job is given up on: one dropped
  /// request on a mobile connection says nothing about a job the server is
  /// still working on.
  static const int maxPollFailures = 3;

  /// A voice of the longest text a request may hold is a few megabytes; on a
  /// slow connection the ordinary 20 seconds would cut it off.
  static const Duration downloadTimeout = Duration(minutes: 2);

  /// The voices the owner offers, in the owner's order. Public: browsing
  /// costs nothing and needs no sign-in. An empty list means text to speech
  /// is not offered right now.
  Future<List<SpeechVoice>> voices() async {
    final envelope = await _api.sendPublicEnvelope(
      () => http.Request('GET', _api.uri('/voices')),
    );
    final data = envelope.data;
    if (data is! List) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No voices.',
      );
    }
    return [
      for (final entry in data) ?SpeechVoice.fromJson(entry),
    ];
  }

  /// Starts speaking [items] in [voiceId]. [idempotencyKey] names this
  /// request: sent again with the same key, the server answers with the job
  /// it already has and charges nothing more.
  Future<SpeechJobStart> start({
    required String voiceId,
    required List<SpeechItem> items,
    required String idempotencyKey,
  }) async {
    final data = await _api.send(
      () => _api.jsonRequest('POST', '/speech', {
        'voiceId': voiceId,
        'items': [for (final item in items) item.toJson()],
      })
        ..headers['Idempotency-Key'] = idempotencyKey,
    );
    final jobId = data['jobId'];
    if (jobId is! String || jobId.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No job id.',
      );
    }
    return SpeechJobStart(
      jobId: jobId,
      pollAfter: _pollAfter(data),
      charged: _charged(data['charged']),
    );
  }

  /// Polls [job] until its voices are made, at the pace the server asks for,
  /// and returns each one's length.
  Future<List<SpokenItem>> result(
    SpeechJobStart job, {
    required bool Function() isCancelled,
  }) async {
    final began = _clock();
    var wait = job.pollAfter;
    var failures = 0;
    while (true) {
      if (isCancelled()) throw const SpeechCancelled();
      if (_clock().difference(began) >= pollLimit) {
        throw const SlimshotApiException(kSpeechPollTimeout);
      }
      await _delay(wait);
      if (isCancelled()) throw const SpeechCancelled();

      final Map<String, dynamic> data;
      try {
        data = await _api.send(
          () => http.Request('GET', _api.uri('/speech/${_segment(job.jobId)}')),
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
          return _spoken(data['items']);
        case 'failed':
          final error = data['error'];
          final code = error is Map ? error['code'] : null;
          final message = error is Map ? error['message'] : null;
          throw SpeechJobFailed(
            code is String ? code : 'PROVIDER_FAILED',
            message is String ? message : '',
          );
        default:
          wait = _pollAfter(data);
      }
    }
  }

  /// Downloads the voice of [itemId] in [jobId] into [into], whole or not at
  /// all: written beside it as `.part` and renamed once complete, so a
  /// download cut short never leaves a file that looks like a voice.
  Future<void> download(String jobId, String itemId, File into) async {
    final bytes = await _api.sendForBytes(
      () => http.Request(
        'GET',
        _api.uri('/speech/${_segment(jobId)}/items/${_segment(itemId)}'),
      ),
      timeout: downloadTimeout,
    );
    final part = File('${into.path}.part');
    try {
      await into.parent.create(recursive: true);
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(into.path);
    } catch (_) {
      if (part.existsSync()) await part.delete();
      rethrow;
    }
  }

  static String _segment(String value) => Uri.encodeComponent(value);

  /// A completed job's voices. A voice without an id or a length is not one
  /// the timeline can place, so the answer is refused whole rather than
  /// placing some of the job's voices and silently dropping the rest.
  static List<SpokenItem> _spoken(Object? items) {
    const refused = SlimshotApiException(
      SlimshotApiException.badResponse,
      'No voices.',
    );
    if (items is! List) throw refused;
    final spoken = <SpokenItem>[];
    for (final item in items) {
      final id = item is Map ? item['id'] : null;
      final seconds = item is Map ? item['durationSeconds'] : null;
      if (id is! String || seconds is! num || !seconds.isFinite || seconds <= 0) {
        throw refused;
      }
      spoken.add(SpokenItem(id: id, durationSeconds: seconds.toDouble()));
    }
    return spoken;
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
