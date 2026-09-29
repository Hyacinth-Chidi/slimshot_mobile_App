import 'dart:math' as math;
import 'dart:ui';

import '../../models/text_overlay_model.dart';
import '../animation/animatable_double.dart';
import '../animation/overlay_keyframes.dart';
import '../text_overlay_geometry.dart';
import 'caption_grouping.dart';
import 'caption_retime.dart';
import 'caption_settings.dart';
import 'caption_transcript.dart';
import 'caption_word.dart';

/// What can be done to a caption once it is on the timeline. Pure: each takes
/// captions and returns captions, knowing nothing of the playhead or of undo.
///
/// One rule runs through all of it: **a word stays on the instant it was
/// spoken.** Word times are stored relative to their caption's start, so
/// anything that moves that start has to move them back by as much.

/// [caption]'s words, or — for a caption that carries none — its text's words
/// sharing its span.
List<CaptionWord> captionWordsOf(TextOverlayModel caption) =>
    caption.captionWords ??
    retimeCaptionWords(
      oldText: '',
      oldWords: const [],
      newText: caption.text,
      span: caption.endTime - caption.startTime,
    );

Duration _atLeastZero(Duration d) => d.isNegative ? Duration.zero : d;

List<CaptionWord> _shifted(
  List<CaptionWord> words, {
  int textBy = 0,
  Duration timeBy = Duration.zero,
}) =>
    [
      for (final w in words)
        CaptionWord(
          textStart: w.textStart + textBy,
          textEnd: w.textEnd + textBy,
          start: _atLeastZero(w.start + timeBy),
          end: _atLeastZero(w.end + timeBy),
        ),
    ];

/// [caption] cut in two at the word boundary nearest [cursor] (a UTF-16
/// offset into its text), or null where there is nothing to cut: a cursor at
/// either end of the text, or a caption of one word.
///
/// The left half keeps the caption's id; the right takes [rightId] and, like
/// any caption, shows [kCaptionLeadSeconds] before its first word.
({TextOverlayModel left, TextOverlayModel right})? splitCaption(
  TextOverlayModel caption,
  int cursor, {
  required String rightId,
}) {
  final words = captionWordsOf(caption);
  if (words.length < 2) return null;
  if (cursor <= words.first.textStart || cursor >= words.last.textEnd) {
    return null;
  }

  var cut = 1;
  for (var k = 2; k < words.length; k++) {
    if ((words[k].textStart - cursor).abs() <
        (words[cut].textStart - cursor).abs()) {
      cut = k;
    }
  }

  final lead = Duration(
    milliseconds: (kCaptionLeadSeconds * 1000).round(),
  );
  final span = caption.endTime - caption.startTime;
  // Inside the caption, and leaving the left half a length.
  var offset = words[cut].start - lead;
  if (offset < const Duration(milliseconds: 1)) {
    offset = const Duration(milliseconds: 1);
  }
  if (offset >= span) return null;

  final textFrom = words[cut].textStart;
  return (
    left: caption.copyWith(
      text: caption.text.substring(0, words[cut - 1].textEnd),
      endTime: caption.startTime + offset,
      captionWords: words.sublist(0, cut),
    ),
    right: caption.copyWith(
      id: rightId,
      text: caption.text.substring(textFrom),
      startTime: caption.startTime + offset,
      captionWords: _shifted(
        words.sublist(cut),
        textBy: -textFrom,
        timeBy: -offset,
      ),
    ),
  );
}

/// [first] and [second] as one caption: [first]'s id, look and place, both
/// texts, from [first]'s start to [second]'s end.
TextOverlayModel mergeCaptions(TextOverlayModel first, TextOverlayModel second) {
  final head = first.text.trimRight();
  final tail = second.text.trimLeft();
  final trimmedFromTail = second.text.length - tail.length;

  final unspaced = head.isNotEmpty &&
      tail.isNotEmpty &&
      isUnspacedScript(head.runes.last) &&
      isUnspacedScript(tail.runes.first);
  final separator = head.isEmpty || tail.isEmpty || unspaced ? '' : ' ';

  return first.copyWith(
    text: '$head$separator$tail',
    endTime: second.endTime > first.endTime ? second.endTime : first.endTime,
    captionWords: [
      for (final w in captionWordsOf(first))
        if (w.textEnd <= head.length) w,
      ..._shifted(
        [
          for (final w in captionWordsOf(second))
            if (w.textStart >= trimmedFromTail) w,
        ],
        textBy: head.length + separator.length - trimmedFromTail,
        timeBy: second.startTime - first.startTime,
      ),
    ],
  );
}

