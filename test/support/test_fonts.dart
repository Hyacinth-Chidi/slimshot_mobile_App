/// The font family for tests that measure or rasterise text.
///
/// Text geometry resolves its font through `getFontStyle`, which sends most
/// families to `GoogleFonts.getFont` — a runtime download. In a test that
/// fails from an async continuation nothing awaits, so the error cannot be
/// caught at the call site and `flutter_test` charges it to whichever test
/// is running (often one that had already passed). See
/// `test/flutter_test_config.dart`.
///
/// This family is in `customBundledFonts`, so `getFontStyle` takes its other
/// branch — a plain `TextStyle(fontFamily:)` against a real bundled `.ttf`.
/// Layout happens against actual glyph metrics, with no network and no async
/// load.
///
/// Metrics still differ from whatever font a user picks, so text tests assert
/// on **relationships** — ordering, containment, proportion — never on
/// absolute pixel widths.
const String kTestFontFamily = 'Ariana Violeta';
