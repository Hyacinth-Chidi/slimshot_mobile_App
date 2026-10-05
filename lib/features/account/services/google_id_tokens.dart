import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/services/slimshot_api.dart';
import '../logic/account_copy.dart';

/// Where a Google ID token for our server comes from. An interface so the
/// sign-in flow is tested without a phone.
abstract class GoogleIdTokens {
  /// Whether this build can offer Google at all.
  bool get isAvailable;

  /// An ID token for our server, or null when the user closed the picker.
  Future<String?> requestIdToken();

  /// Forgets the chosen Google account, so the next sign-in shows the picker
  /// again rather than signing straight back in.
  Future<void> signOut();
}

/// Google's account picker — on Android, Credential Manager: the accounts
/// already on the phone, no browser.
class PluginGoogleIdTokens implements GoogleIdTokens {
  /// The **Web** OAuth client ID the server checks the token's audience
  /// against: `--dart-define=SLIMSHOT_GOOGLE_CLIENT_ID=…`. Not the Android
  /// client's — that one only vouches for the app's signature.
  /// `docs/google-sign-in-setup.md` says where it comes from.
  static const String serverClientId =
      String.fromEnvironment('SLIMSHOT_GOOGLE_CLIENT_ID');

  /// `initialize` may be called once per app run.
  static Future<void>? _initialised;

  @override
  bool get isAvailable => serverClientId.isNotEmpty;

  Future<void> _initialise() => _initialised ??=
      GoogleSignIn.instance.initialize(serverClientId: serverClientId);

  @override
  Future<String?> requestIdToken() async {
    await _initialise();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const SlimshotApiException(kGoogleSignInFailed, 'No ID token.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw SlimshotApiException(
        kGoogleSignInFailed,
        e.description ?? e.code.name,
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!isAvailable) return;
    try {
      await _initialise();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Leaving Google is a courtesy; our own session has already ended.
    }
  }
}
