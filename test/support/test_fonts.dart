/// The font family for tests that measure or rasterise text.
///
/// Montserrat Bold is bundled with the app (the caption and new-text default),
/// so text lays out against a real `.ttf`'s glyph metrics, with nothing to
/// download. A server font would draw in the System face until downloaded,
/// which no test does. (It was Ariana Violeta until that font left the app
/// for its licence.)
///
/// Metrics still differ from whatever font a user picks, so text tests assert
/// on **relationships** — ordering, containment, proportion — never on
/// absolute pixel widths.
const String kTestFontFamily = 'Montserrat Bold';
