import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'token_vault.dart';

/// A request the server refused, or one that never reached it.
class SlimshotApiException implements Exception {
  const SlimshotApiException(this.code, [this.message = '']);

  /// The server's error code (`CAPTIONS_UNAVAILABLE`, `NOT_FOUND`, …) or one
  /// of the local codes below.
  final String code;
  final String message;

  /// No connection, a timeout, or a request cut off.
  static const String network = 'NETWORK';

  /// A body that was not the server's envelope.
  static const String badResponse = 'BAD_RESPONSE';

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
/// Auto captions is the first server feature of several (fonts and sign-in
/// follow), so registration, the token and the response envelope live here
/// rather than in any one feature.
class SlimshotApi {
  SlimshotApi({
    required String baseUrl,
    http.Client? client,
    DeviceTokenStore tokens = const SecureDeviceTokenStore(),
  })  : _base = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client(),
        _tokens = tokens;

  /// The server this build talks to: `--dart-define=SLIMSHOT_API_URL=…`.
  /// Empty when the build carries none.
  static const String configuredBaseUrl =
      String.fromEnvironment('SLIMSHOT_API_URL');

  /// Whether this build has a server at all. Auto captions is offered only
  /// then — it is not offered before it works.
  static bool get isConfigured => configuredBaseUrl.isNotEmpty;

  static const Duration defaultTimeout = Duration(seconds: 20);

  final String _base;
  final http.Client _client;
  final DeviceTokenStore _tokens;

  Uri uri(String path) => Uri.parse('$_base/api/app/v1$path');

  /// Sends the request [build] makes, as this device, and returns the
  /// envelope's `data`.
  ///
  /// [build] runs again for the one retry after a 401: a request can be sent
  /// only once, and a multipart body is a stream.
  Future<Map<String, dynamic>> send(
    http.BaseRequest Function() build, {
    Duration timeout = defaultTimeout,
  }) async {
    var token = await _tokens.read() ?? await _register(timeout);
    var response = await _perform(_authorised(build(), token), timeout);
    if (response.statusCode == HttpStatus.unauthorized) {
      // A token the server no longer knows — a reset database, a revoked
      // install. Register again once; a second refusal is an answer, not a
      // reason to loop.
      await _tokens.clear();
      token = await _register(timeout);
      response = await _perform(_authorised(build(), token), timeout);
    }
    return _decode(response);
  }

  /// Aborts anything in flight — how Cancel stops an upload.
  void close() => _client.close();

  http.BaseRequest _authorised(http.BaseRequest request, String token) {
    request.headers['Authorization'] = 'Bearer $token';
    return request;
  }

  Future<String> _register(Duration timeout) async {
    final request = http.Request('POST', uri('/devices'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'platform': 'android'});
    final data = _decode(await _perform(request, timeout));
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

  Map<String, dynamic> _decode(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      body = null;
    }
    if (body is Map && body['success'] == true && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      final code = error['code'];
      final message = error['message'];
      throw SlimshotApiException(
        code is String ? code : 'HTTP_${response.statusCode}',
        message is String ? message : '',
      );
    }
    throw SlimshotApiException(
      SlimshotApiException.badResponse,
      'HTTP ${response.statusCode}',
    );
  }
}
