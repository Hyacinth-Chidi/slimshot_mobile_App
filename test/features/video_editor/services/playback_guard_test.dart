import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/playback_guard.dart';

import '../../../support/app_lifecycle.dart';

/// The guard's audio, recording what it was asked.
class _FakeAudio implements PlaybackAudio {
  final List<String> calls = [];
  final StreamController<void> _interruptions =
      StreamController<void>.broadcast();

  void interrupt() => _interruptions.add(null);

  @override
  Future<void> take() async => calls.add('take');

  @override
  Future<void> release() async => calls.add('release');

  @override
  Stream<void> get interruptions => _interruptions.stream;
}

/// The phone's audio session, as far as the guard's audio uses it.
class _FakeSession extends Fake implements AudioSession {
  final List<bool> active = [];
  final List<AudioSessionConfiguration> configurations = [];
  final StreamController<AudioInterruptionEvent> _interruptions =
      StreamController<AudioInterruptionEvent>.broadcast();
  final StreamController<void> _noisy = StreamController<void>.broadcast();

  /// Holds the first set-up open until completed: a slow start.
  Completer<void>? configuring;

  void interruption(bool begin, AudioInterruptionType type) =>
      _interruptions.add(AudioInterruptionEvent(begin, type));

  void headphonesOut() => _noisy.add(null);

  @override
  bool get isConfigured => configurations.isNotEmpty;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    await configuring?.future;
    configurations.add(configuration);
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    this.active.add(active);
    return true;
  }

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _interruptions.stream;

  @override
  Stream<void> get becomingNoisyEventStream => _noisy.stream;
}

