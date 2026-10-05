import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secrets by name: the install token, the session tokens and the
/// signed-in profile.
abstract class TokenVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The vault in the platform's keystore-backed storage.
///
/// **A value that cannot be decrypted reads as absent.** A backup restored
/// onto a phone whose keystore never held the key that encrypted it cannot be
/// read back; throwing there would break every launch, where reading nothing
/// leaves the app signed out — which is the truth on that phone.
class SecureTokenVault implements TokenVault {
  const SecureTokenVault([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SecureTokenVault: $key unreadable ($e)');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SecureTokenVault: $key not deleted ($e)');
    }
  }
}
