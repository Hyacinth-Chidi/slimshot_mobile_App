import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'account_session.dart';
import 'token_vault.dart';

/// A request the server refused, or one that never reached it.
class SlimshotApiException implements Exception {
  const SlimshotApiException(
    this.code, [
    this.message = '',
    this.details = const {},
  ]);

  /// The server's error code (`CAPTIONS_UNAVAILABLE`, `OTP_INVALID`, …) or
  /// one of the local codes below.
  final String code;
  final String message;

  /// The error's `details`, where the server sends them
  /// (`attemptsLeft`, `retryAfterSeconds`, …).
  final Map<String, Object?> details;

  /// No connection, a timeout, or a request cut off.
  static const String network = 'NETWORK';

  /// A body that was not the server's envelope.
  static const String badResponse = 'BAD_RESPONSE';

  /// No session, or one the server ended: the user has to sign in.
  static const String signInRequired = 'SIGN_IN_REQUIRED';

  /// A whole number from [details], or null.
  int? detailInt(String key) {
    final value = details[key];
    return value is num ? value.toInt() : null;
  }

  @override
  String toString() =>
      'SlimshotApiException($code${message.isEmpty ? '' : ': $message'})';
}

/// Where this install's device token is kept.
abstract class DeviceTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The install token, in the [TokenVault].
///
/// It used to live in `shared_preferences`; once sign-in made the install a
/// key to an account it was worth protecting. It moves the first time it is
/// read — the old copy is removed only after the new one is written, so a
/// move cut short loses nothing.
class SecureDeviceTokenStore implements DeviceTokenStore {
  const SecureDeviceTokenStore([this._vault = const SecureTokenVault()]);

  final TokenVault _vault;

  static const String vaultKey = 'slimshot_device_token';
  static const String legacyPrefsKey = 'slimshot_device_token';

  @override
  Future<String?> read() async {
    final stored = await _vault.read(vaultKey);
    if (stored != null) return stored;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyPrefsKey);
    if (legacy == null) return null;
    await _vault.write(vaultKey, legacy);
    await prefs.remove(legacyPrefsKey);
    return legacy;
  }

  @override
  Future<void> write(String token) => _vault.write(vaultKey, token);

  @override
  Future<void> clear() async {
    await _vault.delete(vaultKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyPrefsKey);
  }
}

/// The app's one client for SlimShot's own server.
///
/// Three kinds of request. **Signed in** ([send]): the access token as a
/// bearer, refreshed once when it has expired. **Sign-in** ([sendWithDevice]):
/// no bearer — the install token travels in the body, so the server can tie
/// the install to the account. **Public** ([sendPublic]): neither, for the
/// refresh and logout calls that carry their own token.
class SlimshotApi {
  SlimshotApi({
    required String baseUrl,
    required AccountSession session,
    http.Client? client,
    DeviceTokenStore tokens = const SecureDeviceTokenStore(),
  })  : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _session = session,
        _tokens = tokens;

  /// The server this build talks to: `--dart-define=SLIMSHOT_API_URL=…`.
  /// Empty when the build carries none.
  static const String configuredBaseUrl =
      String.fromEnvironment('SLIMSHOT_API_URL');

  /// Whether this build has a server at all. Server features are offered
  /// only then — they are not offered before they work.
  static bool get isConfigured => configuredBaseUrl.isNotEmpty;

  static const Duration defaultTimeout = Duration(seconds: 20);

  final String _base;
  final http.Client _client;
  final AccountSession _session;
  final DeviceTokenStore _tokens;

  Uri uri(String path) => Uri.parse('$_base/api/app/v1$path');

  /// A JSON request to [path].
  http.Request jsonRequest(
    String method,
    String path,
    Map<String, Object?> body,
  ) =>
      http.Request(method, uri(path))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

  /// Sends the request [build] makes as the signed-in user and returns the
  /// envelope's `data`.
  ///
  /// An access token lasts minutes. Expired, it is exchanged once — through
  /// the session, so requests refused together share one exchange — and the
  /// request is built again: a request can be sent only once, and a
  /// multipart body is a stream. No session, any other refusal, or a second
  /// refusal ends in [SlimshotApiException.signInRequired]: a request that
  /// cannot be made as anyone is the sign-in sheet's cue, never a loop.
  Future<Map<String, dynamic>> send(
    http.BaseRequest Function() build, {
    Duration timeout = defaultTimeout,
  }) async {
    final tokens = await _session.read();
    if (tokens == null) {
      throw const SlimshotApiException(SlimshotApiException.signInRequired);
    }
    var response =
        await _perform(_authorised(build(), tokens.accessToken), timeout);
    if (response.statusCode != HttpStatus.unauthorized) {
      return _decode(response);
    }
    final fresh = _errorCode(response) == 'UNAUTHENTICATED'
        ? await _session.refreshAfter(
            tokens.accessToken,
            (refreshToken) => _exchange(refreshToken, timeout),
          )
        : null;
    if (fresh != null) {
      response =
          await _perform(_authorised(build(), fresh.accessToken), timeout);
      if (response.statusCode != HttpStatus.unauthorized) {
        return _decode(response);
      }
    }
    await _session.end();
    throw const SlimshotApiException(SlimshotApiException.signInRequired);
  }

