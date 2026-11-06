import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/reaction_sound.dart';

/// Finding where you talked in a take, from its loudness, and the volume
/// curve that lowers the video under it.
void main() {
  /// A take's loudness in 50ms buckets: the speaker's copy of the video at
  /// [bleed] throughout, your voice at [voice] through [talking] (bucket
  /// ranges, end exclusive).
  List<double> take(int buckets, {double bleed = 0.08, double voice = 0.9, List<(int, int)> talking = const []}) => [
        for (var i = 0; i < buckets; i++)
          talking.any((t) => i >= t.$1 && i < t.$2) ? voice : bleed,
      ];

  group('where you talked', () {
    test('a stretch of talking over the video is found, padded at both ends', () {
      final speech = speechSpans(take(100, talking: [(20, 40)]), bucketMs: 50)!;
      expect(speech, [
        const ReactionSpeech(1000 - kSpeechLeadMs, 2000 + kSpeechTailMs),
      ]);
    });

    test('a short pause between words does not open the gap', () {
      final speech = speechSpans(take(100, talking: [(20, 30), (34, 44)]), bucketMs: 50)!;
      expect(speech, hasLength(1), reason: '200ms between words is one stretch of talking');
    });

    test('a long pause makes two stretches', () {
      final speech = speechSpans(take(200, talking: [(20, 40), (80, 100)]), bucketMs: 50)!;
      expect(speech, hasLength(2));
    });

    test('a click is not talking', () {
      final speech = speechSpans(take(200, talking: [(20, 40), (120, 121)]), bucketMs: 50)!;
      expect(speech, hasLength(1));
    });

    test('talking from the first instant is held to the start of the take', () {
      final speech = speechSpans(take(100, talking: [(0, 20)]), bucketMs: 50)!;
      expect(speech.single.startMs, 0);
    });

    test('a take where nothing stands out says nothing, rather than guessing', () {
      expect(speechSpans(take(100), bucketMs: 50), isNull, reason: 'no talking found: leave the sound as recorded');
      expect(speechSpans(List.filled(100, 0.0), bucketMs: 50), isNull, reason: 'no sound read at all');
      expect(speechSpans(const [], bucketMs: 50), isNull);
    });
  });

  group('the volume curve', () {
    test('the video goes down while you talk and back up after, ramped at each edge', () {
      final points = speechEnvelope(
        const [ReactionSpeech(1000, 2000)],
        fromMs: 0,
        toMs: 4000,
        inside: 0.25,
        outside: 1,
      );
      const ramp = kSpeechRampMs;
      expect(points, [
        (0.0, 1.0),
        ((1000 - ramp) / 4000, 1.0),
        (1000 / 4000, 0.25),
        (2000 / 4000, 0.25),
        ((2000 + ramp) / 4000, 1.0),
        (1.0, 1.0),
      ]);
    });

    test('a stretch that starts mid-talk starts low, and one that ends mid-ramp ends between', () {
      final points = speechEnvelope(
        const [ReactionSpeech(1000, 2000)],
        fromMs: 1500,
        toMs: 2075,
        inside: 0.25,
        outside: 1,
      );
      expect(points.first, (0.0, 0.25));
      expect(points.last.$1, 1.0);
      expect(points.last.$2, moreOrLessEquals(0.625));
    });

    test('no talking in the stretch is no curve at all: the value is flat', () {
      expect(
        speechEnvelope(const [ReactionSpeech(9000, 9500)], fromMs: 0, toMs: 4000, inside: 0.25, outside: 1),
        isEmpty,
      );
    });

    test('the microphone opens the other way: up while you talk', () {
      final points = speechEnvelope(
        const [ReactionSpeech(1000, 2000)],
        fromMs: 0,
        toMs: 4000,
        inside: 1,
        outside: kReactionMicGateVolume,
      );
      expect(points.map((p) => p.$2), [kReactionMicGateVolume, kReactionMicGateVolume, 1, 1, kReactionMicGateVolume, kReactionMicGateVolume]);
    });
  });

  test('talking survives a round trip', () {
    const speech = ReactionSpeech(120, 3400);
    expect(ReactionSpeech.fromJson(speech.toJson()), speech);
    expect(ReactionSpeech.fromJson('junk'), isNull);
  });
}
