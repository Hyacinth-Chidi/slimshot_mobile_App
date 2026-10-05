import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import 'account_fakes.dart';

http.Response envelope(Object data, [int status = 200]) =>
    http.Response(jsonEncode({'success': true, 'data': data}), status);

http.Response failure(
  String code,
  int status, {
  Map<String, Object?>? details,
}) =>
    http.Response(
      jsonEncode({
        'success': false,
        'error': {
          'code': code,
          'message': 'm',
          if (details != null) 'details': details,
          'traceId': 't',
        },
      }),
      status,
    );

/// The server, answering by method and path, and remembering every request.
/// A route nobody set answers 404 NOT_FOUND.
class FakeServer {
  final List<http.Request> requests = [];
  final Map<String, FutureOr<http.Response> Function(http.Request)> _routes =
      {};

  late final MockClient client = MockClient((request) async {
    requests.add(request);
    final answer = _routes['${request.method} ${request.url.path}'];
    if (answer == null) return failure('NOT_FOUND', 404);
    return await answer(request);
  });

  /// Answers `METHOD /api/app/v1[path]`.
  void on(
    String method,
    String path,
    FutureOr<http.Response> Function(http.Request request) answer,
  ) {
    _routes['$method /api/app/v1$path'] = answer;
  }

  Iterable<http.Request> to(String method, String path) => requests.where(
        (r) => r.method == method && r.url.path == '/api/app/v1$path',
      );

  Map<String, dynamic> lastBody(String method, String path) =>
      jsonDecode(to(method, path).last.body) as Map<String, dynamic>;
}

Map<String, Object?> userJson({
  String username = 'ann_1',
  int balance = 100,
  bool needsClaim = false,
  String status = 'active',
}) =>
    {
      'id': 'u1',
      'email': 'ann@example.com',
      'username': needsClaim ? null : username,
      'referralCode': 'AB3DEF7K',
      'creditBalance': balance,
      'accountStatus': status,
      'needsClaim': needsClaim,
      'signInMethods': {'google': false, 'email': true},
      'ads': {'rewardCredits': 5, 'dailyCap': 10, 'remainingToday': 10},
    };

Map<String, Object?> signInJson({
  bool needsClaim = false,
  String access = 'a1',
  String refresh = 'r1',
}) =>
    {
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': 900,
      'isNewAccount': needsClaim,
      'needsClaim': needsClaim,
      'user': userJson(needsClaim: needsClaim, balance: needsClaim ? 0 : 100),
    };

/// A client on [server], with an install already registered as `dev-1`.
SlimshotApi fakeApi(
  FakeServer server, {
  AccountSession? session,
  DeviceTokenStore? devices,
}) =>
    SlimshotApi(
      baseUrl: 'https://api.test',
      client: server.client,
      session: session ?? AccountSession(vault: MemoryTokenVault()),
      tokens: devices ?? MemoryDeviceTokens('dev-1'),
    );
