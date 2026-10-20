import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/audio_tools/record_controller.dart';
import 'package:slimshotai/features/audio_tools/voice_recorder_service.dart';

/// Every call the mode makes, in order, from recorder and editor alike.
final List<String> log = [];

class _FakeRecorder implements VoiceRecorder {
  Object? openError;
  var captured = false;

  @override
  Future<void> open(String outputPath) async {
    log.add('open $outputPath');
    if (openError != null) throw openError!;
  }

  @override
  Future<void> setCapturing(bool on, {double? alignTo}) async {
    log.add(on ? 'capture true at ${((alignTo ?? -1) * 1000).round()}' : 'capture false');
    if (on) captured = true;
  }

  @override
  Future<RecordedTake?> close({required bool keep}) async {
    log.add('close keep=$keep');
    if (!keep || !captured) return null;
    return const RecordedTake(path: '/d/voice.m4a', durationSeconds: 4.2);
  }
}

/// Recording mode: countdown, one take across pauses, the monitor mute, and
/// the ways a take can fail to start.
void main() {
  late _FakeRecorder recorder;
  late double playhead;
  late double projectEnd;
  late MicPermission permission;
  late List<int> countdownSeen;
  late Future<String> Function() takePath;

  RecordController controller() {
    final c = RecordController(
      recorder: recorder,
      requestMic: () async {
        log.add('ask mic');
        return permission;
      },
      newTakePath: () => takePath(),
      play: () => log.add('play'),
      pause: () => log.add('pause'),
      setMonitorMuted: (muted) => log.add('monitor muted=$muted'),
      playhead: () => playhead,
      projectEnd: () => projectEnd,
      wait: (_) async {},
    );
    c.addListener(() {
      if (c.phase == RecordPhase.countdown &&
          (countdownSeen.isEmpty || countdownSeen.last != c.countdown)) {
        countdownSeen.add(c.countdown);
      }
    });
    return c;
  }

  setUp(() {
    log.clear();
    recorder = _FakeRecorder();
    playhead = 2.0;
    projectEnd = 20.0;
    permission = MicPermission.granted;
    countdownSeen = [];
    takePath = () async => '/d/voice.m4a';
  });

  test('entering mutes the preview, leaving restores it', () async {
    final c = controller();
    await c.enter();
    expect(c.monitorMuted, isTrue);
    await c.discard();
    expect(log.where((l) => l.startsWith('monitor')), ['monitor muted=true', 'monitor muted=false']);
  });

  test('the toggle unmutes and mutes again', () async {
    final c = controller();
    await c.enter();
    c.toggleMonitor();
    expect(c.monitorMuted, isFalse);
    c.toggleMonitor();
    expect(c.monitorMuted, isTrue);
    expect(log.where((l) => l.startsWith('monitor')).toList(),
        ['monitor muted=true', 'monitor muted=false', 'monitor muted=true']);
  });

  test('first record asks for the mic, a resume does not', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    await c.toggle();
    await c.toggle();
    expect(log.where((l) => l == 'ask mic').length, 1);
  });

  test('a refused mic says how to allow it and stays idle', () async {
    permission = MicPermission.denied;
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.phase, RecordPhase.idle);
    expect(c.takeMessage(), kMicDeniedMessage);
    expect(c.needsSettings, isFalse);
    expect(log, isNot(contains('play')));
  });

  test('a permanently refused mic says to open Settings', () async {
    permission = MicPermission.permanentlyDenied;
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.phase, RecordPhase.idle);
    expect(c.takeMessage(), kMicBlockedMessage);
    expect(c.needsSettings, isTrue);
  });

  test('a recorder that will not open says so and stays idle', () async {
    recorder.openError = const VoiceRecorderException('The microphone is in use or unavailable.');
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.phase, RecordPhase.idle);
    expect(c.takeMessage(), 'The microphone is in use or unavailable.');
    expect(log, isNot(contains('play')));
  });

  test('countdown runs 3-2-1 before capturing', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(countdownSeen, [3, 2, 1]);
    expect(c.phase, RecordPhase.recording);
  });

  List<String> captures() => log.where((l) => l.startsWith('capture true')).toList();

  test('capture waits for the video to move', () async {
    // Before play the editor composes the timeline and seeks — a decoder
    // flush, up to a few hundred milliseconds on a low-end phone. Kept from
    // the moment play was asked for, every word in that gap would land that
    // much late against the picture.
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(log, contains('play'));
    expect(captures(), isEmpty);
    c.onPlayhead(2.0);
    expect(captures(), isEmpty, reason: 'parked, not yet moving');
    c.onPlayhead(2.04);
    expect(captures(), ['capture true at 40'],
        reason: 'silence pads the take to the frame the video moved on');
  });

  test('pause stops capture, then the video', () async {
    // The other way round, the take kept the sound of the moment the video
    // took to stop — sound nothing can take out again, so everything after
    // the next resume would land that much late.
    final c = controller();
    await c.enter();
    await c.toggle();
    c.onPlayhead(2.1);
    log.clear();
    await c.toggle();
    expect(log, ['capture false', 'pause']);
    expect(c.phase, RecordPhase.paused);
  });

  test('a resume lines the take up with the picture', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    c.onPlayhead(2.04);
    c.onPlayhead(3.0);
    await c.toggle();
    // The video stopped a moment after the capture did.
    playhead = 3.02;
    await c.toggle();
    log.clear();
    c.onPlayhead(3.02);
    c.onPlayhead(3.06);
    expect(log, ['capture true at 1060']);
  });

  test('pressing pause before the video moves keeps nothing and starts nothing', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    log.clear();
    await c.toggle();
    expect(log, ['capture false', 'pause']);
    c.onPlayhead(2.5);
    expect(captures(), isEmpty, reason: 'a late playhead after a pause starts nothing');
  });

  test('one take across pauses', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    c.onPlayhead(2.1);
    await c.toggle();
    await c.toggle();
    c.onPlayhead(2.2);
    await c.toggle();
    final take = await c.finish();
    expect(log.where((l) => l.startsWith('open')).length, 1);
    expect(log.where((l) => l.startsWith('close')).toList(), ['close keep=true']);
    expect(take, isNotNull);
  });

  test('the take starts where the playhead was', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.takeStart, 2.0);
    playhead = 3.5;
    c.onPlayhead(3.5);
    expect(c.takeLength, closeTo(1.5, 1e-9));
    await c.toggle();
    await c.toggle();
    expect(c.takeStart, 2.0, reason: 'a resume does not move the start');
    final take = await c.finish();
    expect(take!.timelineStart, 2.0);
    expect(take.path, '/d/voice.m4a');
    expect(take.durationSeconds, 4.2);
  });

  test('reaching the end pauses', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    log.clear();
    c.onPlayhead(20.0);
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, RecordPhase.paused);
    expect(log, ['capture false', 'pause'], reason: 'nothing is started at the end');
  });

  test('playback stopping elsewhere pauses the take', () async {
    // The end of the project, or anything else that stops the video, must
    // stop the take with it — a take that ran on over a still picture would
    // no longer line up with what was on screen.
    final c = controller();
    await c.enter();
    await c.toggle();
    log.clear();
    c.onPlaybackStopped();
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, RecordPhase.paused);
    expect(log, ['capture false']);
  });

  test('at the end already it says to move back and does not start', () async {
    playhead = 20.0;
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.phase, RecordPhase.idle);
    expect(c.takeMessage(), kRecordAtEndMessage);
    expect(log, isNot(contains('ask mic')));
  });

  test('Done with nothing recorded adds nothing', () async {
    final c = controller();
    await c.enter();
    expect(await c.finish(), isNull);
    expect(log, isNot(contains('play')));
  });

  test('✕ keeps nothing', () async {
    final c = controller();
    await c.enter();
    await c.toggle();
    await c.discard();
    expect(log, contains('close keep=false'));
    expect(c.phase, RecordPhase.idle);
  });

  test('a take that cannot be created says so and stays idle', () async {
    // The project's folder could not be written: a full or locked storage.
    takePath = () async => throw const FileSystemException('read-only');
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.phase, RecordPhase.idle);
    expect(c.takeMessage(), kRecordStartFailedMessage);
    expect(log, isNot(contains('play')));
    expect(log.where((l) => l.startsWith('open')), isEmpty);
  });

  test('a message is read once', () async {
    playhead = 20.0;
    final c = controller();
    await c.enter();
    await c.toggle();
    expect(c.takeMessage(), isNotNull);
    expect(c.takeMessage(), isNull);
  });
}
