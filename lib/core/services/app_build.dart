import 'package:flutter/services.dart';

/// The channel `AppBuildChannel.kt` answers on.
const MethodChannel kAppBuildChannel = MethodChannel('slimshot_ai/app_build');

/// This install's build, as Android reports it: the version code and when
/// this APK was installed or last updated — `"2-1793141004000"`. The second
/// moves with every install, a store update and a debug rebuild alike, so
/// anything kept against it is never mistaken for another build's.
///
/// Null where the platform cannot say (a test, a failed lookup): then
/// nothing should be kept against a build, since none is known.
Future<String?> appBuildStamp() async {
  try {
    return await kAppBuildChannel.invokeMethod<String>('buildStamp');
  } catch (_) {
    return null;
  }
}
