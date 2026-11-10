import '../services/native_timeline_preview_service.dart';

/// What the editor shows for an event from the preview engine, or null for
/// nothing.
///
/// **An error is said in plain words, never in the engine's.** The engine's
/// `message` is written for whoever reads the log — a player's error name, an
/// exception class, a file's full path — and it reached people's screens word
/// for word until this (device-reported, 2026-11-10). The `code` says which
/// kind of failure it was, and that picks the line.
///
/// **A warning is not shown at all.** Every warning the preview sends is a
/// compromise of the preview's own — a transition drawn as a dissolve, an
/// overlay heard silent, a blur the GPU refused — and the owner's rule is a
/// toast only when the exported file differs. The export reports its own
/// compromises on its own screen. The screen logs these instead.
String? previewEventToast(NativeTimelinePreviewEvent event) {
  if (event.type != 'error') return null;
  return switch (event.code) {
    'missing_file' => "A clip's file is missing from this phone.",
    'playback_failed' => "This video can't play on this phone.",
    _ => "The preview couldn't load.",
  };
}
