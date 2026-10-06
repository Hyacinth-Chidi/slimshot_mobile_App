import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/utils/file_utils.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

void main() {
  const hello = CaptionTranscript(
    text: 'Hello world',
    words: [
      TranscriptWord(text: 'Hello', start: 0.2, end: 0.5),
      TranscriptWord(text: 'world', start: 0.6, end: 0.9),
    ],
  );
  const sound = CaptionAudioResult(
    outputPath: '/tmp/captions.m4a',
    durationSeconds: 3,
    hasSound: true,
  );
  const job = CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero);

  late List<String> deleted;
  late List<String> keys;
  late int cancels;
  late List<double> quoted;
  late List<int> charges;

  setUp(() {
    deleted = [];
    keys = [];
    cancels = 0;
    quoted = [];
    charges = [];
  });

  CaptionPipeline pipeline({
    Future<CaptionAudioResult> Function(CaptionSource source)? render,
    Future<CaptionJobStart> Function(String? language)? start,
    Future<CaptionTranscript> Function(bool Function() isCancelled)? transcript,
    CreditQuote quote = const CreditQuote(credits: 0, balance: 94, enough: true),
    Future<CreditQuote> Function()? quoteWith,
    Future<CaptionJobStart> Function(String key)? startWithKey,
  }) {
    var n = 0;
    return CaptionPipeline(
      audioPath: () async => '/tmp/captions.m4a',
      deleteFile: (path) async => deleted.add(path),
      newKey: () => 'key-${++n}',
      renderAudio: (path, source, onProgress) async {
        onProgress(0.5);
        return render == null ? sound : render(source);
      },
      quotePrice: (seconds) async {
        quoted.add(seconds);
        return quoteWith == null ? quote : quoteWith();
      },
      startJob: (path, language, key) async {
        keys.add(key);
        if (startWithKey != null) return startWithKey(key);
        return start == null ? job : start(language);
      },
      awaitJob: (job, isCancelled) =>
          transcript == null ? Future.value(hello) : transcript(isCancelled),
      onCharged: charges.add,
      onCancel: () => cancels++,
    );
  }

  test('render → upload → listen → place, and the audio file is cleaned up',
      () async {
    final stages = <CaptionStage>[];
    final progress = <double?>[];
    final drafts = await pipeline().run(
      const CaptionRequest(),
      onProgress: (stage, value) {
        if (stages.isEmpty || stages.last != stage) stages.add(stage);
        progress.add(value);
      },
    );
    expect(stages, CaptionStage.values);
    expect(progress, contains(0.5));
    expect(drafts.single.text, 'Hello world');
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('the audio file is one the startup sweep will find', () {
    // A run killed part-way never reaches its own cleanup; the sweep only
    // takes files that carry its prefix.
    final name = captionAudioFileName(DateTime.fromMillisecondsSinceEpoch(42));
    expect(name, startsWith(FileUtils.filePrefix));
    expect(name, endsWith('_42.wav'));
  });

  test('no caption outlasts the sound it was heard in', () async {
    final drafts = await pipeline(
      render: (_) async => const CaptionAudioResult(
        outputPath: '/tmp/captions.m4a',
        durationSeconds: 1.0,
        hasSound: true,
      ),
    ).run(const CaptionRequest(), onProgress: (_, __) {});
    expect(drafts.single.end, const Duration(milliseconds: 1000));
  });

  test('the chosen sound and language reach the steps that use them',
      () async {
    CaptionSource? rendered;
    String? sent = 'unset';
    await pipeline(
      render: (source) async {
        rendered = source;
        return sound;
      },
      start: (language) async {
        sent = language;
        return job;
      },
    ).run(
      const CaptionRequest(source: CaptionSource.tracks, language: 'yo'),
      onProgress: (_, __) {},
    );
    expect(rendered, CaptionSource.tracks);
    expect(sent, 'yo');
  });

  test('nothing to hear stops before any upload', () async {
    await expectLater(
      pipeline(
        render: (_) async => const CaptionAudioResult(
          outputPath: '',
          durationSeconds: 0,
          hasSound: false,
        ),
      ).run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(
        isA<CaptionFailure>()
            .having((e) => e.code, 'code', CaptionFailure.noSound),
      ),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('no words is No speech found', () async {
    await expectLater(
      pipeline(
        transcript: (_) async => const CaptionTranscript(text: '', words: []),
      ).run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(
        isA<CaptionFailure>()
            .having((e) => e.code, 'code', CaptionFailure.noSpeech),
      ),
    );
  });

  test('a cancel while listening ends in CaptionCancelled and places nothing',
      () async {
    late CaptionPipeline p;
    p = pipeline(transcript: (isCancelled) async {
      p.cancel();
      expect(isCancelled(), isTrue);
      return hello;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(cancels, 1);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('a render stopped natively is a cancel', () async {
    await expectLater(
      pipeline(render: (_) async => throw const CaptionAudioCancelled())
          .run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<CaptionCancelled>()),
    );
  });

  test('Try again after an upload that never landed reuses its key', () async {
    var attempts = 0;
    final p = pipeline(start: (_) async {
      if (attempts++ == 0) {
        throw const SlimshotApiException(SlimshotApiException.network);
      }
      return job;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<SlimshotApiException>()),
    );
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-1']);
  });

  test('Try again after the server had the job takes a new key', () async {
    var attempts = 0;
    final p = pipeline(transcript: (_) async {
      if (attempts++ == 0) {
        throw const SlimshotApiException('PROVIDER_FAILED');
      }
      return hello;
    });
    await expectLater(
      p.run(const CaptionRequest(), onProgress: (_, __) {}),
      throwsA(isA<SlimshotApiException>()),
    );
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-2']);
  });

  test('a finished run retires its key', () async {
    final p = pipeline();
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    await p.run(const CaptionRequest(), onProgress: (_, __) {});
    expect(keys, ['key-1', 'key-2']);
  });

  const paid = CreditQuote(credits: 6, balance: 94, enough: true);
  void ignore(CaptionStage stage, double? value) {}

  test('a paid run is priced on the audio it rendered, then asked', () async {
    CreditQuote? asked;
    await pipeline(quote: paid).run(
      const CaptionRequest(),
      onProgress: ignore,
      confirmPrice: (q) async {
        asked = q;
        return true;
      },
    );
    expect(quoted, [3.0], reason: "the rendered sound's own length");
    expect(asked, same(paid));
    expect(keys, ['key-1']);
  });

  test('declining uploads nothing and cleans up', () async {
    await expectLater(
      pipeline(quote: paid).run(
        const CaptionRequest(),
        onProgress: ignore,
        confirmPrice: (_) async => false,
      ),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test('with nobody to ask, a paid run never uploads', () async {
    await expectLater(
      pipeline(quote: paid).run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<CaptionCancelled>()),
    );
    expect(keys, isEmpty);
  });

  test('a free run is not asked about', () async {
    var asked = false;
    await pipeline().run(
      const CaptionRequest(),
      onProgress: ignore,
      confirmPrice: (_) async => asked = true,
    );
    expect(asked, isFalse);
    expect(keys, ['key-1']);
  });

  test('a quote that fails uploads nothing', () async {
    await expectLater(
      pipeline(
        quoteWith: () async =>
            throw const SlimshotApiException('CAPTIONS_UNAVAILABLE'),
      ).run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<SlimshotApiException>()),
    );
    expect(keys, isEmpty);
    expect(deleted, ['/tmp/captions.m4a']);
  });

  test("the upload's charged balance is reported", () async {
    await pipeline(
      quote: paid,
      start: (_) async => const CaptionJobStart(
        jobId: 'cap_1',
        pollAfter: Duration.zero,
        charged: CreditCharge(credits: 6, balance: 88),
      ),
    ).run(
      const CaptionRequest(),
      onProgress: ignore,
      confirmPrice: (_) async => true,
    );
    expect(charges, [88]);
  });

  test('a failed paid job says the credits came back; a free one does not',
      () async {
    Future<CaptionTranscript> fails(bool Function() _) async =>
        throw const CaptionJobFailed('PROVIDER_FAILED');

    await expectLater(
      pipeline(
        quote: paid,
        start: (_) async => const CaptionJobStart(
          jobId: 'cap_1',
          pollAfter: Duration.zero,
          charged: CreditCharge(credits: 6, balance: 88),
        ),
        transcript: fails,
      ).run(
        const CaptionRequest(),
        onProgress: ignore,
        confirmPrice: (_) async => true,
      ),
      throwsA(isA<CaptionFailure>()
          .having((e) => e.code, 'code', CaptionFailure.refunded)),
    );
    await expectLater(
      pipeline(transcript: fails)
          .run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<CaptionJobFailed>()),
    );
  });

  test('a key the server will not take again is replaced once', () async {
    var tries = 0;
    await pipeline(
      startWithKey: (key) async {
        if (tries++ == 0) {
          throw const SlimshotApiException('IDEMPOTENCY_KEY_REUSED');
        }
        return job;
      },
    ).run(const CaptionRequest(), onProgress: ignore);
    expect(keys, ['key-1', 'key-2']);
  });

  test('a second refusal of the key is not retried again', () async {
    await expectLater(
      pipeline(
        startWithKey: (_) async =>
            throw const SlimshotApiException('IDEMPOTENCY_KEY_REUSED'),
      ).run(const CaptionRequest(), onProgress: ignore),
      throwsA(isA<SlimshotApiException>()),
    );
    expect(keys, ['key-1', 'key-2']);
  });

  test("declining forgets a lost upload's key", () async {
    var lose = true;
    final p = pipeline(
      quote: paid,
      start: (_) async {
        if (lose) throw const SlimshotApiException(SlimshotApiException.network);
        return job;
      },
    );
    await expectLater(
      p.run(const CaptionRequest(),
          onProgress: ignore, confirmPrice: (_) async => true),
      throwsA(isA<SlimshotApiException>()),
    ); // key-1 kept: the upload may have landed
    await expectLater(
      p.run(const CaptionRequest(),
          onProgress: ignore, confirmPrice: (_) async => false),
      throwsA(isA<CaptionCancelled>()),
    );
    lose = false;
    await p.run(const CaptionRequest(),
        onProgress: ignore, confirmPrice: (_) async => true);
    expect(keys, ['key-1', 'key-2'], reason: 'a new upload, a new key');
  });

  test('a refusal for credits says how many', () {
    expect(
      captionErrorMessage(const SlimshotApiException(
        'INSUFFICIENT_CREDITS',
        'm',
        {'required': 6, 'balance': 2},
      )),
      'Needs 6 credits · You have 2',
    );
    expect(
      captionErrorMessage(const SlimshotApiException('INSUFFICIENT_CREDITS')),
      'Not enough credits for these captions.',
    );
    expect(
      captionErrorMessage(const CaptionFailure(CaptionFailure.refunded)),
      'Captioning failed. Your credits were returned.',
    );
  });
}
