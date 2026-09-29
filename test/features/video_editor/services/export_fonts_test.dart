import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/services/export_fonts.dart';

/// Export waits for fonts, but a font is never a reason an export fails.
///
/// `GoogleFonts.pendingFonts()` is `Future.wait` over a set a failed download
/// is never removed from, so after one failed font it throws on every call
/// until the app restarts — and a download has no timeout of its own.
void main() {
  group('awaitExportFonts', () {
    test('fonts that load are loaded', () async {
      expect(await awaitExportFonts(() async {}), isTrue);
    });

    test('a font that failed to load is not an error', () async {
      expect(
        await awaitExportFonts(() async => throw Exception('no network')),
        isFalse,
      );
      expect(
        await awaitExportFonts(() => throw StateError('sync')),
        isFalse,
      );
    });

    test('a font that never loads is waited for only so long', () async {
      expect(
        await awaitExportFonts(
          () => Completer<void>().future,
          limit: const Duration(milliseconds: 20),
        ),
        isFalse,
      );
    });
  });

  group('exportFontWarning', () {
    final withText = VideoEditorState(
      textOverlays: [TextOverlayModel(id: 't', text: 'Hello')],
    );

    test('says so when a project with text exports without its fonts', () {
      expect(
        exportFontWarning(withText, fontsLoaded: false),
        kFontsNotLoadedWarning,
      );
    });

    test('says nothing when the fonts loaded', () {
      expect(exportFontWarning(withText, fontsLoaded: true), isNull);
    });

    test('says nothing for a project that draws no text', () {
      // The failed font may be one the Font tab merely listed; a project
      // without text has nothing that could look different.
      expect(
        exportFontWarning(const VideoEditorState(), fontsLoaded: false),
        isNull,
      );
      expect(
        exportFontWarning(
          VideoEditorState(
            textOverlays: [TextOverlayModel(id: 't', text: '')],
          ),
          fontsLoaded: false,
        ),
        isNull,
      );
    });
  });
}
