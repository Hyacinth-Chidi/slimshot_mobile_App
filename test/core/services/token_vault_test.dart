import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/services/token_vault.dart';

/// Storage whose every read fails, as it does on a phone that restored a
/// backup without the keystore key that encrypted it.
class _UnreadableStorage implements FlutterSecureStorage {
  const _UnreadableStorage();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) {
      return Future<String?>.error(
        PlatformException(code: 'Exception', message: 'BAD_DECRYPT'),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stores, reads and deletes a value', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const vault = SecureTokenVault();
    expect(await vault.read('k'), isNull);
    await vault.write('k', 'v');
    expect(await vault.read('k'), 'v');
    await vault.delete('k');
    expect(await vault.read('k'), isNull);
  });

  test('a value that cannot be decrypted reads as absent', () async {
    const vault = SecureTokenVault(_UnreadableStorage());
    expect(await vault.read('k'), isNull);
  });
}
