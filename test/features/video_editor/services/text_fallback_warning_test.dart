import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/native_timeline_preview_service.dart';

/// The flat-raster fallback used to be silent because the file it produced was
/// identical. It no longer is — the flat path cannot animate per character — so
/// it warns. These tests hold the one rule that keeps the warning meaningful:
/// it fires **only** when something was actually lost.
void main() {
  TextOverlayModel textWith({
    String text = 'Hello',
    String inAnimation = 'none',
    String outAnimation = 'none',
    String loopAnimation = 'none',
  }) {
    return TextOverlayModel(
      id: 'overlay-1',
      text: text,
      inAnimation: inAnimation,
      outAnimation: outAnimation,
      loopAnimation: loopAnimation,
    );
  }

  test('a static text on the flat path is not degraded and stays silent', () {
    expect(textFallbackWarning(textWith(), hasBackground: false), isNull);
    expect(textFallbackWarning(textWith(), hasBackground: true), isNull);
  });

  test('an animated text warns on either fallback cause', () {
    expect(
      textFallbackWarning(textWith(inAnimation: 'typing'), hasBackground: false),
      isNotNull,
    );
    expect(
      textFallbackWarning(textWith(inAnimation: 'typing'), hasBackground: true),
      isNotNull,
    );
  });

  test('the two causes say different things', () {
    final overflow = textFallbackWarning(
      textWith(inAnimation: 'typing'),
      hasBackground: false,
    );
    final background = textFallbackWarning(
      textWith(inAnimation: 'typing'),
      hasBackground: true,
    );
    expect(overflow, isNot(background));
    // A user can remove a background box; they cannot make an atlas smaller,
    // so the message has to name which one they are looking at.
    expect(background, contains('background'));
  });

  test('an out-only and a loop-only animation each warn', () {
    expect(
      textFallbackWarning(
        textWith(outAnimation: 'fade_out'),
        hasBackground: true,
      ),
      isNotNull,
    );
    expect(
      textFallbackWarning(
        textWith(loopAnimation: 'wave_loop'),
        hasBackground: true,
      ),
      isNotNull,
    );
  });

  // The old widget layer played no out-animation for a bare in-only id, so
  // such an overlay animates in neither path and has lost nothing. Reading the
  // raw strings instead of resolving them by slot would warn every export.
  test('a bare in-only id in the out slot is not an animation', () {
    expect(
      textFallbackWarning(
        textWith(outAnimation: 'slide_up'),
        hasBackground: true,
      ),
      isNull,
    );
  });

  test('an unknown id from an old draft does not warn', () {
    expect(
      textFallbackWarning(
        textWith(inAnimation: 'circleOpen'),
        hasBackground: true,
      ),
      isNull,
    );
  });

  test('the message names the text so the user can find it', () {
    final warning = textFallbackWarning(
      textWith(text: 'Chapter One', inAnimation: 'typing'),
      hasBackground: true,
    );
    expect(warning, contains('Chapter One'));
  });

  test('a long caption is truncated rather than filling the toast', () {
    final warning = textFallbackWarning(
      textWith(
        text: 'A very long caption that would run clean off the screen edge',
        inAnimation: 'typing',
      ),
      hasBackground: true,
    )!;
    expect(warning, contains('…'));
    expect(warning, isNot(contains('off the screen edge')));
  });
}
