import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/emoji_catalog.dart';

void main() {
  group('emoji catalog', () {
    test('every entry is exactly one grapheme cluster', () {
      // The renderer counts clusters, so a two-cluster entry would insert as
      // two glyphs and animate as two characters — and a half-cluster (a lone
      // surrogate, or a flag missing its second regional indicator) renders
      // as a box. This is the invariant a careless paste breaks.
      for (final group in kEmojiGroups) {
        for (final emoji in group.emoji) {
          expect(
            emoji.characters.length,
            1,
            reason: '"$emoji" in ${group.name} is not a single cluster',
          );
        }
      }
    });

    test('no entry is blank', () {
      for (final group in kEmojiGroups) {
        for (final emoji in group.emoji) {
          expect(emoji.trim(), isNotEmpty, reason: 'blank entry in ${group.name}');
        }
      }
    });

    test('no emoji repeats, within a group or across the catalog', () {
      // A duplicate is dead space in a grid the user scrolls, and usually the
      // symptom of a bad merge rather than a deliberate choice.
      final seen = <String, String>{};
      for (final group in kEmojiGroups) {
        for (final emoji in group.emoji) {
          final previous = seen[emoji];
          expect(
            previous,
            isNull,
            reason: '"$emoji" appears in both $previous and ${group.name}',
          );
          seen[emoji] = group.name;
        }
      }
    });

    test('every group has a name and something in it', () {
      expect(kEmojiGroups, isNotEmpty);
      for (final group in kEmojiGroups) {
        expect(group.name.trim(), isNotEmpty);
        expect(group.emoji, isNotEmpty, reason: '${group.name} is empty');
        // The pill shows the first entry, so an empty group would throw.
        expect(group.icon, group.emoji.first);
      }
    });

    test('kAllEmoji is every group concatenated', () {
      final expected = kEmojiGroups.fold<int>(0, (sum, g) => sum + g.emoji.length);
      expect(kAllEmoji.length, expected);
      expect(kAllEmoji.first, kEmojiGroups.first.emoji.first);
    });
  });
}
