import 'package:flutter/widgets.dart';

/// The one door every auto-caption run passes before any audio is rendered.
///
/// **It always opens today.** Auto captions will become signed-in and
/// credit-based: this is where the Google / email sign-in sheet and the
/// balance check go, and nothing else changes when they do.
class CaptionAccess {
  const CaptionAccess._();

  static Future<bool> ensureAllowed(BuildContext context) async => true;
}
