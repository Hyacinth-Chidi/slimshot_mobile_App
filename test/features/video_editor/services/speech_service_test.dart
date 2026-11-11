import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/video_editor/services/speech_service.dart';

import '../../../support/account_fakes.dart';
import '../../../support/fake_server.dart';

Matcher throwsCode(String code) => throwsA(
      isA<SlimshotApiException>().having((e) => e.code, 'code', code),
    );

void main() {
  late FakeServer server;
  late List<Duration> waits;
  setUp(() {
    server = FakeServer();
    waits = [];
  });

  SpeechService service({DateTime Function()? clock, bool signedIn = true}) =>
      SpeechService(
        fakeApi(
          server,
          session: signedIn ? signedInSession(access: 'a1', refresh: 'r1') : null,
        ),
        delay: (wait) async => waits.add(wait),
        clock: clock,
      );

  const job = SpeechJobStart(
    jobId: 'tts_1',
    pollAfter: Duration(milliseconds: 1500),
  );

  /// Answers the poll with [answers] in turn; the last one repeats.
  void pollAnswers(List<http.Response Function()> answers) {
    var asked = 0;
    server.on('GET', '/speech/tts_1', (_) {
      final answer = answers[asked < answers.length ? asked : answers.length - 1];
      asked++;
      return answer();
    });
  }

  http.Response working([int pollAfterMs = 1500]) => envelope(
        {'jobId': 'tts_1', 'status': 'processing', 'pollAfterMs': pollAfterMs},
      );

  http.Response done() => envelope({
        'jobId': 'tts_1',
        'status': 'completed',
        'items': [
          {'id': 't0', 'durationSeconds': 2.448},
          {'id': 't1', 'durationSeconds': 3.072},
        ],
      });

  http.Response dropped() => throw http.ClientException('connection reset');

  test('lists the voices the server offers, skipping malformed ones', () async {
    server.on(
      'GET',
      '/voices',
      (_) => envelope([
        {'id': 'v1', 'label': 'Eve', 'sampleUrl': 'https://cdn.test/eve.mp3'},
        {'id': 'v2', 'sampleUrl': 'https://cdn.test/no-name.mp3'},
        {'id': '', 'label': 'Nobody', 'sampleUrl': 'https://cdn.test/x.mp3'},
        {'id': 'v4', 'label': 'Mute'},
        {'id': 'v5', 'label': 'Odd', 'sampleUrl': 'not a url'},
        'junk',
        {'id': 'v3', 'label': 'Rex', 'sampleUrl': 'https://cdn.test/rex.mp3'},
      ]),
    );

    final voices = await service(signedIn: false).voices();

    expect(
      [for (final v in voices) (v.id, v.label, v.sampleUrl)],
      [
        ('v1', 'Eve', 'https://cdn.test/eve.mp3'),
        ('v3', 'Rex', 'https://cdn.test/rex.mp3'),
      ],
    );
    // Public, like the catalogue: browsing voices needs no sign-in.
    expect(server.to('GET', '/voices').single.headers['Authorization'], isNull);
  });

  test('starts a job with the key and the trimmed items', () async {
    server.on(
      'POST',
      '/speech',
      (_) => envelope({
        'jobId': 'tts_1',
        'status': 'queued',
        'pollAfterMs': 900,
        'charged': {'credits': 4, 'balance': 90},
      }, 202),
    );

    final started = await service().start(
      voiceId: 'v1',
      items: const [
        SpeechItem(id: 't0', text: 'Welcome back.'),
        SpeechItem(id: 't1', text: 'héllo 👍🏽'),
      ],
      idempotencyKey: 'key-12345678',
    );

    final request = server.to('POST', '/speech').single;
    expect(request.headers['Idempotency-Key'], 'key-12345678');
    expect(request.headers['Authorization'], 'Bearer a1');
    expect(jsonDecode(request.body), {
      'voiceId': 'v1',
      'items': [
        {'id': 't0', 'text': 'Welcome back.'},
        {'id': 't1', 'text': 'héllo 👍🏽'},
      ],
    });
    expect(started.jobId, 'tts_1');
    expect(started.pollAfter, const Duration(milliseconds: 900));
    expect((started.charged!.credits, started.charged!.balance), (4, 90));
  });

  test('a resend the server still has carries no charge', () async {
    server.on(
      'POST',
      '/speech',
      (_) => envelope({'jobId': 'tts_1', 'status': 'processing'}, 202),
    );

    final started = await service().start(
      voiceId: 'v1',
      items: const [SpeechItem(id: 't0', text: 'Hi')],
      idempotencyKey: 'key-12345678',
    );

    expect(started.charged, isNull);
    expect(started.pollAfter, SpeechService.defaultPollAfter);
  });

  test('an answer without a job id is BAD_RESPONSE', () async {
    server.on('POST', '/speech', (_) => envelope({'status': 'queued'}, 202));

    await expectLater(
      service().start(
        voiceId: 'v1',
        items: const [SpeechItem(id: 't0', text: 'Hi')],
        idempotencyKey: 'key-12345678',
      ),
      throwsCode(SlimshotApiException.badResponse),
    );
  });

  test(
      'polls until completed, at the server\'s pace, and returns each '
      "voice's length", () async {
    pollAnswers([() => working(700), done]);

    final spoken = await service().result(job, isCancelled: () => false);

    expect(waits, const [Duration(milliseconds: 1500), Duration(milliseconds: 700)]);
    expect(
      [for (final s in spoken) (s.id, s.durationSeconds)],
      [('t0', 2.448), ('t1', 3.072)],
    );
  });

  test('a completed job whose voices have no length is BAD_RESPONSE', () async {
    pollAnswers([
      () => envelope({
            'jobId': 'tts_1',
            'status': 'completed',
            'items': [
              {'id': 't0'},
            ],
          }),
    ]);

    await expectLater(
      service().result(job, isCancelled: () => false),
      throwsCode(SlimshotApiException.badResponse),
    );
  });

  test("a failed job throws SpeechJobFailed with the server's code", () async {
    pollAnswers([
      () => envelope({
            'jobId': 'tts_1',
            'status': 'failed',
            'error': {'code': 'TTS_UNAVAILABLE', 'message': 'off'},
          }),
    ]);

    await expectLater(
      service().result(job, isCancelled: () => false),
      throwsA(
        isA<SpeechJobFailed>().having((e) => e.code, 'code', 'TTS_UNAVAILABLE'),
      ),
    );

    pollAnswers([
      () => envelope({'jobId': 'tts_1', 'status': 'failed'}),
    ]);
    await expectLater(
      service().result(job, isCancelled: () => false),
      throwsA(
        isA<SpeechJobFailed>().having((e) => e.code, 'code', 'PROVIDER_FAILED'),
      ),
    );
  });

  test('three dropped polls in a row end it; fewer are ridden out', () async {
    pollAnswers([dropped, dropped, done]);
    final spoken = await service().result(job, isCancelled: () => false);
    expect(spoken, hasLength(2));

    pollAnswers([dropped, dropped, working, dropped, dropped, done]);
    expect(
      await service().result(job, isCancelled: () => false),
      hasLength(2),
      reason: 'a poll that lands resets the count',
    );

    pollAnswers([dropped, dropped, dropped, done]);
    await expectLater(
      service().result(job, isCancelled: () => false),
      throwsCode(SlimshotApiException.network),
    );
  });

  test('gives up after 10 minutes', () async {
    var now = DateTime(2026, 11, 11, 9);
    final waiting = SpeechService(
      fakeApi(server, session: signedInSession()),
      delay: (wait) async => now = now.add(wait),
      clock: () => now,
    );
    pollAnswers([() => working(60000)]);

    await expectLater(
      waiting.result(
        const SpeechJobStart(jobId: 'tts_1', pollAfter: Duration(minutes: 1)),
        isCancelled: () => false,
      ),
      throwsCode(kSpeechPollTimeout),
    );
    expect(server.to('GET', '/speech/tts_1'), hasLength(10));
  });

  test('a cancelled poll throws SpeechCancelled', () async {
    pollAnswers([working]);

    await expectLater(
      service().result(job, isCancelled: () => true),
      throwsA(isA<SpeechCancelled>()),
    );
    expect(server.requests, isEmpty);
  });

  group('download', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('voices'));
    tearDown(() => dir.delete(recursive: true));

    test('downloads into the file whole, leaving no .part', () async {
      server.on(
        'GET',
        '/speech/tts_1/items/t0',
        (_) => http.Response.bytes([73, 68, 51, 9], 200),
      );
      final into = File('${dir.path}/audio/voice_text_1_5.mp3');

      await service().download('tts_1', 't0', into);

      expect(into.readAsBytesSync(), [73, 68, 51, 9]);
      expect(File('${into.path}.part').existsSync(), isFalse);
      expect(
        server.to('GET', '/speech/tts_1/items/t0').single.headers['Authorization'],
        'Bearer a1',
      );
    });

    test('a refused download leaves nothing behind', () async {
      server.on(
        'GET',
        '/speech/tts_1/items/t0',
        (_) => failure('NOT_FOUND', 404),
      );
      final into = File('${dir.path}/voice_text_1_5.mp3');

      await expectLater(
        service().download('tts_1', 't0', into),
        throwsCode('NOT_FOUND'),
      );
      expect(into.existsSync(), isFalse);
      expect(File('${into.path}.part').existsSync(), isFalse);
    });
  });
}
