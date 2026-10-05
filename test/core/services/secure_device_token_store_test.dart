import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/services/slimshot_api.dart';

import '../../support/account_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a token kept in preferences moves into the vault, once', () async {
    SharedPreferences.setMockInitialValues({
      SecureDeviceTokenStore.legacyPrefsKey: 'old-token',
    });
    final vault = MemoryTokenVault();
    final store = SecureDeviceTokenStore(vault);

    expect(await store.read(), 'old-token');
    expect(vault.values[SecureDeviceTokenStore.vaultKey], 'old-token');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SecureDeviceTokenStore.legacyPrefsKey), isNull);
    expect(await store.read(), 'old-token');
  });

  test('the vault wins over a leftover in preferences', () async {
    SharedPreferences.setMockInitialValues({
      SecureDeviceTokenStore.legacyPrefsKey: 'old-token',
    });
    final vault = MemoryTokenVault()
      ..values[SecureDeviceTokenStore.vaultKey] = 'new-token';
    expect(await SecureDeviceTokenStore(vault).read(), 'new-token');
  });

  test('nothing stored reads as nothing', () async {
    expect(await SecureDeviceTokenStore(MemoryTokenVault()).read(), isNull);
  });

  test('write and clear go to the vault, and clear leaves no copy behind',
      () async {
    SharedPreferences.setMockInitialValues({
      SecureDeviceTokenStore.legacyPrefsKey: 'old-token',
    });
    final vault = MemoryTokenVault();
    final store = SecureDeviceTokenStore(vault);
    await store.write('t');
    expect(vault.values[SecureDeviceTokenStore.vaultKey], 't');
    await store.clear();
    expect(vault.values, isEmpty);
    expect(await store.read(), isNull);
  });
}
