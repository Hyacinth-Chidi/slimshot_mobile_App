import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/video_editor/logic/speech/speech_request.dart';
import 'package:slimshotai/features/video_editor/logic/speech/voice_clip.dart';
import 'package:slimshotai/features/video_editor/services/speech_run.dart';
import 'package:slimshotai/features/video_editor/services/speech_service.dart';
import 'package:slimshotai/features/video_editor/services/voice_sample_player.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/text_to_speech_sheet.dart';

import '../../../../support/app_lifecycle.dart';
import '../../../../support/speech_pipelines.dart';

class FakeSamples implements VoiceSamplePlayer {
  final List<String> played = [];
  int stops = 0;
  final ValueNotifier<String?> _playing = ValueNotifier(null);

  @override
  ValueListenable<String?> get playing => _playing;

  @override
  Future<void> play(String url) async {
    played.add(url);
    _playing.value = url;
  }

  @override
  Future<void> stop() async {
    stops++;
    _playing.value = null;
  }

  @override
  Future<void> dispose() async {}
}

const eve = SpeechVoice(id: 'v1', label: 'Eve', sampleUrl: 'https://cdn.test/eve.mp3');
const rex = SpeechVoice(id: 'v2', label: 'Rex', sampleUrl: 'https://cdn.test/rex.mp3');

const one = SpeechReady([
  SpeechTarget(textId: 'a', text: 'Hello', startSeconds: 1),
], 5);

