import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// REACT's sound out loud: the video plays from the phone's speaker, so the
/// microphone hears it along with you. The reaction keeps the video's own,
/// clean sound and lowers it while you talk; your microphone comes through
/// only while you talk, so the speaker's copy it picked up does not double the
/// video's sound the rest of the time.
///
/// Where you talked is found from your take's loudness ([speechSpans]) after
/// the take; the two volume curves ([speechEnvelope]) become keyframes on the
/// video's layer and on your clip, so the editor plays them as the file does.
/// Every number here is a starting point, to be tuned on a phone.

/// The video's volume while you talk.
const double kReactionDuckVolume = 0.25;

/// Your microphone's volume while you are not talking.
const double kReactionMicGateVolume = 0.1;

/// How long each change of volume takes.
const int kSpeechRampMs = 150;

/// The finest step the take's loudness is read in.
const int kSpeechBucketMs = 50;

/// The most steps the loudness is read in, however long the take.
const int kSpeechMaxBuckets = 12000;

/// A gap in talking shorter than this is a pause between words, not silence.
const int kSpeechBridgeMs = 400;

/// Louder for less than this is a click or a knock, not talking.
const int kSpeechMinMs = 120;

/// Talking is let in this much before it is heard — a first sound is quieter
/// than what follows — and held this much after.
const int kSpeechLeadMs = 80;
const int kSpeechTailMs = 200;

/// Talking must stand this far above the rest of the take, in decibels, to be
/// told apart from it at all.
const double kSpeechMinContrastDb = 6;

/// A stretch of the take where you were talking, in the recording's time.
@immutable
class ReactionSpeech {
  const ReactionSpeech(this.startMs, this.endMs);

  final int startMs;
  final int endMs;

  List<int> toJson() => [startMs, endMs];

  static ReactionSpeech? fromJson(Object? raw) {
    if (raw is! List || raw.length != 2) return null;
    final start = raw[0];
    final end = raw[1];
    if (start is! num || end is! num || end <= start) return null;
    return ReactionSpeech(start.toInt(), end.toInt());
  }

  @override
  bool operator ==(Object other) => other is ReactionSpeech && other.startMs == startMs && other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);

  @override
  String toString() => 'ReactionSpeech($startMs..$endMs)';
}

/// Where you talked, from a take's loudness: [peaks], one per [bucketMs] of
/// the take, 0..1.
///
/// Out loud the microphone hears the video the whole time, so talking is what
/// stands **above** the rest: the take's quiet level (its 20th percentile)
/// against its loud one (its 95th), talking anything past halfway between.
/// Pauses between words are bridged, clicks dropped, and each stretch padded
/// so the first and last sounds are not cut.
///
/// **Null when talking cannot be told apart** — no sound read, or a take with
/// nothing standing out (nobody talked, or you talked the whole time). Then
/// the sound is left as it was recorded rather than guessed at: a wrong guess
/// would silence your voice.
List<ReactionSpeech>? speechSpans(List<double> peaks, {required double bucketMs}) {
  if (peaks.isEmpty || !(bucketMs > 0)) return null;
  if (!peaks.any((p) => p > 0)) return null;
  final levels = [for (final p in peaks) 20 * math.log(math.max(p, 1e-4)) / math.ln10];
  final sorted = [...levels]..sort();
  double at(double share) => sorted[((sorted.length - 1) * share).floor()];
  final quiet = at(0.2);
  final loud = at(0.95);
  if (loud - quiet < kSpeechMinContrastDb) return null;
  final threshold = quiet + (loud - quiet) / 2;

  // Runs of loud buckets, in milliseconds.
  final runs = <(double, double)>[];
  for (var i = 0; i < levels.length; i++) {
    if (levels[i] < threshold) continue;
    final start = i * bucketMs;
    final end = (i + 1) * bucketMs;
    if (runs.isNotEmpty && start - runs.last.$2 < kSpeechBridgeMs) {
      runs[runs.length - 1] = (runs.last.$1, end);
    } else {
      runs.add((start, end));
    }
  }

  final totalMs = levels.length * bucketMs;
  final spans = <ReactionSpeech>[];
  for (final run in runs) {
    if (run.$2 - run.$1 < kSpeechMinMs) continue;
    final start = math.max(0.0, run.$1 - kSpeechLeadMs).round();
    final end = math.min(totalMs, run.$2 + kSpeechTailMs).round();
    if (spans.isNotEmpty && start <= spans.last.endMs) {
      spans[spans.length - 1] = ReactionSpeech(spans.last.startMs, math.max(end, spans.last.endMs));
    } else {
      spans.add(ReactionSpeech(start, end));
    }
  }
  return spans.isEmpty ? null : spans;
}

/// A volume through [fromMs]..[toMs] of the recording: [inside] while you
/// talk, [outside] otherwise, moving between the two over [rampMs] at each
/// edge. As (progress through the stretch, value) points, exact for that
/// piecewise-straight shape — or empty when it never leaves [outside], so a
/// stretch with no talking carries no curve at all.
List<(double, double)> speechEnvelope(
  List<ReactionSpeech> speech, {
  required int fromMs,
  required int toMs,
  required double inside,
  required double outside,
  int rampMs = kSpeechRampMs,
}) {
  if (toMs <= fromMs) return const [];
  double valueAt(num t) {
    var value = outside;
    for (final s in speech) {
      double share;
      if (t >= s.startMs && t <= s.endMs) {
        share = 1;
      } else if (t < s.startMs && t >= s.startMs - rampMs) {
        share = (t - (s.startMs - rampMs)) / rampMs;
      } else if (t > s.endMs && t <= s.endMs + rampMs) {
        share = 1 - (t - s.endMs) / rampMs;
      } else {
        continue;
      }
      final candidate = outside + (inside - outside) * share;
      // Where two edges meet, the one further toward [inside] wins.
      if ((candidate - outside).abs() > (value - outside).abs()) value = candidate;
    }
    return value;
  }

  final times = <int>{fromMs, toMs};
  for (final s in speech) {
    for (final t in [s.startMs - rampMs, s.startMs, s.endMs, s.endMs + rampMs]) {
      if (t > fromMs && t < toMs) times.add(t);
    }
  }
  final sorted = times.toList()..sort();
  final span = (toMs - fromMs).toDouble();
  final points = [for (final t in sorted) ((t - fromMs) / span, valueAt(t))];
  if (points.every((p) => p.$2 == outside)) return const [];

  // A point between two of the same value says nothing.
  final kept = <(double, double)>[];
  for (var i = 0; i < points.length; i++) {
    final middle = i > 0 &&
        i < points.length - 1 &&
        points[i - 1].$2 == points[i].$2 &&
        points[i + 1].$2 == points[i].$2;
    if (!middle) kept.add(points[i]);
  }
  return kept;
}
