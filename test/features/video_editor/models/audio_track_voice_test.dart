import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';

/// A voice made by Text to speech is an ordinary audio track that knows it
/// is a voice, and which text it speaks.
void main() {
  const plain = AudioTrackModel(
    id: 'm',
    filePath: '/m.mp3',
    sourceDuration: 30,
    sourceStart: 0,
    sourceEnd: 30,
    timelineStart: 0,
  );
  final voice = plain.copyWith(
    id: 'v',
    filePath: '/drafts/d1/audio/voice_text_1_5.mp3',
    isVoice: true,
    voiceForTextId: 'text_1',
  );

  test('a voice track round-trips its two fields, and a plain one writes neither',
      () {
    final json = voice.toJson();
    expect(json['isVoice'], isTrue);
    expect(json['voiceForTextId'], 'text_1');
    final back = AudioTrackModel.fromJson(json);
    expect((back.isVoice, back.voiceForTextId), (true, 'text_1'));

    // A draft without voices is byte-identical to one saved before them.
    expect(plain.toJson(), {
      'id': 'm',
      'filePath': '/m.mp3',
      'sourceDuration': 30.0,
      'sourceStart': 0.0,
      'sourceEnd': 30.0,
      'timelineStart': 0.0,
      'volume': 1.0,
      'laneIndex': 0,
    });
    final old = AudioTrackModel.fromJson(plain.toJson());
    expect((old.isVoice, old.voiceForTextId), (false, null));
  });

  test('a text id that is not a string reads as none', () {
    final read = AudioTrackModel.fromJson({
      ...plain.toJson(),
      'isVoice': true,
      'voiceForTextId': 7,
    });
    expect((read.isVoice, read.voiceForTextId), (true, null));
  });

  test('copyWith keeps a voice a voice, and can let go of its text', () {
    final moved = voice.copyWith(timelineStart: 4);
    expect((moved.isVoice, moved.voiceForTextId), (true, 'text_1'));

    final loose = voice.copyWith(clearVoiceForTextId: true);
    expect((loose.isVoice, loose.voiceForTextId), (true, null));
  });
}
