import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
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

    testWidgets('asks only what generating needs: no highlight, no style',
        (tester) async {
      // The look is chosen afterwards, on the captions themselves (a
      // caption's menu, Caption style), where it can be judged against the
      // footage. A new set comes out in the default style.
      await open(tester, (_) => const AutoCaptionSheet());
      expect(find.text('Highlight'), findsNothing);
      expect(find.text('Style'), findsNothing);
      expect(find.byKey(const Key('caption_highlight_none')), findsNothing);
      expect(find.byKey(const Key('caption_preset_bubble')), findsNothing);
      for (final section in ['Source', 'Language', 'Length']) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
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

  testWidgets('an unlisted language opens the sheet on Auto detect',
      (tester) async {
    final popped = await open(
      tester,
      (_) => const AutoCaptionSheet(
        initial: CaptionSettings(setId: 's', language: 'xx'),
      ),
    );
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'caption_generate');
    expect((popped.single as CaptionRequest).language, isNull);
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
      CreditQuote quote =
          const CreditQuote(credits: 0, balance: 94, enough: true),
      void Function()? onUpload,
    }) =>
        CaptionPipeline(
          audioPath: () async => '/tmp/none.m4a',
          deleteFile: (_) async {},
          renderAudio: (path, source, onProgress) => render(),
          quotePrice: (_) async => quote,
          startJob: (path, language, key) async {
            onUpload?.call();
            return const CaptionJobStart(
              jobId: 'cap_1',
              pollAfter: Duration.zero,
            );
          },
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

    testWidgets('a paid run shows its price and waits for Generate',
        (tester) async {
      var uploads = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 94, enough: true),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      expect(find.text('6 credits · You have 94'), findsOneWidget);
      expect(uploads, 0, reason: 'nothing leaves before Generate');

      await tapKey(tester, 'caption_confirm');
      expect(uploads, 1);
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
    });

    testWidgets('closing at the price step uploads nothing', (tester) async {
      var uploads = 0;
      var cancels = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 94, enough: true),
            onUpload: () => uploads++,
            onCancel: () => cancels++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      await tapKey(tester, 'caption_cancel');
      expect(popped.single, isNull);
      expect((uploads, cancels), (0, 1));

      // And by a tap outside the sheet.
      final again = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 94, enough: true),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(again.single, isNull);
      expect(uploads, 0);
    });

    testWidgets('short of credits: how many it needs, and only Close',
        (tester) async {
      var uploads = 0;
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(
            render: () async => sound,
            quote: const CreditQuote(credits: 6, balance: 2, enough: false),
            onUpload: () => uploads++,
          ),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      expect(find.text('Needs 6 credits · You have 2'), findsOneWidget);
      expect(find.byKey(const Key('caption_confirm')), findsNothing);
      await tapKey(tester, 'caption_close');
      expect(popped.single, isNull);
      expect(uploads, 0);
    });

    testWidgets('a free run goes straight through', (tester) async {
      final popped = await open(
        tester,
        (_) => CaptionProgressSheet(
          pipeline: pipelineWith(render: () async => sound),
          request: const CaptionRequest(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('caption_price')), findsNothing);
      expect((popped.single as List<CaptionDraft>).single.text, 'Hello');
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

  // Sign-in now exists: the gate is tested in caption_access_test.dart.
}
