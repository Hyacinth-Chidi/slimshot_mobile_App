import 'package:http/http.dart' as http;

import '../../../core/services/slimshot_api.dart';
import '../models/account_models.dart';

/// The account endpoints, one method each — requests and answers, no UI and
/// no state. `slimshot_server/docs/app-credits-api.md` is the contract.
class AccountService {
  AccountService(this._api);

  final SlimshotApi _api;

  Future<SignInResult> signInWithGoogle(String idToken) async =>
      SignInResult.fromJson(
        await _api.sendWithDevice('/auth/google', {'idToken': idToken}),
      );

  Future<EmailCodeSent> startEmail(String email) async =>
      EmailCodeSent.fromJson(
        await _api.sendWithDevice('/auth/email/start', {'email': email}),
      );

  Future<SignInResult> verifyEmail(String email, String code) async =>
      SignInResult.fromJson(
        await _api.sendWithDevice(
          '/auth/email/verify',
          {'email': email, 'code': code},
        ),
      );

  Future<AccountUser> me() async => AccountUser.fromJson(
        await _api.send(() => http.Request('GET', _api.uri('/me'))),
      );

  Future<UsernameAvailability> usernameAvailability(String name) async =>
      UsernameAvailability.fromJson(
        await _api.send(
          () => http.Request(
            'GET',
            _api.uri('/usernames/${Uri.encodeComponent(name)}/availability'),
          ),
        ),
      );

  Future<AccountUser> changeUsername(String name) async =>
      AccountUser.fromJson(
        await _api.send(
          () => _api.jsonRequest('PATCH', '/me/username', {'username': name}),
        ),
      );

  Future<ClaimResult> claim({
    required String username,
    String? referralCode,
  }) async =>
      ClaimResult.fromJson(
        await _api.send(
          () => _api.jsonRequest('POST', '/me/claim', {
            'username': username,
            if (referralCode != null) 'referralCode': referralCode,
          }),
        ),
      );

  Future<void> logout(String refreshToken) async {
    await _api.sendPublic(
      () => _api.jsonRequest(
        'POST',
        '/auth/logout',
        {'refreshToken': refreshToken},
      ),
    );
  }

  /// The server wants the confirmation in the body; the app's own confirm
  /// sheet comes first.
  Future<void> deleteAccount() async {
    await _api.send(
      () => _api.jsonRequest('DELETE', '/me', {'confirm': 'DELETE'}),
    );
  }
}
