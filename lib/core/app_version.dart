/// The app's version, as pubspec.yaml's `version:` line says it: `2.0.1+3`
/// is version 2.0.1, build 3. The update check and Settings read it here.
///
/// **Change it with pubspec.yaml** — `app_version_test.dart` fails while the
/// two disagree. It was written by hand in both places and stayed at 2.0.0 (2)
/// after a bump, which would have told every 2.0.1 install to update to
/// itself once the update API named 2.0.1.
const String kAppVersion = '2.0.1';
const int kAppBuildNumber = 3;