Future<void> _drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('the guard', () {
    late _FakeAudio audio;
    late bool playing;
    late int pauses;

    setUp(() {
      audio = _FakeAudio();
      playing = false;
      pauses = 0;
    });

    Future<PlaybackGuard> guardFor(WidgetTester tester) async {
      await sendAppLifecycle(tester, AppLifecycleState.resumed);
      addTearDown(() => sendAppLifecycle(tester, AppLifecycleState.resumed));
      final guard = PlaybackGuard(
        audio: audio,
        isPlaying: () => playing,
        pause: () {
          pauses++;
          playing = false;
        },
      );
      addTearDown(guard.dispose);
      return guard;
    }

    testWidgets('minimising the app pauses what is playing', (tester) async {
      await guardFor(tester);
      playing = true;
      await sendAppLifecycle(tester, AppLifecycleState.hidden);
      expect(pauses, 1);
    });

    testWidgets('locking the screen pauses it too', (tester) async {
      await guardFor(tester);
      playing = true;
      await sendAppLifecycle(tester, AppLifecycleState.paused);
      expect(pauses, 1);
    });

    testWidgets(
      'still on screen — the notifications pulled down — it plays on',
      (tester) async {
        await guardFor(tester);
        playing = true;
        await sendAppLifecycle(tester, AppLifecycleState.inactive);
        expect(pauses, 0);
      },
    );

    testWidgets('minimising while paused does nothing', (tester) async {
      await guardFor(tester);
      await sendAppLifecycle(tester, AppLifecycleState.hidden);
      expect(pauses, 0);
    });

    testWidgets('coming back leaves it paused where it stopped', (
      tester,
    ) async {
      await guardFor(tester);
      playing = true;
      await sendAppLifecycle(tester, AppLifecycleState.hidden);
      await sendAppLifecycle(tester, AppLifecycleState.resumed);
      expect(pauses, 1);
      expect(playing, isFalse);
    });

    testWidgets('a call, another app or headphones coming out pause it', (
      tester,
    ) async {
      await guardFor(tester);
      playing = true;
      audio.interrupt();
      await tester.pump();
      expect(pauses, 1);
    });

    testWidgets('an interruption while paused does nothing', (tester) async {
      await guardFor(tester);
      audio.interrupt();
      await tester.pump();
      expect(pauses, 0);
    });

    testWidgets(
      'the audio is held while playing and given back when it stops',
      (tester) async {
        final guard = await guardFor(tester);
        guard.playingChanged(true);
        guard.playingChanged(true);
        guard.playingChanged(false);
        guard.playingChanged(false);
        expect(audio.calls, ['take', 'release']);
      },
    );

    testWidgets('closing the editor gives the audio back and stops listening', (
      tester,
    ) async {
      await sendAppLifecycle(tester, AppLifecycleState.resumed);
      addTearDown(() => sendAppLifecycle(tester, AppLifecycleState.resumed));
      final guard = PlaybackGuard(
        audio: audio,
        isPlaying: () => playing,
        pause: () => pauses++,
      );
      guard.playingChanged(true);
      playing = true;
      guard.dispose();
      expect(audio.calls, ['take', 'release']);
      audio.interrupt();
      await tester.pump();
      await sendAppLifecycle(tester, AppLifecycleState.hidden);
      expect(pauses, 0);
    });
  });

  group("the phone's audio session", () {
    test('takes and releases reach it in the order asked, a slow start '
        'included', () async {
      final session = _FakeSession()..configuring = Completer<void>();
      final audio = SessionPlaybackAudio(session: () async => session);
      final took = audio.take();
      final released = audio.release();
      await _drain();
      expect(session.active, isEmpty, reason: 'still setting up');
      session.configuring!.complete();
      await Future.wait([took, released]);
      expect(session.active, [true, false]);
      await audio.dispose();
    });

    test('it is set up once, for music', () async {
      final session = _FakeSession();
      final audio = SessionPlaybackAudio(session: () async => session);
      await audio.take();
      await audio.release();
      await audio.take();
      expect(session.configurations, hasLength(1));
      final music = session.configurations.single;
      expect(music.androidAudioAttributes?.usage, AndroidAudioUsage.media);
      expect(music.androidAudioFocusGainType, AndroidAudioFocusGainType.gain);
      await audio.dispose();
    });

    test('a call, another app or headphones coming out interrupt; the call '
        'ending does not', () async {
      final session = _FakeSession();
      final audio = SessionPlaybackAudio(session: () async => session);
      var heard = 0;
      final listening = audio.interruptions.listen((_) => heard++);
      await _drain();
      session.interruption(true, AudioInterruptionType.pause);
      session.interruption(true, AudioInterruptionType.unknown);
      session.interruption(false, AudioInterruptionType.pause);
      session.headphonesOut();
      await _drain();
      expect(heard, 3);
      await listening.cancel();
      await audio.dispose();
    });

    // A notification's ping asks the others to dip, not to stop: the phone
    // lowers the editor for a moment and it plays on. Pausing there would
    // stop every edit at every incoming message.
    test('a notification dipping the volume does not interrupt', () async {
      final session = _FakeSession();
      final audio = SessionPlaybackAudio(session: () async => session);
      var heard = 0;
      final listening = audio.interruptions.listen((_) => heard++);
      await _drain();
      session.interruption(true, AudioInterruptionType.duck);
      session.interruption(false, AudioInterruptionType.duck);
      await _drain();
      expect(heard, 0);
      await listening.cancel();
      await audio.dispose();
    });

    test('a session it cannot reach is no error', () async {
      final audio = SessionPlaybackAudio(
        session: () async => throw MissingPluginException(),
      );
      await audio.take();
      await audio.release();
      await audio.dispose();
    });

    test('disposed, it hears nothing more', () async {
      final session = _FakeSession();
      final audio = SessionPlaybackAudio(session: () async => session);
      var heard = 0;
      audio.interruptions.listen((_) => heard++);
      await _drain();
      await audio.dispose();
      session.headphonesOut();
      await _drain();
      expect(heard, 0);
    });
  });

  // One owner for the editor's sound: a player that paused and resumed
  // itself around a call would play music over an editor the guard paused.
  test("the editor's music players leave interruptions to the guard", () {
    final players = <String>[];
    for (final file
        in Directory('lib/features/video_editor')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'\bAudioPlayer\(([^)]*)\)',
      ).allMatches(source)) {
        players.add(file.path);
        expect(
          match.group(1),
          contains('handleInterruptions: false'),
          reason: file.path,
        );
        expect(
          match.group(1),
          contains('handleAudioSessionActivation: false'),
          reason: file.path,
        );
      }
    }
    expect(players, isNotEmpty, reason: 'the music player is found');
  });
}
