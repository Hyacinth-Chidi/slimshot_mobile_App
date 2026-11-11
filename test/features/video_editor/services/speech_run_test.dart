import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/video_editor/services/speech_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/speech_run.dart';
import 'package:slimshotai/features/video_editor/services/speech_service.dart';

import '../../../support/speech_pipelines.dart';

/// One voice run as the sheet shows it: where it is, a failure's line, a
/// shortfall waiting on the user, and the voices once they land.
void main() {
  late HeldWork held;
  late SpeechFakes fakes;
  setUp(() {
    held = HeldWork();
    fakes = SpeechFakes();
  });

  Future<void> drain() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  SpeechRun runOn(SpeechPipeline pipeline) => SpeechRun(
        pipeline: pipeline,
        voiceId: 'v1',
        plan: kTwoTexts,
        heldWork: held,
      );

  test('holds the app while running', () async {
    final heard = Completer<List<SpokenItem>>();
    fakes.awaitWith = (_) => heard.future;
    final run = runOn(fakes.pipeline());

    expect(held.isHeld, isFalse);
    run.start();
    await drain();
    expect(held.isHeld, isTrue);
    expect(run.stage, SpeechStage.speaking);
    expect(speechStageLabel(run.stage, count: 2), 'Making the voices');

    heard.complete(fakes.spoken);
    await drain();
    expect(run.voices, hasLength(2));

    run.dispose();
    expect(held.isHeld, isFalse);
  });

  test('earned credits that cover the price carry it on', () async {
    fakes.quote = kShort;
    final run = runOn(fakes.pipeline());
    addTearDown(run.dispose);

    run.start();
    await drain();
    expect(run.shortfall!.credits, 30);
    expect(fakes.started, isEmpty);

    run.earned(10);
    await drain();
    expect(run.shortfall!.balance, 10, reason: 'too little: the line updates');
    expect(fakes.started, isEmpty);

    run.earned(30);
    await drain();
    expect(run.shortfall, isNull);
    expect(fakes.started, hasLength(1));
    expect(run.voices, hasLength(2));
  });

  test('closing on a shortfall stops the run: nothing is started', () async {
    fakes.quote = kShort;
    final run = runOn(fakes.pipeline())..start();
    await drain();

    run.dispose();
    await drain();
    expect(fakes.started, isEmpty);
  });

  test('retry runs the same pipeline', () async {
    fakes.startFailure =
        const SlimshotApiException(SlimshotApiException.network);
    final run = runOn(fakes.pipeline());
    addTearDown(run.dispose);

    run.start();
    await drain();
    expect(run.error, 'No internet connection.');
    expect(run.voices, isNull);

    fakes.startFailure = null;
    run.retry();
    await drain();
    expect(run.error, isNull);
    expect([for (final s in fakes.started) s.key], ['key-1', 'key-1']);
    expect(run.voices, hasLength(2));
  });

  test('a cancel is no failure', () async {
    final heard = Completer<List<SpokenItem>>();
    fakes.awaitWith = (_) => heard.future;
    final run = runOn(fakes.pipeline())..start();
    await drain();

    run.dispose();
    heard.complete(fakes.spoken);
    await drain();
    expect(fakes.cancels, 1);
    expect(run.voices, isNull);
  });
}
