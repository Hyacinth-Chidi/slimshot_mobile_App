import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google's consent step (UMP), then the ads SDK — once per launch, and only
/// once something that shows ads is on screen: a user who never meets an ad
/// never starts the SDK. Shared by every ad in the app: credit ads, and the
/// placements `AdService` switches on.
///
/// In the EEA, the UK and Switzerland ads need consent to serve; elsewhere
/// Google answers that none is required.
///
/// **The last answer is used first** (Google's own pattern): where an
/// earlier check already allowed ads, the SDK starts at once and the check
/// is refreshed alongside, so a weak connection does not hold every ad
/// behind a network round trip. Only with no answer yet is it waited for.
class AdsSdk {
  AdsSdk._();

  static const Duration consentTimeout = Duration(seconds: 10);

  static const String _tag = 'SlimshotAds';

  /// Null once ads may be requested, otherwise why not. Cleared on a
  /// failure so the next ask tries again.
  static Future<String?>? _sdk;

  /// Starts the SDK after the consent step: null once ads may be
  /// requested, otherwise why not. Never throws.
  static Future<String?> start() => _sdk ??= _consentThenStart();

  /// Whether the consent step has let the SDK start. No ad may be asked
  /// for before it: in the EEA, the UK and Switzerland that would be an ad
  /// requested without consent.
  static bool get started => _started;
  static bool _started = false;

  static Future<String?> _consentThenStart() async {
    try {
      final consent = ConsentInformation.instance;
      if (await consent.canRequestAds()) {
        unawaited(_checkConsent());
      } else {
        final failed = await _checkConsent();
        if (!await consent.canRequestAds()) {
          _sdk = null;
          return failed ?? 'consent not given';
        }
      }
      await MobileAds.instance.initialize();
      _started = true;
      return null;
    } catch (e) {
      _sdk = null;
      return 'ads SDK: $e';
    }
  }

  /// Asks Google whether a consent form is needed and shows it if so.
  /// Null when the check answered; otherwise why it did not.
  static Future<String?> _checkConsent() async {
    try {
      final updated = Completer<String?>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!updated.isCompleted) updated.complete(null);
        },
        (error) {
          if (!updated.isCompleted) {
            updated.complete(
                'consent check failed (${error.errorCode}: ${error.message})');
          }
        },
      );
      final failed = await updated.future.timeout(
        consentTimeout,
        onTimeout: () => 'consent check timed out',
      );
      if (failed != null) {
        debugPrint('$_tag: $failed');
        return failed;
      }
      final dismissed = Completer<void>();
      unawaited(ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!dismissed.isCompleted) dismissed.complete();
      }));
      await dismissed.future;
      return null;
    } catch (e) {
      debugPrint('$_tag: consent check: $e');
      return 'consent check: $e';
    }
  }
}
