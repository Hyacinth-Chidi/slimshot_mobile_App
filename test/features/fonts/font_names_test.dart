import 'dart:io';

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

  test('every bundled font is a family the app ships, and its file is there', () {
    // A name listed here and missing from pubspec.yaml draws in System on
    // every phone — with nothing failing anywhere to say so.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final name in kBundledFontNames) {
      expect(pubspec, contains('- family: $name\n'), reason: name);
    }
    final assets = RegExp(r'- asset: (assets/fonts/\S+)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!);
    for (final asset in assets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
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
