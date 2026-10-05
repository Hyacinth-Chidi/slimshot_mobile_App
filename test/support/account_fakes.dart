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
