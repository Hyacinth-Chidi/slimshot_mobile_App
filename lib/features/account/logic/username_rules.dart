import 'package:flutter/services.dart';

/// How long typing must pause before the server is asked whether a name is
/// free. The server allows 60 checks a minute.
const Duration kUsernameCheckDelay = Duration(milliseconds: 300);

final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

/// 3–20 characters of `a–z`, `0–9` and `_` — the server's rule. The server
/// also reserves some names; only it can say which.
bool isValidUsername(String name) => _usernamePattern.hasMatch(name);

/// Keeps a username field to what a username may hold, in lower case — the
/// server stores names lowercased, so the field shows what will be kept.
List<TextInputFormatter> get usernameInputFormatters => [
      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9_]')),
      LengthLimitingTextInputFormatter(20),
      const _LowerCase(),
    ];

class _LowerCase extends TextInputFormatter {
  const _LowerCase();

  // ASCII only reaches here, so lowercasing keeps the length — and with it
  // the cursor.
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toLowerCase());
}