  /// Sends a request that needs no sign-in and carries no install token.
  Future<Map<String, dynamic>> sendPublic(
    http.BaseRequest Function() build, {
    Duration timeout = defaultTimeout,
  }) async =>
      _decode(await _perform(build(), timeout));

  /// POSTs [body] as JSON with this install's token added as `deviceToken` —
  /// how a sign-in names the phone. A token the server no longer knows (a
  /// reset database) is replaced once and the request sent again.
  Future<Map<String, dynamic>> sendWithDevice(
    String path,
    Map<String, Object?> body, {
    Duration timeout = defaultTimeout,
  }) async {
    Future<http.Response> post(String deviceToken) => _perform(
          jsonRequest('POST', path, {...body, 'deviceToken': deviceToken}),
          timeout,
        );
    var response = await post(await deviceToken(timeout: timeout));
    if (_errorCode(response) == 'DEVICE_NOT_REGISTERED') {
      await _tokens.clear();
      response = await post(await _register(timeout));
    }
    return _decode(response);
  }

  /// This install's token, registering the install the first time.
  Future<String> deviceToken({Duration timeout = defaultTimeout}) async =>
      await _tokens.read() ?? await _register(timeout);

  /// Aborts anything in flight — how Cancel stops an upload.
  void close() => _client.close();

  http.BaseRequest _authorised(http.BaseRequest request, String token) {
    request.headers['Authorization'] = 'Bearer $token';
    return request;
  }

  /// A refresh token traded for new tokens.
  ///
  /// Refused (401): the token is spent, revoked or unknown — null, and the
  /// session ends. Anything else that is not an answer — a server error, a
  /// proxy's page — says nothing about the session, so it is thrown and the
  /// session kept.
  Future<SessionTokens?> _exchange(String refreshToken, Duration timeout) async {
    final response = await _perform(
      jsonRequest('POST', '/auth/refresh', {'refreshToken': refreshToken}),
      timeout,
    );
    if (response.statusCode == HttpStatus.unauthorized) return null;
    final data = _decode(response);
    final access = data['accessToken'];
    final refresh = data['refreshToken'];
    if (access is! String || refresh is! String) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No session.',
      );
    }
    return SessionTokens(accessToken: access, refreshToken: refresh);
  }

  Future<String> _register(Duration timeout) async {
    final data = _decode(await _perform(
      jsonRequest('POST', '/devices', {'platform': 'android'}),
      timeout,
    ));
    final token = data['token'];
    if (token is! String || token.isEmpty) {
      throw const SlimshotApiException(
        SlimshotApiException.badResponse,
        'No device token.',
      );
    }
    await _tokens.write(token);
    return token;
  }

  Future<http.Response> _perform(
    http.BaseRequest request,
    Duration timeout,
  ) async {
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const SlimshotApiException(
        SlimshotApiException.network,
        'Timed out.',
      );
    } on SocketException catch (e) {
      throw SlimshotApiException(SlimshotApiException.network, e.message);
    } on http.ClientException catch (e) {
      throw SlimshotApiException(SlimshotApiException.network, e.message);
    }
  }

  static Object? _body(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  static String? _errorCode(http.Response response) {
    final body = _body(response);
    if (body is Map && body['error'] is Map) {
      final code = (body['error'] as Map)['code'];
      return code is String ? code : null;
    }
    return null;
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = _body(response);
    if (body is Map && body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      final code = error['code'];
      final message = error['message'];
      final details = error['details'];
      throw SlimshotApiException(
        code is String ? code : 'HTTP_${response.statusCode}',
        message is String ? message : '',
        details is Map ? Map<String, Object?>.from(details) : const {},
      );
    }
    throw SlimshotApiException(
      SlimshotApiException.badResponse,
      'HTTP ${response.statusCode}',
    );
  }
}
