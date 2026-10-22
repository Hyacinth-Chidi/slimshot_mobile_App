/// The fonts the app has without the server, and the server fonts the
/// built-in templates and caption styles name.
library;

/// The phone's own font. `Roboto` is what Android resolves to its system
/// face, and what the text model has always defaulted to (every emoji too).
const String kSystemFontName = 'Roboto';

/// Fonts bundled in the app (`pubspec.yaml`), drawn offline from the first
/// install. Every other font comes from SlimShot's server.
const List<String> kBundledFontNames = ['Montserrat Bold', 'Bebas Neue', 'Poppins'];

/// The server fonts the built-in templates and caption styles use. The owner
/// uploads each as a Regular face; until one is on the phone, its text draws
/// in the System font.
const List<String> kServerTemplateFontNames = [
  'Abril Fatface',
  'Inter',
  'Montserrat',
  'Nunito',
  'Oswald',
  'Permanent Marker',
  'Playfair Display',
  'Press Start 2P',
  'Righteous',
  'Sacramento',
];

/// Whether [name] needs no download: System or a bundled font, in any case.
bool isLocalFontName(String name) {
  final wanted = name.trim().toLowerCase();
  if (wanted == kSystemFontName.toLowerCase()) return true;
  return kBundledFontNames.any((bundled) => bundled.toLowerCase() == wanted);
}
