/// The font family for tests that measure or rasterise text.
///
/// Text geometry resolves its font through `getFontStyle`, which sends most
/// families to `GoogleFonts.getFont` — a runtime download. In a test that
/// fails from an async continuation nothing awaits, so the error cannot be
/// caught at the call site and `flutter_test` charges it to whichever test
/// is running (often one that had already passed). See
/// `test/flutter_test_config.dart`.
///
/// Montserrat Bold is bundled with the app (the caption and new-text default)
/// and stays bundled, so `getFontStyle` resolves it as a plain
/// `TextStyle(fontFamily:)` against a real `.ttf` — layout happens against
/// actual glyph metrics, with no network and no async load. (It was Ariana
/// Violeta until that font left the app for its licence.)
///
/// Metrics still differ from whatever font a user picks, so text tests assert
/// on **relationships** — ordering, containment, proportion — never on
/// absolute pixel widths.
const String kTestFontFamily = 'Montserrat Bold';
