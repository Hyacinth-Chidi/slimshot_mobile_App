import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/services/removed_features.dart';

/// What a removed feature left in preferences is cleared, not left on the
/// phone for good.
void main() {
  test('the compression history list goes; everything else stays', () async {
    SharedPreferences.setMockInitialValues({
      'optimization_history': ['{"id":"a"}'],
      'hasSeenOnboarding': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await forgetRemovedFeatures(prefs);
    expect(prefs.containsKey('optimization_history'), isFalse);
    expect(prefs.getBool('hasSeenOnboarding'), isTrue);
  });
}
