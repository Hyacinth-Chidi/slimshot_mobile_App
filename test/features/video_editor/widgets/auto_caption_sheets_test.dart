import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/services/caption_access.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/auto_caption_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/caption_progress_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/replace_captions_dialog.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/caption_preset_tile.dart';

import '../../../support/test_fonts.dart';

/// Caption styles in the bundled test face — the real catalog's downloaded
/// faces cannot load in a test.
const testPresets = [
  CaptionPreset(id: 'a', name: 'Alpha', look: TextLook(fontFamily: kTestFontFamily)),
  CaptionPreset(
    id: 'b',
    name: 'Beta',
    look: TextLook(fontFamily: kTestFontFamily, color: Color(0xFFFFC107)),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.karaoke),
  ),
  CaptionPreset(
    id: 'c',
    name: 'Gamma',
    look: TextLook(fontFamily: kTestFontFamily, strokeWidth: 3),
    highlight: CaptionHighlight(style: CaptionHighlightStyle.focus),
  ),
];

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
      final popped = await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
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
      final popped = await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
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
          presets: testPresets,
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

  group('the highlight', () {
    testWidgets('starts on None, and a choice travels with the request',
        (tester) async {
      final popped = await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
      expect(find.byKey(const Key('caption_highlight_none')), findsOneWidget);
      await tapKey(tester, 'caption_highlight_karaoke');
      await tapKey(tester, 'caption_highlight_color_2');
      await tapKey(tester, 'caption_generate');
      expect(
        (popped.single as CaptionRequest).highlight,
        CaptionHighlight(
          style: CaptionHighlightStyle.karaoke,
          color: kCaptionHighlightColors[2],
        ),
      );
    });

    testWidgets('offers every style', (tester) async {
      await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
      // The row scrolls sideways, like the Language row: the last chips are
      // built past the sheet's edge.
      for (final style in CaptionHighlightStyle.values) {
        expect(
          find.byKey(Key('caption_highlight_${style.name}'), skipOffstage: false),
          findsOneWidget,
          reason: style.name,
        );
      }
    });

    testWidgets('shows colours only for a style that lights in one',
        (tester) async {
      await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
      const swatch = Key('caption_highlight_color_0');
      expect(find.byKey(swatch), findsNothing);
      await tapKey(tester, 'caption_highlight_pill');
      expect(find.byKey(swatch), findsOneWidget);
      await tapKey(tester, 'caption_highlight_focus');
      expect(find.byKey(swatch), findsNothing);
    });

    testWidgets("reopens on the set's highlight", (tester) async {
      const pill = CaptionHighlight(
        style: CaptionHighlightStyle.pill,
        color: Color(0xFF0A84FF),
      );
      final popped = await open(
        tester,
        (_) => const AutoCaptionSheet(
          presets: testPresets,
          initial: CaptionSettings(setId: 's', highlight: pill),
        ),
      );
      await tapKey(tester, 'caption_generate');
      expect((popped.single as CaptionRequest).highlight, pill);
    });

    testWidgets('with a set present, each change reaches it at once',
        (tester) async {
      final applied = <CaptionHighlight>[];
      await open(
        tester,
        (_) => AutoCaptionSheet(
          presets: testPresets,
          initial: const CaptionSettings(setId: 's'),
          onHighlightChanged: applied.add,
        ),
      );
      await tapKey(tester, 'caption_highlight_pop');
      await tapKey(tester, 'caption_highlight_color_4');
      expect(applied, [
        const CaptionHighlight(style: CaptionHighlightStyle.pop),
        CaptionHighlight(
          style: CaptionHighlightStyle.pop,
          color: kCaptionHighlightColors[4],
        ),
      ]);
    });
  });

  group('the style', () {
    bool marked(WidgetTester tester, String id) => tester
        .widget<CaptionPresetTile>(find.byKey(Key('caption_preset_$id')))
        .isSelected;

    test('the sheet offers the real catalog unless told otherwise', () {
      expect(const AutoCaptionSheet().presets, same(kCaptionPresets));
    });

    testWidgets('shows every style, the first marked on a new set',
        (tester) async {
      await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
      expect(find.byType(CaptionPresetTile, skipOffstage: false),
          findsNWidgets(testPresets.length));
      await tester.ensureVisible(find.byKey(const Key('caption_preset_a')));
      expect(marked(tester, 'a'), isTrue);
      expect(marked(tester, 'b'), isFalse);
    });

    testWidgets('a style is the new set\'s look and highlight',
        (tester) async {
      final popped =
          await open(tester, (_) => const AutoCaptionSheet(presets: testPresets));
      await tapKey(tester, 'caption_preset_b');
      expect(marked(tester, 'b'), isTrue);
      // The Highlight row follows, so the style can be tuned from there.
      expect(find.byKey(const Key('caption_highlight_color_0')), findsOneWidget);
      await tapKey(tester, 'caption_generate');
      final request = popped.single as CaptionRequest;
      expect(request.look, testPresets[1].look);
      expect(request.highlight, testPresets[1].highlight);
    });

    testWidgets("reopens on the set's look, its style marked", (tester) async {
      await open(
        tester,
        (_) => AutoCaptionSheet(
          presets: testPresets,
          initial: CaptionSettings(setId: 's', highlight: testPresets[2].highlight),
          initialLook: testPresets[2].look,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('caption_preset_c')));
      expect(marked(tester, 'c'), isTrue);
      expect(marked(tester, 'a'), isFalse);
    });

    testWidgets('a hand-tuned look marks no style, and a new set keeps it',
        (tester) async {
      const tuned = TextLook(fontFamily: kTestFontFamily, color: Color(0xFF7C3AED));
      final popped = await open(
        tester,
        (_) => const AutoCaptionSheet(
          presets: testPresets,
          initial: CaptionSettings(setId: 's'),
          initialLook: tuned,
        ),
      );
      for (final p in testPresets) {
        await tester.ensureVisible(find.byKey(Key('caption_preset_${p.id}')));
        expect(marked(tester, p.id), isFalse, reason: p.id);
      }
      await tapKey(tester, 'caption_generate');
      expect((popped.single as CaptionRequest).look, tuned);
    });

    testWidgets('with a set present, a style reaches it at once',
        (tester) async {
      final chosen = <String>[];
      await open(
        tester,
        (_) => AutoCaptionSheet(
          presets: testPresets,
          initial: const CaptionSettings(setId: 's'),
          onPresetChosen: (p) => chosen.add(p.id),
        ),
      );
      await tapKey(tester, 'caption_preset_c');
      expect(chosen, ['c']);
    });
  });

  testWidgets('an unlisted language opens the sheet on Auto detect',
      (tester) async {
    final popped = await open(
      tester,
      (_) => const AutoCaptionSheet(
          presets: testPresets,
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
