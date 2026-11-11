import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/speech/speech_request.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

TextOverlayModel text(
  String id,
  String words, {
  double start = 0,
  String? captionSetId,
}) =>
    TextOverlayModel(
      id: id,
      text: words,
      startTime: Duration(microseconds: (start * 1e6).round()),
      endTime: Duration(microseconds: ((start + 3) * 1e6).round()),
      captionSetId: captionSetId,
    );

List<(String, String, double)> targetsOf(SpeechPlan plan) => [
      for (final t in (plan as SpeechReady).targets)
        (t.textId, t.text, t.startSeconds),
    ];

void main() {
  test('counts code points of the trimmed text, as the server does', () {
    // "héllo 👍🏽": the thumb and its skin tone are two.
    expect(speechCharacters(' héllo \u{1F44D}\u{1F3FD} '), 8);
    // An accent written as its own mark is a code point of its own.
    expect(speechCharacters('é'), 2);
    expect(speechCharacters('  \n\t '), 0);
  });

  test('one text: the selected one, trimmed, at its start', () {
    final plan = planSpeech(
      texts: [text('a', 'First', start: 1), text('b', '  Hello there \n', start: 4.25)],
      selectedId: 'b',
      applyToAll: false,
    );

    expect(targetsOf(plan), [('b', 'Hello there', 4.25)]);
    expect((plan as SpeechReady).characters, 11);
    expect(speechPlanMessage(plan), '');
  });

  test('a caption is voiced on its own from its own menu', () {
    final plan = planSpeech(
      texts: [text('c', 'spoken words', start: 2, captionSetId: 's')],
      selectedId: 'c',
      applyToAll: false,
    );

    expect(targetsOf(plan), [('c', 'spoken words', 2.0)]);
  });

  test('an empty selected text is nothing to voice', () {
    for (final words in ['', '   ', '\n\t']) {
      expect(
        planSpeech(
          texts: [text('a', words)],
          selectedId: 'a',
          applyToAll: false,
        ),
        isA<SpeechNothing>(),
      );
    }
    expect(
      planSpeech(texts: [text('a', 'Hi')], selectedId: 'gone', applyToAll: false),
      isA<SpeechNothing>(),
    );
  });

  test(
      'Apply to all voices plain texts in timeline order, skipping empty ones '
      'and captions', () {
    final plan = planSpeech(
      texts: [
        text('late', 'Third', start: 9),
        text('cap', 'a caption', start: 0.5, captionSetId: 's'),
        text('early', ' First ', start: 1),
        text('blank', '   ', start: 2),
        text('tie', 'Second', start: 5),
        text('tie2', 'Also second', start: 5),
      ],
      selectedId: 'early',
      applyToAll: true,
    );

    expect(targetsOf(plan), [
      ('early', 'First', 1.0),
      ('tie', 'Second', 5.0),
      ('tie2', 'Also second', 5.0),
      ('late', 'Third', 9.0),
    ]);
    expect((plan as SpeechReady).characters, 5 + 6 + 11 + 5);
  });

  test('Apply to all from a caption still skips captions', () {
    final plan = planSpeech(
      texts: [
        text('cap', 'a caption', start: 0, captionSetId: 's'),
        text('cap2', 'another', start: 1, captionSetId: 's'),
        text('plain', 'Plain words', start: 3),
      ],
      selectedId: 'cap',
      applyToAll: true,
    );
    expect(targetsOf(plan), [('plain', 'Plain words', 3.0)]);

    expect(
      planSpeech(
        texts: [text('cap', 'a caption', captionSetId: 's')],
        selectedId: 'cap',
        applyToAll: true,
      ),
      isA<SpeechNothing>(),
    );
  });

  test('a text over 2,000 characters is refused by its id', () {
    final atLimit = 'a' * kSpeechMaxItemCharacters;
    expect(
      planSpeech(texts: [text('a', atLimit)], selectedId: 'a', applyToAll: false),
      isA<SpeechReady>(),
    );

    final over = planSpeech(
      texts: [text('a', '$atLimit!')],
      selectedId: 'a',
      applyToAll: false,
    );
    expect(over, isA<SpeechTooLong>().having((p) => p.textId, 'textId', 'a'));
    expect(
      speechPlanMessage(over),
      'That text is too long for one voice. Split it into shorter texts.',
    );

    final all = planSpeech(
      texts: [text('ok', 'Fine', start: 0), text('long', '$atLimit!', start: 4)],
      selectedId: 'ok',
      applyToAll: true,
    );
    expect(all, isA<SpeechTooLong>().having((p) => p.textId, 'textId', 'long'));
  });

  test('past 100 texts or 20,000 characters, says how many fit', () {
    final many = planSpeech(
      texts: [
        for (var i = 0; i <= kSpeechMaxItems; i++) text('t$i', 'Line $i', start: i * 1.0),
      ],
      selectedId: 't0',
      applyToAll: true,
    );
    expect(many, isA<SpeechTooMuch>().having((p) => p.fitting, 'fitting', 100));
    expect(
      speechPlanMessage(many),
      'Too much for one go. Apply to all can voice 100 of these texts at once.',
    );

    final full = 'b' * kSpeechMaxItemCharacters;
    final long = planSpeech(
      texts: [for (var i = 0; i < 11; i++) text('t$i', full, start: i * 1.0)],
      selectedId: 't0',
      applyToAll: true,
    );
    expect(long, isA<SpeechTooMuch>().having((p) => p.fitting, 'fitting', 10));

    final exactly = planSpeech(
      texts: [for (var i = 0; i < 10; i++) text('t$i', full, start: i * 1.0)],
      selectedId: 't0',
      applyToAll: true,
    );
    expect((exactly as SpeechReady).characters, kSpeechMaxRequestCharacters);
  });
}