void main() {
  late FakeSamples samples;
  late SpeechFakes fakes;
  late HeldWork held;
  late List<(String, SpeechReady)> runs;
  late List<List<VoiceClip>> handed;
  late List<bool> planned;

  setUp(() {
    samples = FakeSamples();
    fakes = SpeechFakes();
    held = HeldWork();
    runs = [];
    handed = [];
    planned = [];
  });

  TextToSpeechSheet sheet({
    Future<List<SpeechVoice>> Function()? voices,
    SpeechPlan Function(bool applyToAll)? plan,
    SpeechSheetMemory? memory,
  }) =>
      TextToSpeechSheet(
        loadVoices: voices ?? () async => const [eve, rex],
        plan: (all) {
          planned.add(all);
          return plan == null ? one : plan(all);
        },
        newRun: (voiceId, plan) {
          runs.add((voiceId, plan));
          return SpeechRun(
            pipeline: fakes.pipeline(),
            voiceId: voiceId,
            plan: plan,
            heldWork: held,
          );
        },
        samples: samples,
        onVoices: handed.add,
        earnCredits: (quote, onEarned) => TextButton(
          key: const Key('earn'),
          onPressed: () => onEarned(quote.credits),
          child: const Text('Watch an ad'),
        ),
        memory: memory,
      );

  /// Opens [child] as an editor sheet, the way the editor does.
  Future<void> open(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showEditorSheet<void>(context, builder: (_) => child),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('lists the voices with a play button each, and plays one sample '
      'at a time', (tester) async {
    await open(tester, sheet());

    expect(find.text('Eve'), findsOneWidget);
    expect(find.text('Rex'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('speech_voice_v1')),
        matching: find.byIcon(LucideIcons.play),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.play), findsNWidgets(2));

    await tapKey(tester, 'speech_voice_v1');
    expect(samples.played, ['https://cdn.test/eve.mp3']);
    expect(
      find.descendant(
        of: find.byKey(const Key('speech_voice_v1')),
        matching: find.byIcon(LucideIcons.square),
      ),
      findsOneWidget,
      reason: 'the playing sample shows its stop',
    );

    await tapKey(tester, 'speech_voice_v2');
    expect(samples.played, ['https://cdn.test/eve.mp3', 'https://cdn.test/rex.mp3']);
    expect(find.byIcon(LucideIcons.square), findsOneWidget);

    // A tap on the one playing stops it.
    await tapKey(tester, 'speech_voice_v2');
    expect(samples.played, hasLength(2));
    expect(find.byIcon(LucideIcons.square), findsNothing);
  });

  testWidgets('closing the sheet stops the sample', (tester) async {
    await open(tester, sheet());
    await tapKey(tester, 'speech_voice_v1');
    final before = samples.stops;

    await tester.tapAt(const Offset(10, 10)); // outside the sheet
    await tester.pumpAndSettle();
    expect(find.byType(TextToSpeechSheet), findsNothing);
    expect(samples.stops, greaterThan(before));
  });

  testWidgets('the sample stops when the app leaves the screen', (tester) async {
    await open(tester, sheet());
    await tapKey(tester, 'speech_voice_v1');
    final before = samples.stops;

    await sendAppLifecycle(tester, AppLifecycleState.hidden);
    await tester.pump();
    expect(samples.stops, greaterThan(before));
    await sendAppLifecycle(tester, AppLifecycleState.resumed);
  });

  testWidgets('Generate is off for an empty text, and says why a too-long one '
      'cannot go', (tester) async {
    await open(tester, sheet(plan: (_) => const SpeechNothing()));
    await tester.tap(find.byKey(const Key('speech_generate')), warnIfMissed: false);
    await tester.pump();
    expect(runs, isEmpty);
    expect(find.byKey(const Key('speech_plan_message')), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // close it
    await tester.pumpAndSettle();

    await open(tester, sheet(plan: (_) => const SpeechTooLong('a')));
    expect(
      find.text('That text is too long for one voice. Split it into shorter texts.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('speech_generate')), warnIfMissed: false);
    await tester.pump();
    expect(runs, isEmpty);
  });

  testWidgets('Apply to all texts voices every plain text', (tester) async {
    await open(tester, sheet(plan: (all) => all ? kTwoTexts : one));

    expect(find.text('Apply to all texts'), findsOneWidget);
    await tapKey(tester, 'speech_apply_all');
    expect(planned.last, isTrue);

    await tapKey(tester, 'speech_generate');
    expect(runs.single.$1, 'v1', reason: 'the first voice is chosen to start');
    expect(runs.single.$2, same(kTwoTexts));
  });

  testWidgets('while running: a ring and Cancel; a failure\'s line and Try again',
      (tester) async {
    final heard = Completer<List<SpokenItem>>();
    fakes.awaitWith = (_) => heard.future;
    await open(tester, sheet());

    await tapKey(tester, 'speech_generate');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Making the voice'), findsOneWidget);
    expect(held.isHeld, isTrue);

    await tapKey(tester, 'speech_cancel');
    expect(fakes.cancels, 1);
    expect(held.isHeld, isFalse);
    expect(find.byKey(const Key('speech_generate')), findsOneWidget,
        reason: 'Cancel goes back to the voices');

    fakes.awaitWith = null;
    fakes.startFailure = const SlimshotApiException(SlimshotApiException.network);
    await tapKey(tester, 'speech_generate');
    await tester.pump();
    expect(find.text('No internet connection.'), findsOneWidget);

    fakes.startFailure = null;
    await tapKey(tester, 'speech_retry');
    await tester.pump();
    expect(handed.single.single.textId, 'a');
  });

  testWidgets("a shortfall shows 'Needs N credits · You have M' with the earn "
      'block', (tester) async {
    fakes.quote = kShort;
    await open(tester, sheet());

    await tapKey(tester, 'speech_generate');
    await tester.pump();
    expect(find.text('Needs 30 credits · You have 0'), findsOneWidget);
    expect(fakes.started, isEmpty);

    // Earning the difference carries the run on.
    await tapKey(tester, 'earn');
    await tester.pump();
    expect(fakes.started, hasLength(1));
  });

  testWidgets('offline, the voices say No internet connection, with Retry',
      (tester) async {
    var calls = 0;
    await open(
      tester,
      sheet(voices: () async {
        if (++calls == 1) {
          throw const SlimshotApiException(SlimshotApiException.network);
        }
        return const [eve];
      }),
    );

    expect(find.text('No internet connection.'), findsOneWidget);
    await tapKey(tester, 'speech_voices_retry');
    expect(calls, 2);
    expect(find.text('Eve'), findsOneWidget);
  });

  testWidgets('no voices offered says Text to speech is unavailable right now',
      (tester) async {
    await open(tester, sheet(voices: () async => const []));

    expect(find.text('Text to speech is unavailable right now.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('speech_generate')), warnIfMissed: false);
    await tester.pump();
    expect(runs, isEmpty);
  });

  testWidgets('a finished run hands its voices over and closes', (tester) async {
    await open(tester, sheet(plan: (_) => kTwoTexts));

    await tapKey(tester, 'speech_generate');
    await tester.pumpAndSettle();

    expect(handed.single.map((c) => c.textId), ['a', 'b']);
    expect(find.byType(TextToSpeechSheet), findsNothing);
  });

  testWidgets('the session remembers the list and the voice last chosen',
      (tester) async {
    final memory = SpeechSheetMemory();
    final slow = Completer<List<SpeechVoice>>();
    await open(tester, sheet(memory: memory));
    await tapKey(tester, 'speech_voice_v2');
    expect(memory.voiceId, 'v2');
    expect(memory.voices, const [eve, rex]);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Opened again: the last list shows while the new one is asked for, and
    // the voice last chosen is the one Generate uses.
    await open(tester, sheet(memory: memory, voices: () => slow.future));
    expect(find.text('Rex'), findsOneWidget);
    await tapKey(tester, 'speech_generate');
    expect(runs.last.$1, 'v2');
    slow.complete(const [eve, rex]);
  });
}
