import 'dart:async';

import '../models/video_editor_state.dart';

/// What the export says when it went ahead without its fonts.
const String kFontsNotLoadedWarning =
    'Some fonts could not be loaded. Text may look different in the file.';

/// How long an export waits for fonts still downloading.
const Duration kExportFontWait = Duration(seconds: 5);

/// Waits for [ready], and answers whether the fonts loaded — **never throws,
/// never waits past [limit]**.
///
/// A font is not a reason an export fails. `GoogleFonts.pendingFonts()` is
/// `Future.wait` over a set a *failed* download is never removed from, so
/// after one failed font — the Font tab opened offline is enough — it throws
/// on every call until the app restarts; and a download has no timeout of its
/// own. Awaited bare, that failed every export for the rest of the session,
/// text or no text.
Future<bool> awaitExportFonts(
  Future<void> Function() ready, {
  Duration limit = kExportFontWait,
}) async {
  try {
    await ready().timeout(limit);
    return true;
  } catch (_) {
    return false;
  }
}

/// The warning an export owes the user, or null when it owes none.
///
/// Only a project that draws text can look different for a missing font, and
/// the font that failed may be one a sheet merely listed.
String? exportFontWarning(
  VideoEditorState state, {
  required bool fontsLoaded,
}) {
  if (fontsLoaded) return null;
  final drawsText = state.textOverlays.any((t) => t.text.isNotEmpty);
  return drawsText ? kFontsNotLoadedWarning : null;
}
