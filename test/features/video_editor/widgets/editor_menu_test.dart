import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_editor_dialog.dart';

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

  test('a selected text has a menu of its own, registered by that id', () {
    // Selecting a text used to show the root menu — tools for making a
    // project, none for the text. The notifier now names `text_overlay`;
    // without a registered menu the toolbar would fall back to root and the
    // switch would silently change nothing.
    final menu = menuSource('_textOverlayMenu');
    expect(menu, contains("id: 'text_overlay'"));
    for (final id in ['duplicate', 'delete']) {
      expect(menu, contains("id: '$id'"), reason: 'the text menu offers $id');
    }
    expect(
      screen.readAsStringSync(),
      contains("'text_overlay': _textOverlayMenu"),
    );
  });

  test('a text cannot be split', () {
    // Built, then removed as not needed: a text is retimed by its trim
    // handles, and a second copy of the words is what Copy is for.
    expect(menuSource('_textOverlayMenu'), isNot(contains("id: 'split'")));
    expect(
      screen.readAsStringSync(),
      isNot(contains('splitTextOverlay')),
      reason: 'no handler reaches a text split',
    );
  });

  test('the text menu opens the one editor sheet, one entry per tab', () {
    // Style, Font and Animation are not new surfaces: each opens the existing
    // editor sheet on its own tab, so there is still exactly one place text
    // is styled. Every tab is reachable, and no two entries open the same one.
    final menu = menuSource('_textOverlayMenu');
    for (final id in kTextMenuSheetTools.keys) {
      expect(menu, contains("id: '$id'"), reason: '$id is declared');
    }
    expect(
      kTextMenuSheetTools.values.toSet(),
      TextEditorTool.values.toSet(),
      reason: 'every tab of the sheet has an entry',
    );
    expect(
      kTextMenuSheetTools.values.toSet(),
      hasLength(kTextMenuSheetTools.length),
      reason: 'no two entries open the same tab',
    );
  });

  test('the text menu never reuses the overlays\' Animation id', () {
    // `animation` opens `AnimationDrawer`, the photo and video overlays'
    // sheet. Reusing the id would send a text to the wrong animations — so
    // the text's entry has its own id and opens the text sheet's tab.
    expect(menuSource('_textOverlayMenu'), isNot(contains("id: 'animation'")));
  });

  test('Text opens a submenu of ways to make text', () {
    // It used to add a text straight away — deliberately, while it had one
    // entry. Templates is the second real entry, so it is a submenu now.
    expect(
      RegExp(r"EditorTool\(\s*id: 'text',[^)]*hasSubMenu: true")
          .hasMatch(menuSource('_rootMenu')),
      isTrue,
      reason: "the root 'text' tool opens its submenu",
    );
    final menu = menuSource('_textMenu');
    expect(menu, contains("id: 'text'"));
    expect(menu, contains("id: 'add_text'"));
    // Choose, then type: a new text wearing the template.
    expect(menu, contains("id: 'add_template'"));
    expect(screen.readAsStringSync(), contains("'text': _textMenu"));
  });

  test('a selected text offers Templates: type, then choose', () {
    // The text's own menu opens the editor on its Templates tab, which puts
    // a template on the words already there — and swaps it, as often as the
    // user likes. Distinct from the Text submenu's entry, which makes a new
    // text: one id each, so neither handler can catch the other's tap.
    expect(menuSource('_textOverlayMenu'), contains("id: 'text_templates'"));
    expect(kTextMenuSheetTools['text_templates'], TextEditorTool.templates);
    expect(menuSource('_textMenu'), isNot(contains("id: 'text_templates'")));
  });

  test('no handler adds a text on the Text tool itself any more', () {
    // The direct-add branch keyed on `tool.id == 'text'` would swallow the tap
    // before the submenu branch saw it, and the submenu would never open.
    expect(screen.readAsStringSync(), isNot(contains("tool.id == 'text' &&")));
  });

  test('the audio menu keeps its unbuilt Effects entry', () {
    // Genuinely unbuilt — no audio-effect code exists — so the standing rule
    // applies: keep it visible and implement later. Unlike the root entry,
    // this one does not promise something that already exists elsewhere.
    expect(menuSource('_audioMenu'), contains("id: 'effects'"));
  });
}
