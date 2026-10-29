import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_run.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';

import '../../../support/caption_pipelines.dart';

/// One caption run as a screen shows it — the editor's progress sheet and
/// the captions screen draw the same run, so what it says and when is pinned
/// here, apart from either.
void main() {
  late HeldWork held;

  setUp(() => held = HeldWork());

  /// Lets the pipeline's awaits run through.
  Future<void> drain() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  CaptionRun runOn(CaptionPipeline pipeline) => CaptionRun(
        pipeline: pipeline,
        request: const CaptionRequest(),
        heldWork: held,
      );

  const job = CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero);
  const short = CreditQuote(credits: 30, balance: 0, enough: false);

  test('reports each stage, then the words', () async {
    final rendered = Completer<CaptionAudioResult>();
    final heard = Completer<CaptionTranscript>();
    final run = runOn(fakeCaptionPipeline(
      render: (_) => rendered.future,
      transcript: () => heard.future,
    ));
    addTearDown(run.dispose);
    var told = 0;
    run.addListener(() => told++);

    run.start();
    await drain();
    expect(run.stage, CaptionStage.preparing);
    expect(run.progress, 0);

    rendered.complete(kSoundRendered);
    await drain();
    expect(run.stage, CaptionStage.listening);
    expect(run.progress, isNull);

    heard.complete(kHelloTranscript);
    await drain();
    expect(run.drafts!.single.text, 'Hello');
    expect(told, greaterThanOrEqualTo(3));
  });

  test('a failure gives its line; retry runs again under the same upload key',
      () async {
    final keys = <String>[];
    var made = 0;
    var fail = true;
    final run = runOn(fakeCaptionPipeline(
      render: (_) async => kSoundRendered,
      newKey: () => 'k${++made}',
      upload: (key) async {
        keys.add(key);
        if (fail) {
          fail = false;
          throw const SlimshotApiException(SlimshotApiException.network);
        }
        return job;
      },
    ));
    addTearDown(run.dispose);

    run.start();
    await drain();
    expect(run.failure, isA<SlimshotApiException>());
    expect(run.error, captionErrorMessage(run.failure!));
    expect(run.drafts, isNull);

    run.retry();
    expect(run.error, isNull);
    await drain();
    expect(run.drafts, isNotNull);
    // A lost upload is retried under the key it was sent with: a fresh key
    // would be a second job, and a second charge.
    expect(keys, ['k1', 'k1']);
  });

  test('a shortfall waits; earning enough carries the run on', () async {
    var uploads = 0;
    final run = runOn(fakeCaptionPipeline(
      render: (_) async => kSoundRendered,
      quote: short,
      upload: (_) async {
        uploads++;
        return job;
      },
    ));
    addTearDown(run.dispose);

    run.start();
    await drain();
    expect(run.shortfall!.credits, 30);
    expect(uploads, 0);

    run.earned(30);
    expect(run.shortfall, isNull);
    await drain();
    expect(uploads, 1);
    expect(run.drafts, isNotNull);
  });

  test('earning too little updates the shortfall and waits', () async {
    var uploads = 0;
    final run = runOn(fakeCaptionPipeline(
      render: (_) async => kSoundRendered,
      quote: short,
      upload: (_) async {
        uploads++;
        return job;
      },
    ));
    addTearDown(run.dispose);

    run.start();
    await drain();
    run.earned(10);
    expect(run.shortfall!.balance, 10);
    expect(run.shortfall!.credits, 30);
    await drain();
    expect(uploads, 0);
  });

  test('stopped on its shortfall, a run uploads nothing', () async {
    var uploads = 0;
    final run = runOn(fakeCaptionPipeline(
      render: (_) async => kSoundRendered,
      quote: short,
      upload: (_) async {
        uploads++;
        return job;
      },
    ));

    run.start();
    await drain();
    expect(run.shortfall, isNotNull);
    run.dispose();
    await drain();
    expect(uploads, 0);
  });

  test('a stopped run never delivers its late words', () async {
    final heard = Completer<CaptionTranscript>();
    var cancels = 0;
    final run = runOn(fakeCaptionPipeline(
      render: (_) async => kSoundRendered,
      transcript: () => heard.future,
      onCancel: () => cancels++,
    ));

    run.start();
    await drain();
    expect(run.stage, CaptionStage.listening);
    var told = 0;
    run.addListener(() => told++);

    run.dispose();
    heard.complete(kHelloTranscript);
    await drain();
    expect(run.drafts, isNull);
    expect(told, 0);
    expect(cancels, 1);
  });

  test('holds the app from start until it is stopped', () {
    final run = runOn(fakeCaptionPipeline(
      render: (_) => Completer<CaptionAudioResult>().future,
    ));
    expect(held.isHeld, isFalse);
    run.start();
    expect(held.isHeld, isTrue);
    run.dispose();
    expect(held.isHeld, isFalse);
  });

  test('start twice is one run', () async {
    var renders = 0;
    final run = runOn(fakeCaptionPipeline(
      render: (_) {
        renders++;
        return Completer<CaptionAudioResult>().future;
      },
    ));
    addTearDown(run.dispose);

    run.start();
    run.start();
    await drain();
    expect(renders, 1);
  });

  test("the stage lines are the sheet's", () {
    expect(captionStageLabel(CaptionStage.preparing), 'Preparing audio');
    // The upload is never named: it reads as the listening it leads into.
    expect(captionStageLabel(CaptionStage.uploading), 'Listening');
    expect(captionStageLabel(CaptionStage.listening), 'Listening');
    expect(captionStageLabel(CaptionStage.placing), 'Placing captions');
  });
}
