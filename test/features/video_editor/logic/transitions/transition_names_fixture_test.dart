import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/transitions/transition_catalog.dart';

/// The catalog and the engine's shader registry name the same transitions.
///
/// `EditorTransition.name` crosses the channel and Kotlin looks it up in
/// `TransitionShaders`; a name one side has and the other lacks is a transition
/// the sheet offers and the engine plays as a hard cut. Both sides test against
/// this one list (the Kotlin copy is under `android/app/src/test/resources/`,
/// and the two files must stay identical).
void main() {
  test('the catalog names exactly the transitions in the shared list', () {
    final json = jsonDecode(
      File('test/fixtures/transition_names.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final names = (json['transitions'] as List).cast<String>();
    expect(EditorTransition.values.map((t) => t.name).toList(), names);
  });

  test('the two copies of the list are the same file', () {
    expect(
      File('android/app/src/test/resources/transition_names.json').readAsStringSync(),
      File('test/fixtures/transition_names.json').readAsStringSync(),
    );
  });
}
