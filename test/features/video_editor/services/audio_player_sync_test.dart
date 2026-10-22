import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/services/audio_player_manager.dart';

/// Imported music keeps time with the playhead.
///
/// It started late — `play()` went out before its seek had finished, on the
/// first position update after the playhead reached it — and while playing it
/// was only corrected once more than half a second out, so the lateness it
/// started with stayed for the whole track.
class FakeMusicPlayer implements MusicPlayer {
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  final log = <String>[];
  Completer<void>? seekGate;

  @override
  Future<void> setFilePath(String path) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> seek(Duration to) async {
    log.add('seek ${to.inMilliseconds}');
    final gate = seekGate;
    if (gate != null) await gate.future;
    position = to;
  }

  @override
  void play() {
    log.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    log.add('pause');
    playing = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  const track = AudioTrackModel(
    id: 'm',
    filePath: '/m.mp3',
    sourceDuration: 60,
    sourceStart: 10,
    sourceEnd: 60,
    timelineStart: 0,
  );

  late FakeMusicPlayer player;
  late Duration now;
  late AudioPlayerManager manager;

  setUp(() async {
    player = FakeMusicPlayer();
    now = Duration.zero;
    manager = AudioPlayerManager(createPlayer: () => player, clock: () => now);
    await manager.syncTracks([track]);
  });

  test('music starts where the playhead is when it plays, not where it was asked', () async {
    final gate = player.seekGate = Completer<void>();
    manager.seekAndPlaySync(1.0, [track], true);
    expect(player.log, ['seek 11000'], reason: 'no play before the seek lands');

    // The seek takes 120 ms; the playhead has moved on by as much.
    now = const Duration(milliseconds: 120);
    gate.complete();
    await pumpEventQueue();

    expect(player.log, ['seek 11000', 'seek 11120', 'play']);
  });

  test('a fast seek plays without a second one', () async {
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, ['seek 11000', 'play']);
  });

  test('while playing, drift under 0.1 s is left alone and over it is corrected', () async {
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    player.log.clear();

    // Past the start's grace, 80 ms out: left alone.
    now = const Duration(seconds: 2);
    player.position = const Duration(milliseconds: 11000 - 80);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, isEmpty);

    // 150 ms out: corrected — the old rule waited for half a second.
    player.position = const Duration(milliseconds: 11000 - 150);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, ['seek 11000']);
  });

  test('corrections are at least 1.5 s apart, the start counting as one', () async {
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    player.log.clear();

    // Just after the start the player is still spinning up: not drift.
    now = const Duration(milliseconds: 500);
    player.position = const Duration(milliseconds: 11000 - 300);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, isEmpty);

    now = const Duration(milliseconds: 1600);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, ['seek 11000']);
  });
}
