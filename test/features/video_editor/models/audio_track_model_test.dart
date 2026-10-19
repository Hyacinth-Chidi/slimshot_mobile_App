import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';

void main() {
  const track = AudioTrackModel(
    id: 'a',
    filePath: '/a.mp3',
    sourceDuration: 2,
    sourceStart: 0,
    sourceEnd: 2,
    timelineStart: 1,
  );

  test('a track is not a sound effect unless it says so', () {
    expect(track.isSoundEffect, isFalse);
  });

  test('a sound effect survives a draft', () {
    final effect = track.copyWith(isSoundEffect: true);
    expect(AudioTrackModel.fromJson(effect.toJson()).isSoundEffect, isTrue);
  });

  test('an ordinary track writes nothing new', () {
    expect(track.toJson().containsKey('isSoundEffect'), isFalse);
  });

  test('a track saved before sound effects reads as ordinary audio', () {
    final json = track.toJson()..remove('isSoundEffect');
    expect(AudioTrackModel.fromJson(json).isSoundEffect, isFalse);
  });

  test('moving or trimming a sound effect keeps it one', () {
    final effect = track.copyWith(isSoundEffect: true);
    expect(effect.copyWith(timelineStart: 3, sourceEnd: 1).isSoundEffect, isTrue);
  });
}