/// [caption] starting at [newStart], its end where it was, **its words on the
/// instants they were spoken** — what trimming a caption's left edge does. A
/// word the new start has passed begins with the caption, never before it.
TextOverlayModel shiftCaptionStart(TextOverlayModel caption, Duration newStart) {
  final words = caption.captionWords;
  return caption.copyWith(
    startTime: newStart,
    captionWords: words == null
        ? null
        : _shifted(words, timeBy: caption.startTime - newStart),
  );
}

/// Every word of [captions], in the order spoken, as the transcript gave
/// them: text, timeline instants, and the separator written before each.
List<SpacedWord> captionSpacedWords(List<TextOverlayModel> captions) {
  final ordered = [...captions]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  final spaced = <SpacedWord>[];
  String? previous;

  for (final caption in ordered) {
    final words = captionWordsOf(caption);
    final origin = caption.startTime.inMicroseconds / 1e6;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w.textStart < 0 ||
          w.textEnd > caption.text.length ||
          w.textStart >= w.textEnd) {
        continue;
      }
      final text = caption.text.substring(w.textStart, w.textEnd);
      final String separator;
      if (previous == null) {
        separator = '';
      } else if (i == 0) {
        separator = isUnspacedScript(previous.runes.last) &&
                isUnspacedScript(text.runes.first)
            ? ''
            : ' ';
      } else {
        final between = caption.text.substring(
          math.min(words[i - 1].textEnd, w.textStart),
          w.textStart,
        );
        separator = between.trim().length < between.length ? ' ' : '';
      }
      spaced.add(
        SpacedWord(
          separator,
          TranscriptWord(
            text: text,
            start: origin + w.start.inMicroseconds / 1e6,
            end: origin + w.end.inMicroseconds / 1e6,
          ),
        ),
      );
      previous = text;
    }
  }
  return spaced;
}

/// The set [captions] cut again to [length] — every word, hand fixes
/// included, regrouped. Nothing runs past where the set ended.
List<CaptionDraft> recutCaptionDrafts(
  List<TextOverlayModel> captions,
  CaptionLength length,
) {
  if (captions.isEmpty) return const [];
  final end = captions
      .map((c) => c.endTime)
      .reduce((a, b) => a > b ? a : b);
  return groupCaptionWords(
    captionSpacedWords(captions),
    length,
    endLimitSeconds: end.inMicroseconds / 1e6,
  );
}

/// [other] after the change that took the edited caption from [before] to
/// [after] — both as shown at the playhead.
///
/// A caption set moves as one: a caption that sits somewhere else each second
/// reads as a fault. The change is applied to [other]'s **whole path**, its
/// base values and every keyframe value, so a keyframed caption keeps its
/// motion and takes the move.
OverlayMotion followCaptionMotion(
  OverlayMotion other, {
  required OverlayMotion before,
  required OverlayMotion after,
}) {
  final by = after.position - before.position;
  final ratio = before.scale == 0 ? 1.0 : after.scale / before.scale;
  final turn = after.rotation - before.rotation;
  final fade = after.opacity - before.opacity;
  if (by == Offset.zero && ratio == 1 && turn == 0 && fade == 0) return other;

  final params = other.params;
  AnimatableDouble map(OverlayProperty p, double Function(double) f) =>
      mapAnimatable(params[p]!, f);
  return OverlayMotion.fromParams({
    OverlayProperty.x: map(OverlayProperty.x, (v) => v + by.dx),
    OverlayProperty.y: map(OverlayProperty.y, (v) => v + by.dy),
    OverlayProperty.scale: map(
      OverlayProperty.scale,
      (v) => (v * ratio).clamp(kMinTextScale, kMaxTextScale).toDouble(),
    ),
    OverlayProperty.rotation: map(OverlayProperty.rotation, (v) => v + turn),
    OverlayProperty.opacity: map(
      OverlayProperty.opacity,
      (v) => (v + fade).clamp(0.0, 1.0).toDouble(),
    ),
  });
}
