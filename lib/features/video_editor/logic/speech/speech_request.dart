import '../../models/text_overlay_model.dart';

/// The server's limits as shipped (`slimshot_server/docs/app-api/text-to-speech.md`).
/// The same numbers here mean a request the app sends is never refused for
/// its size: what would be is said in the app, before anything is sent.
const int kSpeechMaxItemCharacters = 2000;
const int kSpeechMaxRequestCharacters = 20000;
const int kSpeechMaxItems = 100;

/// The characters a text is priced by: the Unicode code points of the
/// trimmed text — the server's own count, so accents and emoji agree
/// (`"héllo 👍🏽"` is 8: the thumb and its skin tone are two).
int speechCharacters(String text) => text.trim().runes.length;

/// One text to voice, as it was when Generate was tapped: the voice lands
/// at [startSeconds] even if the text moves or goes while it is made.
class SpeechTarget {
  const SpeechTarget({
    required this.textId,
    required this.text,
    required this.startSeconds,
  });

  final String textId;

  /// Trimmed: what is sent is what was counted.
  final String text;
  final double startSeconds;
}

/// What a Generate would send.
sealed class SpeechPlan {
  const SpeechPlan();
}

/// Texts to send, and the characters they are priced by.
class SpeechReady extends SpeechPlan {
  const SpeechReady(this.targets, this.characters);

  final List<SpeechTarget> targets;
  final int characters;
}

/// Nothing to voice: Generate stays off.
class SpeechNothing extends SpeechPlan {
  const SpeechNothing();
}

/// A text over [kSpeechMaxItemCharacters], named by its id.
class SpeechTooLong extends SpeechPlan {
  const SpeechTooLong(this.textId);

  final String textId;
}

/// Apply to all past a request's limits: [fitting] texts, in order, would go.
class SpeechTooMuch extends SpeechPlan {
  const SpeechTooMuch(this.fitting);

  final int fitting;
}

/// What Generate sends from the text [selectedId]: that text alone, or with
/// [applyToAll] every plain text with words in it, in timeline order.
///
/// Apply to all never voices a caption — a caption is already speech, and the
/// likely caption set in a project is Auto captions run over a voice; a
/// caption is voiced on its own, from its own menu.
SpeechPlan planSpeech({
  required List<TextOverlayModel> texts,
  required String selectedId,
  required bool applyToAll,
}) {
  final chosen = applyToAll
      ? _inTimelineOrder([
          for (final t in texts)
            if (!t.isCaption && t.text.trim().isNotEmpty) t,
        ])
      : [
          for (final t in texts)
            if (t.id == selectedId && t.text.trim().isNotEmpty) t,
        ].take(1).toList();
  if (chosen.isEmpty) return const SpeechNothing();

  for (final t in chosen) {
    if (speechCharacters(t.text) > kSpeechMaxItemCharacters) {
      return SpeechTooLong(t.id);
    }
  }

  var characters = 0;
  var fitting = 0;
  for (final t in chosen) {
    final next = characters + speechCharacters(t.text);
    if (fitting == kSpeechMaxItems || next > kSpeechMaxRequestCharacters) {
      return SpeechTooMuch(fitting);
    }
    characters = next;
    fitting++;
  }

  return SpeechReady([
    for (final t in chosen)
      SpeechTarget(
        textId: t.id,
        text: t.text.trim(),
        startSeconds: t.startTime.inMicroseconds / Duration.microsecondsPerSecond,
      ),
  ], characters);
}

/// The plain line a plan that cannot go says; empty for one that can, and
/// for nothing to voice, where Generate is simply off.
String speechPlanMessage(SpeechPlan plan) => switch (plan) {
      SpeechTooLong() =>
        'That text is too long for one voice. Split it into shorter texts.',
      SpeechTooMuch(:final fitting) =>
        'Too much for one go. Apply to all can voice $fitting of these texts at once.',
      SpeechReady() || SpeechNothing() => '',
    };

/// By start, and in list order where two start together: a stable sort.
List<TextOverlayModel> _inTimelineOrder(List<TextOverlayModel> texts) {
  final indexed = [for (var i = 0; i < texts.length; i++) (i, texts[i])];
  indexed.sort((a, b) {
    final byStart = a.$2.startTime.compareTo(b.$2.startTime);
    return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
  });
  return [for (final (_, t) in indexed) t];
}
