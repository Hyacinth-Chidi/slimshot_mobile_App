import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/toolbar_visibility.dart';

/// Which declared tools the toolbar shows.
///
/// Device-reported: the video overlay's Volume never appeared. It was
/// declared, and `editor_menu_test.dart` — which reads the declarations —
/// was green; a filter inside the screen hid Volume whenever a project had
/// more than one clip and none was selected, which selecting an overlay
/// always arranges. The same filter hid the video overlay's Animation
/// outright.
void main() {
  bool visible(
    String id, {
    bool isSplitEnabled = true,
    bool canDeleteSegment = true,
    bool isClipSelected = false,
    int clipCount = 3,
    bool text = false,
    bool image = false,
    bool video = false,
  }) =>
      isToolbarToolVisible(
        id,
        isSplitEnabled: isSplitEnabled,
        canDeleteSegment: canDeleteSegment,
        isClipSelected: isClipSelected,
        clipCount: clipCount,
        hasTextSelected: text,
        hasImageSelected: image,
        hasVideoOverlaySelected: video,
      );

  /// The tool ids a `const EditorMenu` declares, without the menu's own id.
  List<String> declaredTools(String varName) {
    final text =
        File('lib/screens/video_editor_screen.dart').readAsStringSync();
    final start = text.indexOf('const EditorMenu $varName');
    expect(start, isNot(-1), reason: '$varName should exist');
    final body = text.substring(start, text.indexOf('\n);', start));
    final ids = RegExp(r"id: '(\w+)'")
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toList();
    return ids.skip(1).toList();
  }

  test('a selected video overlay offers Volume, however many clips there are',
      () {
    expect(visible('volume', video: true, clipCount: 3), isTrue);
    expect(visible('volume', video: true, clipCount: 1), isTrue);
  });

  test('a selected video overlay offers Animation', () {
    expect(visible('animation', video: true), isTrue);
  });

  test('every tool an overlay menu declares is shown for that overlay', () {
    // The declaration is the promise; nothing may withhold an entry from the
    // very selection its menu exists for. Split is left to its own gate,
    // which asks where the playhead is.
    for (final (menu, kind) in [
      ('_videoOverlayMenu', 'video'),
      ('_imageOverlayMenu', 'image'),
      ('_textOverlayMenu', 'text'),
    ]) {
      for (final id in declaredTools(menu)) {
        expect(
          visible(
            id,
            canDeleteSegment: false,
            text: kind == 'text',
            image: kind == 'image',
            video: kind == 'video',
          ),
          isTrue,
          reason: '$menu declares $id',
        );
      }
    }
  });

  group('the clip menu, reached with no clip selected', () {
    test('hides Volume and Speed when there are several clips to mean', () {
      // No target: with several clips and none selected, a slider would not
      // know which clip it moved.
      expect(visible('volume', clipCount: 3), isFalse);
      expect(visible('speed', clipCount: 3), isFalse);
    });

    test('shows them for a lone clip, the only one they can mean', () {
      expect(visible('volume', clipCount: 1), isTrue);
      expect(visible('speed', clipCount: 1), isTrue);
    });

    test('shows them once a clip is selected', () {
      expect(visible('volume', isClipSelected: true), isTrue);
      expect(visible('speed', isClipSelected: true), isTrue);
    });
  });

  test('Split follows its gate and Delete its own rule', () {
    expect(visible('split', isSplitEnabled: false), isFalse);
    expect(visible('delete', canDeleteSegment: false), isFalse);
    expect(visible('delete', canDeleteSegment: false, text: true), isTrue);
  });

  test('the screen filters through this function, not a copy of it', () {
    final screen =
        File('lib/screens/video_editor_screen.dart').readAsStringSync();
    expect(screen, contains('isToolbarToolVisible('));
    expect(screen, isNot(contains("tool.id == 'volume' || tool.id == 'speed'")));
  });
}
