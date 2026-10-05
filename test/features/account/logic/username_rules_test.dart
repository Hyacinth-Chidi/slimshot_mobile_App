import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/account/logic/username_rules.dart';

String typed(String text) {
  var value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  for (final formatter in usernameInputFormatters) {
    value = formatter.formatEditUpdate(TextEditingValue.empty, value);
  }
  return value.text;
}

void main() {
  test('3–20 of a–z, 0–9 and _', () {
    for (final ok in ['ann', 'ann_1', 'a1_', '___', 'a' * 20]) {
      expect(isValidUsername(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'an', 'a' * 21, 'Ann', 'ann-1', 'ann 1', 'añn']) {
      expect(isValidUsername(bad), isFalse, reason: bad);
    }
  });

  test('typing keeps only what a username may hold, in lower case', () {
    expect(typed('Ann_1'), 'ann_1');
    expect(typed('ann-1!'), 'ann1');
    expect(typed('a' * 25), 'a' * 20);
  });
}
