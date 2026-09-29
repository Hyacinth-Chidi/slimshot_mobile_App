import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

class MemoryTokens implements DeviceTokenStore {
  String? token = 'tok';

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

void main() {
  late File audio;
  const job = CaptionJobStart(
    jobId: 'cap_1',
    pollAfter: Duration(milliseconds: 1500),
  );

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('captions');
    audio = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3, 4]);
  });

  CaptionService serviceWith(
    MockClient client, {
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  }) =>
      CaptionService(
        SlimshotApi(
          baseUrl: 'https://api.test',
          client: client,
          tokens: MemoryTokens(),
        ),
        delay: delay ?? (_) async {},
        clock: clock,
      );

  group('upload', () {
    test('sends the audio, the language and the key as the server expects',
        () async {
      late http.Request upload;
      final service = serviceWith(MockClient((request) async {
        upload = request;
        return envelope(
          {'jobId': 'cap_1', 'status': 'queued', 'pollAfterMs': 900},
          202,
        );
      }));
      final started = await service.start(
        audioPath: audio.path,
        language: 'fr',
        idempotencyKey: 'key-12345678',
      );

      expect(started.jobId, 'cap_1');
      expect(started.pollAfter, const Duration(milliseconds: 900));
      expect(upload.method, 'POST');
      expect(upload.url.path, '/api/app/v1/captions');
      expect(upload.headers['Idempotency-Key'], 'key-12345678');
      expect(upload.headers['Authorization'], 'Bearer tok');
      expect(upload.headers['Content-Type'], startsWith('multipart/form-data'));
      final body = latin1.decode(upload.bodyBytes);
      expect(body, contains('name="audio"; filename="captions.m4a"'));
      expect(body, contains('content-type: audio/mp4'));
      expect(body, contains('name="language"'));
    });

    test('a pace that is not a number falls back to the default', () async {
      final service = serviceWith(MockClient((_) async => http.Response(
            '{"success":true,"data":'
            '{"jobId":"cap_1","status":"queued","pollAfterMs":1e400}}',
            202,
          )));
      final started = await service.start(
        audioPath: audio.path,
        idempotencyKey: 'key-12345678',
      );
      expect(started.pollAfter, CaptionService.defaultPollAfter);
    });

    test('Auto detect sends no language', () async {
      late http.Request upload;
      final service = serviceWith(MockClient((request) async {
        upload = request;
        return envelope({'jobId': 'cap_1', 'status': 'queued'}, 202);
      }));
      final started = await service.start(
        audioPath: audio.path,
        idempotencyKey: 'key-12345678',
      );
      expect(
        latin1.decode(upload.bodyBytes),
        isNot(contains('name="language"')),
      );
      expect(started.pollAfter, CaptionService.defaultPollAfter);
    });
  });

  group('polling', () {
    test("polls at the server's pace until the words arrive", () async {
      final statuses = ['queued', 'processing', 'completed'];
      final waits = <Duration>[];
      final service = serviceWith(
        MockClient((_) async {
          final status = statuses.removeAt(0);
          if (status != 'completed') {
            return envelope(
              {'jobId': 'cap_1', 'status': status, 'pollAfterMs': 700},
            );
          }
          return envelope({
            'jobId': 'cap_1',
            'status': 'completed',
            'result': {
              'provider': 'elevenlabs',
              'language': 'en',
              'durationSeconds': 1.2,
              'text': 'Hi there.',
              'words': [
                {'text': 'Hi', 'start': 0.1, 'end': 0.3, 'confidence': 1},
                {'text': 'there.', 'start': 0.4, 'end': 0.8, 'confidence': 0.9},
              ],
            },
          });
        }),
        delay: (d) async => waits.add(d),
      );
      final transcript = await service.result(job, isCancelled: () => false);
      expect(transcript.words.map((w) => w.text), ['Hi', 'there.']);
      expect(waits, const [
        Duration(milliseconds: 1500),
        Duration(milliseconds: 700),
        Duration(milliseconds: 700),
      ]);
    });

    test('a failed job carries its code', () async {
      final service = serviceWith(MockClient((_) async => envelope({
            'jobId': 'cap_1',
            'status': 'failed',
            'error': {'code': 'PROVIDER_FAILED', 'message': 'no'},
          })));
      await expectLater(
        service.result(job, isCancelled: () => false),
        throwsA(
          isA<SlimshotApiException>()
              .having((e) => e.code, 'code', 'PROVIDER_FAILED'),
        ),
      );
    });

    test('gives up after ten minutes', () async {
      var now = DateTime(2026);
      final service = serviceWith(
        MockClient((_) async => envelope(
              {'jobId': 'cap_1', 'status': 'processing', 'pollAfterMs': 1500},
            )),
        delay: (_) async {
          now = now.add(const Duration(minutes: 3));
        },
        clock: () => now,
      );
      await expectLater(
        service.result(job, isCancelled: () => false),
        throwsA(
          isA<SlimshotApiException>()
              .having((e) => e.code, 'code', kCaptionPollTimeout),
        ),
      );
    });

    test('a dropped poll is ridden out: the job is still running', () async {
      // One lost request on a mobile connection must not throw away a job
      // the server is still working on — the retry would upload it again.
      var polls = 0;
      final service = serviceWith(MockClient((_) async {
        if (++polls < 3) throw http.ClientException('dropped');
        return envelope({
          'jobId': 'cap_1',
          'status': 'completed',
          'result': {
            'text': 'Hi',
            'words': [
              {'text': 'Hi', 'start': 0.1, 'end': 0.3},
            ],
          },
        });
      }));
      final transcript = await service.result(job, isCancelled: () => false);
      expect(transcript.words.single.text, 'Hi');
      expect(polls, 3);
    });

    test('polls that keep failing end as No connection', () async {
      var polls = 0;
      final service = serviceWith(MockClient((_) async {
        polls++;
        throw http.ClientException('offline');
      }));
      await expectLater(
        service.result(job, isCancelled: () => false),
        throwsA(
          isA<SlimshotApiException>()
              .having((e) => e.code, 'code', SlimshotApiException.network),
        ),
      );
      expect(polls, CaptionService.maxPollFailures);
    });

    test('a poll that answers resets the count of failures', () async {
      var polls = 0;
      final service = serviceWith(MockClient((_) async {
        polls++;
        // fail, fail, answer, fail, fail, answer: never three in a row.
        if (polls % 3 != 0) throw http.ClientException('dropped');
        return envelope(
          polls < 6
              ? {'jobId': 'cap_1', 'status': 'processing', 'pollAfterMs': 10}
              : {
                  'jobId': 'cap_1',
                  'status': 'completed',
                  'result': {'text': '', 'words': <Object>[]},
                },
        );
      }));
      await service.result(job, isCancelled: () => false);
      expect(polls, 6);
    });

    test('a cancel stops polling before the next request', () async {
      var polls = 0;
      var cancelled = false;
      final service = serviceWith(MockClient((_) async {
        polls++;
        cancelled = true;
        return envelope(
          {'jobId': 'cap_1', 'status': 'processing', 'pollAfterMs': 10},
        );
      }));
      await expectLater(
        service.result(job, isCancelled: () => cancelled),
        throwsA(isA<CaptionCancelled>()),
      );
      expect(polls, 1);
    });
  });

  group('captionErrorMessage', () {
    test('every cause has its one line', () {
      const expected = {
        SlimshotApiException.network:
            'No connection. Check your internet and try again.',
        'CAPTIONS_UNAVAILABLE': 'Auto captions are unavailable right now.',
        'UNAUTHENTICATED': 'Auto captions are unavailable right now.',
        'PROVIDER_FAILED': "Couldn't transcribe this audio. Try again.",
        'VALIDATION_FAILED': "Couldn't transcribe this audio. Try again.",
        'PAYLOAD_TOO_LARGE': 'This video is too long for auto captions.',
        'NOT_FOUND': 'Captions expired before they arrived. Try again.',
        kCaptionPollTimeout: 'Captions took too long. Try again.',
      };
      expected.forEach((code, line) {
        expect(
          captionErrorMessage(SlimshotApiException(code)),
          line,
          reason: code,
        );
      });
      expect(
        captionErrorMessage(const CaptionFailure(CaptionFailure.noSpeech)),
        'No speech found.',
      );
      expect(
        captionErrorMessage(const CaptionFailure(CaptionFailure.noSound)),
        'No sound to caption.',
      );
      expect(
        captionErrorMessage(PlatformException(code: 'caption_audio_failed')),
        "Couldn't read this project's sound. Try again.",
      );
      expect(
        captionErrorMessage(StateError('?')),
        "Couldn't transcribe this audio. Try again.",
      );
    });
  });
}
