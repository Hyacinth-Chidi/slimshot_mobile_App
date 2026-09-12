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
    // Per-glyph on both ends: a whole-box out-animation loses nothing on the
    // flat path, so it would correctly stay silent and prove nothing here.
    expect(
      textFallbackWarning(
        textWith(outAnimation: 'untyping'),
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

  // `colour_fill` and `colour_cycle_loop` resolve and time correctly but no
  // renderer draws `fillProgress` on either side, so the glyph path and the
  // flat path show the same picture for them. Nothing was lost, and warning
  // would apologise for an effect the user never saw.
  test('an animation nothing draws is not a degradation', () {
    expect(
      textFallbackWarning(
        textWith(inAnimation: 'colour_fill'),
        hasBackground: true,
      ),
      isNull,
    );
    expect(
      textFallbackWarning(
        textWith(loopAnimation: 'colour_cycle_loop'),
        hasBackground: true,
      ),
      isNull,
    );
  });

  // Reported from a device: a text with a background box warned, and the
  // export was identical to the preview. It was — the animation was a fade,
  // which is `isPerGlyph: false`, so the flat path animates the whole quad and
  // produces the same picture the glyph path would. Only a per-glyph animation
  // genuinely degrades into a whole-block effect.
  test('a whole-box animation loses nothing on the flat path', () {
    for (final id in ['fade_in', 'zoom_in', 'slide_up']) {
      expect(
        textFallbackWarning(textWith(inAnimation: id), hasBackground: true),
        isNull,
        reason: '$id is a whole-box animation and the flat path draws it',
      );
    }
    expect(
      textFallbackWarning(
        textWith(outAnimation: 'fade_out'),
        hasBackground: true,
      ),
      isNull,
    );
  });

  test('a per-glyph animation is what actually degrades', () {
    for (final id in ['typing', 'wave_in', 'bounce_in']) {
      expect(
        textFallbackWarning(textWith(inAnimation: id), hasBackground: true),
        isNotNull,
        reason: '$id animates character by character and the flat path cannot',
      );
    }
  });

  test('a per-glyph loop beside a whole-box in-animation still warns', () {
    expect(
      textFallbackWarning(
        textWith(inAnimation: 'fade_in', loopAnimation: 'wave_loop'),
        hasBackground: true,
      ),
      isNotNull,
    );
  });

  test('a drawable animation alongside an undrawable one still warns', () {
    // `colour_fill` draws nothing and `untyping` is per-glyph: one real
    // degradation is enough, whatever it is paired with.
    expect(
      textFallbackWarning(
        textWith(inAnimation: 'colour_fill', outAnimation: 'untyping'),
        hasBackground: true,
      ),
      isNotNull,
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
