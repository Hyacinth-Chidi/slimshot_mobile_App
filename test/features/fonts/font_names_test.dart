import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/fonts/font_names.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_preset_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/text_template_catalog.dart';

void main() {
  test('System and the bundled fonts are local, in any case', () {
    expect(isLocalFontName(kSystemFontName), isTrue);
    for (final name in kBundledFontNames) {
      expect(isLocalFontName(name), isTrue, reason: name);
      expect(isLocalFontName(name.toUpperCase()), isTrue, reason: name);
    }
    expect(isLocalFontName('Playfair Display'), isFalse);
  });

  test('every template and caption font is local or a server template font', () {
    final names = {
      for (final t in kTextTemplates) t.fontFamily,
      for (final p in kCaptionPresets) p.look.fontFamily,
    };
    for (final name in names) {
      expect(
        isLocalFontName(name) || kServerTemplateFontNames.contains(name),
        isTrue,
        reason: '$name: bundle it, or add it to the fonts the owner uploads',
      );
    }
  });
}
