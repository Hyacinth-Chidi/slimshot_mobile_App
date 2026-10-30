import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app's two legal pages, on the SlimShot website. Settings links both,
/// and signing in — which makes the account — says it agrees to both.
const String kPrivacyPolicyUrl = 'https://slimshotai.vercel.app/privacy';
const String kTermsOfServiceUrl = 'https://slimshotai.vercel.app/terms';

/// Opens [url] outside the app; false when nothing could open it.
typedef LegalLinkOpener = Future<bool> Function(Uri url);

/// The browser, by default; a test records what would have opened.
final legalLinkOpenerProvider = Provider<LegalLinkOpener>(
  (ref) => (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);
