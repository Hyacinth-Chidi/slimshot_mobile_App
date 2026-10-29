import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/account/logic/account_copy.dart';
import 'package:slimshotai/features/account/models/account_models.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/logic/captions/captions_mode.dart';
import 'package:slimshotai/features/video_editor/logic/text_look.dart';
import 'package:slimshotai/features/video_editor/services/caption_audio_result.dart';
import 'package:slimshotai/features/video_editor/services/caption_errors.dart';
import 'package:slimshotai/features/video_editor/services/caption_pipeline.dart';
import 'package:slimshotai/features/video_editor/services/caption_run.dart';
import 'package:slimshotai/features/video_editor/widgets/captions_mode/captions_mode_view.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/caption_preset_tile.dart';

import '../../../support/caption_pipelines.dart';
import '../../../support/test_fonts.dart';

/// The real catalog's faces are downloaded, which a test cannot load, so the
/// view is handed styles of its own in the bundled test face.
const _presets = [
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

class _Calls {
  final languages = <String?>[];
  final lengths = <CaptionLength>[];
  final presets = <CaptionPreset>[];
  final colors = <Color>[];
  int generates = 0;
  int cancels = 0;
  int backs = 0;
  int editWords = 0;
  int exports = 0;
  int openEditor = 0;
}

/// The captions screen — the editor's captions mode — as a picture of its
/// step: Ready, Generating (the run drawn on the card), Done.
void main() {
  late List<CaptionRun> runs;

  setUp(() => runs = []);
  tearDown(() {
    for (final run in runs) {
      run.dispose();
    }
  });

  /// A started run on [pipeline], disposed after the test.
  CaptionRun runOn(CaptionPipeline pipeline) {
    final run = CaptionRun(
      pipeline: pipeline,
      request: const CaptionRequest(),
      heldWork: HeldWork(),
    )..start();
    runs.add(run);
    return run;
  }

  Future<_Calls> pumpView(
    WidgetTester tester, {
    required CaptionsStep step,
    CaptionRun? run,
    String? notice,
    bool generateOn = true,
    ({TextLook look, CaptionHighlight highlight})? style,
    Size size = const Size(390, 844),
    double textScale = 1,
    List<CaptionPreset> presets = _presets,
    bool playing = false,
    Widget? preview,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final calls = _Calls();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: CaptionsModeView(
        step: step,
        preview: preview ??
            const ColoredBox(key: Key('preview'), color: Colors.blue),
        playing: playing,
        aspectRatio: 9 / 16,
        onBack: () => calls.backs++,
        language: null,
        length: CaptionLength.phrase,
        onLanguage: calls.languages.add,
        onLength: calls.lengths.add,
        onGenerate: generateOn ? () => calls.generates++ : null,
        notice: notice,
        run: run,
        onCancel: () => calls.cancels++,
        earnCredits: (quote, onEarned) => const Text('earn'),
        style: style ?? (look: _presets[1].look, highlight: _presets[1].highlight),
        onPreset: calls.presets.add,
        onColor: calls.colors.add,
        onEditWords: () => calls.editWords++,
        onExport: () => calls.exports++,
        onOpenEditor: () => calls.openEditor++,
        presets: presets,
      ),
    ));
    await tester.pump();
    await tester.pump();
    return calls;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A render that reports [progress] and then waits for ever.
  CaptionPipeline preparing({double progress = 0}) => fakeCaptionPipeline(
        render: (onProgress) {
          onProgress(progress);
          return Completer<CaptionAudioResult>().future;
        },
      );

  group('Ready', () {
    testWidgets(
        'the title, Language and Length on the defaults, Generate — no ✎, '
        'no styles', (tester) async {
      final calls = await pumpView(tester, step: CaptionsStep.ready);
      expect(find.text('Auto captions'), findsOneWidget);
      expect(find.byKey(const Key('caption_language_auto')), findsOneWidget);
      expect(find.byKey(const Key('caption_length_phrase')), findsOneWidget);
      expect(find.byKey(const Key('preview')), findsOneWidget);

      await tapKey(tester, 'caption_length_word');
      expect(calls.lengths, [CaptionLength.word]);
      final other = kCaptionLanguages[1].code;
      await tapKey(tester, 'caption_language_$other');
      expect(calls.languages, [other]);
      await tapKey(tester, 'captions_generate');
      expect(calls.generates, 1);

      expect(find.byKey(const Key('captions_open_editor')), findsNothing);
      expect(find.byType(CaptionPresetTile), findsNothing);
    });

    testWidgets('Ready settles: no tile animates off Done', (tester) async {
      await pumpView(tester, step: CaptionsStep.ready);
      await tester.pumpAndSettle();
    });

    testWidgets('Generate is off while a run is being started',
        (tester) async {
      final calls =
          await pumpView(tester, step: CaptionsStep.ready, generateOn: false);
      await tapKey(tester, 'captions_generate');
      expect(calls.generates, 0);
    });

    testWidgets('Ready says why a run came back', (tester) async {
      await pumpView(
        tester,
        step: CaptionsStep.ready,
        notice: 'No sound to caption.',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('captions_notice'))).data,
        'No sound to caption.',
      );
    });
  });

  group('Generating', () {
    testWidgets('the ring and its percentage over the picture, the stage, '
        'Cancel', (tester) async {
      final calls = await pumpView(
        tester,
        step: CaptionsStep.generating,
        run: runOn(preparing(progress: 0.5)),
      );
      final card = find.byKey(const Key('captions_card'));
      expect(
        find.descendant(of: card, matching: find.byKey(const Key('captions_ring'))),
        findsOneWidget,
      );
      expect(find.descendant(of: card, matching: find.text('50%')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.byKey(const Key('preview'))),
          findsOneWidget);
      expect(find.text('Writing captions…'), findsOneWidget);
      expect(find.text('Preparing audio'), findsOneWidget);
      expect(find.byKey(const Key('captions_open_editor')), findsNothing);

      await tapKey(tester, 'captions_cancel');
      expect(calls.cancels, 1);
    });

    testWidgets('a stage with no number spins without one', (tester) async {
      await pumpView(
        tester,
        step: CaptionsStep.generating,
        run: runOn(fakeCaptionPipeline(
          render: (_) async => kSoundRendered,
          transcript: () => Completer<CaptionTranscript>().future,
        )),
      );
      await tester.pump();
      expect(find.text('Listening'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.byKey(const Key('captions_ring')), findsOneWidget);
    });

    testWidgets('a failure shows its line, Cancel and Try again',
        (tester) async {
      var first = true;
      final calls = await pumpView(
        tester,
        step: CaptionsStep.generating,
        run: runOn(fakeCaptionPipeline(render: (_) {
          if (first) {
            first = false;
            return Future.error(PlatformException(code: 'x'));
          }
          return Completer<CaptionAudioResult>().future;
        })),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('caption_error'))).data,
        captionErrorMessage(PlatformException(code: 'x')),
      );
      expect(find.byKey(const Key('captions_cancel')), findsOneWidget);

      await tapKey(tester, 'captions_retry');
      expect(find.byKey(const Key('caption_error')), findsNothing);
      expect(find.text('Preparing audio'), findsOneWidget);
      expect(calls.cancels, 0);
    });

    testWidgets('a shortfall says how many, with the ways to earn, in place',
        (tester) async {
      await pumpView(
        tester,
        step: CaptionsStep.generating,
        run: runOn(fakeCaptionPipeline(
          render: (_) async => kSoundRendered,
          quote: const CreditQuote(credits: 30, balance: 0, enough: false),
        )),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('caption_price'))).data,
        shortfallLine(30, 0),
      );
      expect(find.text('earn'), findsOneWidget);
      expect(find.byKey(const Key('captions_cancel')), findsOneWidget);
    });
  });

  // The tiles loop for ever, so these pump frames: pumpAndSettle would time
  // out.
  group('Done', () {
    testWidgets(
        'Edit words, the styles with the current one marked, the colours, '
        'Export and ✎', (tester) async {
      final calls = await pumpView(tester, step: CaptionsStep.done);

      CaptionPresetTile tile(String id) => tester.widget<CaptionPresetTile>(
          find.byKey(Key('captions_style_$id')));
      expect(tile('b').isSelected, isTrue);
      expect(tile('a').isSelected, isFalse);
      expect(tile('c').isSelected, isFalse);

      await tapKey(tester, 'captions_style_c');
      expect(calls.presets, [_presets[2]]);
      await tapKey(tester, 'captions_color_2');
      expect(calls.colors, [kCaptionHighlightColors[2]]);
      await tapKey(tester, 'captions_edit_words');
      await tapKey(tester, 'captions_export');
      await tapKey(tester, 'captions_open_editor');
      expect(calls.editWords, 1);
      expect(calls.exports, 1);
      expect(calls.openEditor, 1);
    });

    testWidgets('the colours are dimmed and deaf where the style lights in no '
        'colour', (tester) async {
      final calls = await pumpView(
        tester,
        step: CaptionsStep.done,
        style: (
          look: _presets[0].look,
          highlight: const CaptionHighlight(style: CaptionHighlightStyle.reveal),
        ),
      );
      await tapKey(tester, 'captions_color_0');
      expect(calls.colors, isEmpty);
    });
  });

  testWidgets("the phone's Back is the back button", (tester) async {
    final calls = await pumpView(tester, step: CaptionsStep.done);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(calls.backs, 1);
    await tapKey(tester, 'captions_back');
    expect(calls.backs, 2);
  });

  // Device-reported: a large empty band between Length and Generate. The
  // video takes the room the controls leave, so they sit just above the
  // button and the picture is as large as the screen allows.
  testWidgets('on Ready the video takes the room: the Length row sits just '
      'above Generate', (tester) async {
    await pumpView(tester, step: CaptionsStep.ready);
    final length = tester.getRect(find.byKey(const Key('captions_length_row')));
    final generate = tester.getRect(find.byKey(const Key('captions_generate')));
    expect(generate.top - length.bottom, lessThan(40));
    final card = tester.getSize(find.byKey(const Key('captions_card')));
    expect(card.height, greaterThan(844 * 0.5));
  });

  // Generate must not make the picture jump: the card keeps its size from
  // Ready into the run.
  testWidgets('the video keeps its size from Ready to Generating',
      (tester) async {
    await pumpView(tester, step: CaptionsStep.ready);
    final ready = tester.getSize(find.byKey(const Key('captions_card')));
    await pumpView(
      tester,
      step: CaptionsStep.generating,
      run: runOn(preparing(progress: 0.2)),
    );
    final generating = tester.getSize(find.byKey(const Key('captions_card')));
    expect(generating.height, closeTo(ready.height, 0.5));
  });

  testWidgets("the card keeps the project's frame", (tester) async {
    await pumpView(tester, step: CaptionsStep.ready);
    final card = tester.getSize(find.byKey(const Key('captions_card')));
    expect(card.width / card.height, closeTo(9 / 16, 1e-2));
  });

  testWidgets('no step overflows a small phone with large text',
      (tester) async {
    Future<void> check(CaptionsStep step, {CaptionRun? run, String? notice}) async {
      await pumpView(
        tester,
        step: step,
        run: run,
        notice: notice,
        size: const Size(320, 568),
        textScale: 1.3,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: step.name);
      // The rows scroll before the picture shrinks past use.
      expect(
        tester.getSize(find.byKey(const Key('captions_card'))).height,
        greaterThanOrEqualTo(150),
        reason: step.name,
      );
    }

    await check(CaptionsStep.ready, notice: 'No sound to caption.');
    await check(CaptionsStep.generating, run: runOn(preparing(progress: 0.3)));
    await check(
      CaptionsStep.generating,
      run: runOn(fakeCaptionPipeline(
        render: (_) async => kSoundRendered,
        quote: const CreditQuote(credits: 30, balance: 0, enough: false),
      )),
    );
    await check(
      CaptionsStep.generating,
      run: runOn(fakeCaptionPipeline(
        render: (_) => Future.error(PlatformException(code: 'x')),
      )),
    );
    await check(CaptionsStep.done);
  });

  // The editor rebuilds on every playhead report while the video plays; the
  // tiles must stay still while their row scrolls, or the scroll pays for
  // every tile's text layout each frame — the device-reported roughness the
  // hold exists for.
  testWidgets('a rebuild mid-scroll keeps the style tiles still',
      (tester) async {
    final many = [
      for (var i = 0; i < 8; i++)
        CaptionPreset(
          id: 'p$i',
          name: 'Style $i',
          look: TextLook(
            fontFamily: kTestFontFamily,
            color: Color(0xFF000000 + i * 0x101010),
          ),
        ),
    ];
    await pumpView(tester, step: CaptionsStep.done, presets: many);
    AnimationController clock() => tester
        .widget<CaptionPresetTile>(find.byKey(const Key('captions_style_p0')))
        .clock! as AnimationController;
    expect(clock().isAnimating, isTrue);

    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('captions_style_p1'))),
    );
    await finger.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(clock().isAnimating, isFalse, reason: 'held while it scrolls');

    // A playhead report rebuilds the screen: the hold stays.
    await pumpView(tester, step: CaptionsStep.done, presets: many);
    expect(clock().isAnimating, isFalse);

    await finger.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(clock().isAnimating, isTrue, reason: 'it plays again once still');
  });

  // Without a cue nobody knows the picture plays at a tap: a faded play icon
  // sits on it while it is paused, and fades out while it plays.
  testWidgets('a paused video wears a faded play icon, and playing fades it '
      'out', (tester) async {
    await pumpView(tester, step: CaptionsStep.ready);
    final hint = find.byKey(const Key('captions_play_hint'));
    expect(
      find.descendant(of: find.byKey(const Key('captions_card')), matching: hint),
      findsOneWidget,
    );
    expect(find.descendant(of: hint, matching: find.byIcon(LucideIcons.play)),
        findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(hint).opacity, 1);

    await pumpView(tester, step: CaptionsStep.ready, playing: true);
    expect(tester.widget<AnimatedOpacity>(hint).opacity, 0);
  });

  testWidgets('a tap on the play icon reaches the video', (tester) async {
    var taps = 0;
    await pumpView(
      tester,
      step: CaptionsStep.done,
      preview: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => taps++,
        child: const ColoredBox(key: Key('preview'), color: Colors.blue),
      ),
    );
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('captions_play_hint'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, 1);
  });

  testWidgets('no play icon while the words are made', (tester) async {
    await pumpView(
      tester,
      step: CaptionsStep.generating,
      run: runOn(preparing()),
    );
    expect(find.byKey(const Key('captions_play_hint')), findsNothing);
  });
}
