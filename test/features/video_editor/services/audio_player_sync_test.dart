import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/services/audio_player_manager.dart';

/// Imported music keeps time with the playhead.
///
/// It started late — `play()` went out before its seek had finished, on the
/// first position update after the playhead reached it. While playing, only a
/// jump is corrected: a seek is heard, so ordinary drift is lived with.
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

  test('a steady lag while playing is lived with, never seeked', () async {
    // The music player and the engine are two players with no shared clock,
    // and the music is always a little behind — the time its sound takes to
    // start. Every seek while playing is heard as a click; correcting this
    // seeked every 1.5 s, and the music crackled.
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    player.log.clear();

    for (var ms = 32; ms <= 10000; ms += 32) {
      now = Duration(milliseconds: ms);
      final playhead = 1.0 + ms / 1000;
      player.position = Duration(milliseconds: (11000 + ms) - 150);
      manager.seekAndPlaySync(playhead, [track], true);
      await pumpEventQueue();
    }
    expect(player.log, isEmpty);
  });

  test('a jump past half a second is corrected, with one seek', () async {
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    player.log.clear();

    now = const Duration(seconds: 3);
    player.position = const Duration(milliseconds: 11000 - 400);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, isEmpty);

    // The seek takes 120 ms. Chasing the playhead with a second one would be
    // a second click; the start may, since nothing is heard yet.
    final gate = player.seekGate = Completer<void>();
    player.position = const Duration(milliseconds: 11000 - 600);
    manager.seekAndPlaySync(1.0, [track], true);
    now = const Duration(milliseconds: 3120);
    gate.complete();
    await pumpEventQueue();
    expect(player.log, ['seek 11000']);
  });

  test('corrections are at least 2 s apart, the start counting as one', () async {
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    player.log.clear();

    now = const Duration(milliseconds: 1500);
    player.position = const Duration(milliseconds: 11000 - 600);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, isEmpty);

    now = const Duration(milliseconds: 2100);
    manager.seekAndPlaySync(1.0, [track], true);
    await pumpEventQueue();
    expect(player.log, ['seek 11000']);
  });
}
