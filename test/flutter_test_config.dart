import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Runs once before every test file in the suite.
///
/// **Google Fonts must not reach the network in a test.** `getFontStyle`
/// resolves most fonts through `GoogleFonts.getFont`, which downloads the
/// font on first use. `main.dart` enables that for the app; tests never run
/// `main()`, and a sandboxed test has no network.
///
/// Turning fetching off makes the failure *deterministic* rather than a
/// hang — but it does not make it quiet: `google_fonts` throws from an async
/// continuation nothing awaits, so the error lands as an unhandled async
/// exception and `flutter_test` charges it to whichever test is running.
/// It cannot be caught at the call site or through `FlutterError.onError`.
///
/// So tests that measure text do not use a Google Font. They pick a family
/// from `customBundledFonts`, which `getFontStyle` resolves as a plain
/// `TextStyle(fontFamily:)` against a real bundled asset — no network, no
/// async load, and metrics that are stable across machines. Use
/// `kTestFontFamily` from `test/support/test_fonts.dart` in any test that
/// measures or rasterises text.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
