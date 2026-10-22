/// The app's own interface font, bundled in the weights the screens use
/// (400, 500, 600, 700, 800) so nothing is fetched at runtime — the app never
/// asks Google for a font. Not the editor's fonts: those are a text's own
/// (`getFontStyle`).
const String kInterfaceFontFamily = 'Plus Jakarta Sans';
