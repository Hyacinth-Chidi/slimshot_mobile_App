import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/video_editor/logic/speech/voice_clip.dart';
import 'package:slimshotai/features/video_editor/services/speech_errors.dart';
import 'package:slimshotai/features/video_editor/services/speech_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/speech_service.dart';

import '../../../support/speech_pipelines.dart';

void main() {
  late SpeechFakes fakes;
  setUp(() => fakes = SpeechFakes());

  const network = SlimshotApiException(SlimshotApiException.network);

  List<(String, String, double, double)> clipsOf(List<VoiceClip> clips) => [
        for (final c in clips)
          (c.textId, c.filePath, c.durationSeconds, c.startSeconds),
      ];

  test('prices silently and generates when the balance covers it', () async {
    final stages = <SpeechStage>[];
    var asked = false;

    final clips = await fakes.pipeline().run(
      'v1',
      kTwoTexts,
      onProgress: stages.add,
      onShortfall: (_) async => asked = true,
    );

    expect(fakes.quoted, [10]);
    expect(asked, isFalse);
    expect(fakes.started.single.voiceId, 'v1');
    expect(
      [for (final i in fakes.started.single.items) (i.id, i.text)],
      [('t0', 'Hello'), ('t1', 'World')],
    );
    expect(fakes.started.single.key, 'key-1');
    expect(stages, [SpeechStage.speaking, SpeechStage.downloading]);
    expect(clipsOf(clips), [
      ('a', '/voices/a.mp3', 2.0, 1.0),
      ('b', '/voices/b.mp3', 3.0, 4.0),
    ]);
  });

  test('downloads every item and returns its clip at the captured start',
      () async {
    // The server lists its voices in its own order; each goes to its text.
    fakes.spoken = const [
      SpokenItem(id: 't1', durationSeconds: 3.5),
      SpokenItem(id: 't0', durationSeconds: 1.25),
    ];

    final clips = await fakes.pipeline().run('v1', kTwoTexts, onProgress: (_) {});

    expect(fakes.downloads, [('tts_1', 't0', 'a'), ('tts_1', 't1', 'b')]);
    expect(clipsOf(clips), [
      ('a', '/voices/a.mp3', 1.25, 1.0),
      ('b', '/voices/b.mp3', 3.5, 4.0),
    ]);
  });

  test("a completed job missing a text's voice is refused, never half placed",
      () async {
    fakes.spoken = const [SpokenItem(id: 't0', durationSeconds: 1)];

    await expectLater(
      fakes.pipeline().run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(isA<SlimshotApiException>()
          .having((e) => e.code, 'code', SlimshotApiException.badResponse)),
    );
    expect(fakes.downloads, isEmpty);
  });

  test('a shortfall asks, and goes on only when told', () async {
    fakes.quote = kShort;
    CreditQuote? told;

    await expectLater(
      fakes.pipeline().run(
        'v1',
        kTwoTexts,
        onProgress: (_) {},
        onShortfall: (quote) async {
          told = quote;
          return false;
        },
      ),
      throwsA(isA<SpeechCancelled>()),
    );
    expect(told!.credits, 30);
    expect(fakes.started, isEmpty);

    // With nobody to tell, a short run never starts either.
    await expectLater(
      fakes.pipeline().run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(isA<SpeechCancelled>()),
    );
    expect(fakes.started, isEmpty);

    final clips = await fakes.pipeline().run(
      'v1',
      kTwoTexts,
      onProgress: (_) {},
      onShortfall: (_) async => true,
    );
    expect(clips, hasLength(2));
  });

  test('a retry after a lost answer reuses the key and skips the price',
      () async {
    final pipeline = fakes.pipeline();
    fakes.startFailure = network;
    await expectLater(
      pipeline.run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(network),
    );

    fakes.startFailure = null;
    final clips = await pipeline.run('v1', kTwoTexts, onProgress: (_) {});

    expect([for (final s in fakes.started) s.key], ['key-1', 'key-1']);
    expect(fakes.quoted, [10], reason: 'the held key may already have paid');
    expect(clips, hasLength(2));
  });

  test('a different request never reuses a held key', () async {
    final pipeline = fakes.pipeline();
    fakes.startFailure = network;
    await expectLater(
      pipeline.run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(network),
    );

    fakes.startFailure = null;
    await pipeline.run('v2', kTwoTexts, onProgress: (_) {});

    // The server answers a held key with the job it already has: another
    // voice under it would come back in the first one.
    expect([for (final s in fakes.started) s.key], ['key-1', 'key-2']);
    expect(fakes.quoted, [10, 10]);
  });

  test(
      'a failed job takes a fresh key next time, and says the credits were '
      'returned when it was paid', () async {
    final pipeline = fakes.pipeline();
    fakes.charge = const CreditCharge(credits: 4, balance: 90);
    fakes.jobFailure = const SpeechJobFailed('PROVIDER_FAILED');

    await expectLater(
      pipeline.run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(isA<SpeechFailure>()
          .having((e) => e.code, 'code', SpeechFailure.refunded)),
    );
    expect(fakes.charged, [90]);
    expect(
      speechErrorMessage(const SpeechFailure(SpeechFailure.refunded)),
      'Making the voice failed. Your credits were returned.',
    );

    fakes.jobFailure = null;
    await pipeline.run('v1', kTwoTexts, onProgress: (_) {});
    expect([for (final s in fakes.started) s.key], ['key-1', 'key-2']);
    expect(fakes.quoted, [10, 10]);
  });

  test('a free job that fails says nothing about credits', () async {
    fakes.quote = kFree;
    fakes.jobFailure = const SpeechJobFailed('PROVIDER_FAILED');

    await expectLater(
      fakes.pipeline().run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(isA<SpeechJobFailed>()),
    );
  });

  test('a priced job that fails after a lost answer says the credits came back',
      () async {
    // The answer that carried the charge was lost; the price said it was paid.
    final pipeline = fakes.pipeline();
    fakes.quote = kPriced;
    fakes.startFailure = network;
    await expectLater(
      pipeline.run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(network),
    );

    fakes.startFailure = null;
    fakes.jobFailure = const SpeechJobFailed('PROVIDER_FAILED');
    await expectLater(
      pipeline.run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(isA<SpeechFailure>()
          .having((e) => e.code, 'code', SpeechFailure.refunded)),
    );
  });

  test('IDEMPOTENCY_KEY_REUSED takes one fresh key', () async {
    const reused = SlimshotApiException('IDEMPOTENCY_KEY_REUSED');
    fakes.startFailures = [reused];

    final clips = await fakes.pipeline().run('v1', kTwoTexts, onProgress: (_) {});
    expect([for (final s in fakes.started) s.key], ['key-1', 'key-2']);
    expect(clips, hasLength(2));

    // A second refusal is the server's to explain, not retried again.
    final other = SpeechFakes()..startFailures = [reused, reused];
    await expectLater(
      other.pipeline().run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(reused),
    );
    expect(other.started, hasLength(2));
  });

  test('a failed download keeps the key; the retry downloads the same job',
      () async {
    final pipeline = fakes.pipeline();
    fakes.downloadFailures = {'t1': network};

    await expectLater(
      pipeline.run('v1', kTwoTexts, onProgress: (_) {}),
      throwsA(network),
    );
    // The voice that did arrive is not left behind for nobody.
    expect(fakes.deleted, ['/voices/a.mp3']);

    fakes.downloadFailures = {};
    final clips = await pipeline.run('v1', kTwoTexts, onProgress: (_) {});

    expect([for (final s in fakes.started) s.key], ['key-1', 'key-1']);
    expect(fakes.quoted, [10]);
    expect(
      fakes.downloads,
      [('tts_1', 't0', 'a'), ('tts_1', 't1', 'b'), ('tts_1', 't0', 'a'), ('tts_1', 't1', 'b')],
    );
    expect(clips, hasLength(2));
  });

  test('cancel stops at the next step and nothing is placed', () async {
    final heard = Completer<List<SpokenItem>>();
    fakes.awaitWith = (_) => heard.future;
    final pipeline = fakes.pipeline();

    final running = pipeline.run('v1', kTwoTexts, onProgress: (_) {});
    await pumpEventQueue();
    pipeline.cancel();
    pipeline.cancel();
    heard.complete(fakes.spoken);

    await expectLater(running, throwsA(isA<SpeechCancelled>()));
    expect(fakes.cancels, 1);
    expect(fakes.downloads, isEmpty);
  });

  test('a cancel mid-download deletes what arrived', () async {
    final second = Completer<String>();
    fakes.downloadWith = (itemId) =>
        itemId == 't1' ? second.future : Future.value('/voices/a.mp3');
    final pipeline = fakes.pipeline();

    final running = pipeline.run('v1', kTwoTexts, onProgress: (_) {});
    await pumpEventQueue();
    pipeline.cancel();
    second.complete('/voices/b.mp3');

    await expectLater(running, throwsA(isA<SpeechCancelled>()));
    expect(fakes.deleted.toSet(), {'/voices/a.mp3', '/voices/b.mp3'});
  });
}
