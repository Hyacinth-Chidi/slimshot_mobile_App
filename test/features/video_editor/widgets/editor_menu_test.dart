import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Which tools each menu offers.
///
/// The menus are private consts inside `video_editor_screen.dart`, so this
/// reads the declarations rather than pumping the screen — the screen needs a
/// loaded project, a native texture and a platform channel to build at all,
/// which is a great deal of scaffolding to assert a list of menu entries.
void main() {
  final screen = File('lib/screens/video_editor_screen.dart');

  /// The body of a `const EditorMenu` declaration, by its variable name.
  String menuSource(String varName) {
    final text = screen.readAsStringSync();
    final start = text.indexOf('const EditorMenu $varName');
    expect(start, isNot(-1), reason: '$varName should exist');
    final end = text.indexOf('\n);', start);
    expect(end, isNot(-1), reason: '$varName should be terminated');
    return text.substring(start, end);
  }

  test('Effects is on the clip menu only, never the root menu', () {
    // **It was on both.** The handler gates the real sheet on the clip menu —
    // an effect belongs to a clip, and the root menu has none selected — so
    // the root entry fell through to a "coming soon" placeholder for a
    // feature that is built and shipping one tap away. That is a wrong
    // signpost rather than an unfinished tool, which is why it goes despite
    // the standing rule about keeping unbuilt tools visible.
    expect(
      menuSource('_rootMenu'),
      isNot(contains("id: 'effects'")),
      reason: 'the root menu has no clip selected to apply an effect to',
    );
    expect(menuSource('_editMenu'), contains("id: 'effects'"));
  });

  test('Animate is not on the root menu, and Animation is on the overlays', () {
    // `animate` was handled by nothing — the string appeared once in the
    // codebase, the entry itself — so it fell through to a "coming soon"
    // placeholder while the real tool shipped under the id `animation`, one
    // tap away on whatever was being animated. An animation also needs a
    // target, and the root menu is the no-selection menu.
    expect(
      menuSource('_rootMenu'),
      isNot(contains("id: 'animate'")),
      reason: 'the root menu has nothing selected to animate',
    );
    expect(menuSource('_imageOverlayMenu'), contains("id: 'animation'"));
    expect(menuSource('_videoOverlayMenu'), contains("id: 'animation'"));
  });

  test('the audio menu keeps its unbuilt Effects entry', () {
    // Genuinely unbuilt — no audio-effect code exists — so the standing rule
    // applies: keep it visible and implement later. Unlike the root entry,
    // this one does not promise something that already exists elsewhere.
    expect(menuSource('_audioMenu'), contains("id: 'effects'"));
  });
}
