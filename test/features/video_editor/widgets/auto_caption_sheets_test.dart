import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/services/caption_access.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/auto_caption_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/caption_progress_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/replace_captions_dialog.dart';

void main() {
  /// Opens [builder] as an editor sheet and records what it pops.
  Future<List<Object?>> open(WidgetTester tester, WidgetBuilder builder) async {
    final popped = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => popped.add(
                await showEditorSheet<Object?>(context, builder: builder),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return popped;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('AutoCaptionSheet', () {
    testWidgets('offers the choices and starts on the defaults',
        (tester) async {
      final popped = await open(tester, (_) => const AutoCaptionSheet());
      for (final label in [
        'Video sound',
        'Audio tracks',
        'All',
        'Auto detect',
        'Word',
        'Phrase',
        'Line',
        'Generate',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(request.source, CaptionSource.video);
      expect(request.language, isNull);
      expect(request.length, CaptionLength.phrase);
    });

    testWidgets('returns what was chosen', (tester) async {
      final popped = await open(tester, (_) => const AutoCaptionSheet());
      await tapKey(tester, 'caption_source_all');
      await tapKey(tester, 'caption_language_fr');
      await tapKey(tester, 'caption_length_line');
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(
        (request.source, request.language, request.length),
        (CaptionSource.all, 'fr', CaptionLength.line),
      );
    });

    testWidgets("reopens on the project's last choices", (tester) async {
      final popped = await open(
        tester,
        (_) => const AutoCaptionSheet(
          initial: CaptionSettings(
            setId: 's',
            source: CaptionSource.tracks,
            language: 'yo',
            length: CaptionLength.word,
          ),
        ),
      );
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(
        (request.source, request.language, request.length),
        (CaptionSource.tracks, 'yo', CaptionLength.word),
      );
    });
  });

  group('CaptionProgressSheet', () {
    const hello = CaptionTranscript(
      text: 'Hello',
      words: [TranscriptWord(text: 'Hello', start: 0.2, end: 0.5)],
    );

    CaptionPipeline pipelineWith({
      required Future<CaptionAudioResult> Function() render,
      Future<CaptionTranscript> Function()? transcript,
      void Function()? onCancel,
    }) =>
        CaptionPipeline(
          audioPath: () async => '/tmp/none.m4a',
          deleteFile: (_) async {},
          renderAudio: (path, source, onProgress) => render(),
          startJob: (path, language, key) async =>
              const CaptionJobStart(jobId: 'cap_1', pollAfter: Duration.zero),
          awaitJob: (job, isCancelled) =>
              transcript == null ? Future.value(hello) : transcript(),
          onCancel: onCancel ?? () {},
        );

    const sound = CaptionAudioResult(
      outputPath: '/tmp/none.m4a',
      durationSeconds: 1,
      hasSound: true,
    );

    testWidgets('names each stage, then closes with the captions',
        (tester) async {
      final rendered = Completer<CaptionAudioResult>();
      final heard = Completer<CaptionTranscript>();
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () => rendered.future,
            transcript: () => heard.future,
          ),
          request: const CaptionRequest(),
        ),
      );
      expect(find.text('Preparing audio'), findsOneWidget);

      rendered.complete(sound);
      await tester.pump();
      await tester.pump();
      expect(find.text('Listening'), findsOneWidget);

      heard.complete(hello);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
    });

    testWidgets('a failure shows its line; Try again runs again',
        (tester) async {
      var runs = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(render: () async {
            runs++;
            return const CaptionAudioResult(
              outputPath: '',
              durationSeconds: 0,
              hasSound: false,
            );
          }),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      expect(find.text('No sound to caption.'), findsOneWidget);
      await tapKey(tester, 'caption_retry');
      expect(runs, 2);
      await tapKey(tester, 'caption_close');
      expect(popped.single, isNull);
    });

    testWidgets('Cancel closes the sheet and stops the run', (tester) async {
      var cancels = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () => Completer<CaptionAudioResult>().future,
            onCancel: () => cancels++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tapKey(tester, 'caption_cancel');
      expect(popped.single, isNull);
      expect(cancels, 1);
    });
  });

  group('replacing captions', () {
    Future<List<bool>> ask(WidgetTester tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async =>
                    answers.add(await confirmReplaceCaptions(context)),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.text('Replace captions?'), findsOneWidget);
      return answers;
    }

    testWidgets('Replace says yes', (tester) async {
      final answers = await ask(tester);
      await tester.tap(find.byKey(const Key('replace_captions_confirm')));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('Cancel, or a tap outside, says no', (tester) async {
      final answers = await ask(tester);
      await tester.tap(find.byKey(const Key('replace_captions_cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(answers, [false, false]);
    });
  });

  testWidgets('every run is allowed until sign-in exists', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(builder: (c) {
        context = c;
        return const SizedBox();
      }),
    );
    expect(await CaptionAccess.ensureAllowed(context), isTrue);
  });
}
