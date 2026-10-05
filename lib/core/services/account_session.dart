import 'dart:async';

import 'token_vault.dart';

/// A signed-in session: the short-lived access token every signed-in request
/// carries, and the refresh token that replaces it.
class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// The signed-in session on this phone, shared by every server client.
///
/// **Refreshes run one at a time**, and they have to: the server lets a
/// refresh token work once, and a second use looks like a stolen token and
/// ends the whole session. Two requests refused together therefore take
/// turns — the first exchanges the refresh token, and the second, finding the
/// access token it was refused with already replaced, simply uses the new one.
///
/// Everything personal the app keeps — the tokens and the last profile — is
/// here, so [end] is the one place that forgets it.
class AccountSession {
  AccountSession({TokenVault vault = const SecureTokenVault()}) : _vault = vault;

  static const String accessKey = 'account_access_token';
  static const String refreshKey = 'account_refresh_token';
  static const String profileKey = 'account_profile';

  final TokenVault _vault;
  final StreamController<void> _ended = StreamController<void>.broadcast();
  Future<SessionTokens?> _turns = Future<SessionTokens?>.value();

  /// Fires whenever the session ends: signed out, deleted, or refused by the
  /// server.
  Stream<void> get ended => _ended.stream;

  Future<SessionTokens?> read() async {
    final access = await _vault.read(accessKey);
    final refresh = await _vault.read(refreshKey);
    if (access == null || refresh == null) return null;
    return SessionTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> save(SessionTokens tokens) async {
    await _vault.write(accessKey, tokens.accessToken);
    await _vault.write(refreshKey, tokens.refreshToken);
  }

  /// The last `/me` the app saw, as JSON — what the home screen shows before
  /// the server has answered.
  Future<String?> readProfile() => _vault.read(profileKey);

  Future<void> saveProfile(String json) => _vault.write(profileKey, json);

  Future<void> end() async {
    await _vault.delete(accessKey);
    await _vault.delete(refreshKey);
    await _vault.delete(profileKey);
    _ended.add(null);
  }

  /// The session to retry with after a request was refused with
  /// [failedAccess].
  ///
  /// [refresh] trades a refresh token for new tokens. It answers null when
  /// the server refused the refresh token — the session is then over — and
  /// throws when the server could not be reached or did not answer, which
  /// says nothing about the session, so it is not ended for that. Returns
  /// null once there is no session.
  Future<SessionTokens?> refreshAfter(
    String failedAccess,
    Future<SessionTokens?> Function(String refreshToken) refresh,
  ) {
    final turn = _turns
        .catchError((Object _) => null)
        .then((_) => _rotate(failedAccess, refresh));
    _turns = turn;
    return turn;
  }

  Future<SessionTokens?> _rotate(
    String failedAccess,
    Future<SessionTokens?> Function(String refreshToken) refresh,
  ) async {
    final current = await read();
    if (current == null) return null;
    if (current.accessToken != failedAccess) return current;
    final fresh = await refresh(current.refreshToken);
    if (fresh == null) {
      await end();
      return null;
    }
    await save(fresh);
    return fresh;
  }
}
