import 'dart:convert';

import 'package:slimshotai/core/services/account_session.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';
import 'package:slimshotai/core/services/token_vault.dart';

/// A [TokenVault] in memory: what a test stores, it can read straight back.
class MemoryTokenVault implements TokenVault {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// An install token in memory; null until the install is registered.
class MemoryDeviceTokens implements DeviceTokenStore {
  MemoryDeviceTokens([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

/// A session already signed in, optionally with a profile kept from last
/// time.
AccountSession signedInSession({
  String access = 'tok',
  String refresh = 'ref',
  Map<String, Object?>? profile,
}) {
  final vault = MemoryTokenVault();
  vault.values[AccountSession.accessKey] = access;
  vault.values[AccountSession.refreshKey] = refresh;
  if (profile != null) {
    vault.values[AccountSession.profileKey] = jsonEncode(profile);
  }
  return AccountSession(vault: vault);
}
