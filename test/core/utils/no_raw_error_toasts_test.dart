import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// No toast shows a caught error's own text.
///
/// Device-reported (2026-11-10): engine and platform errors reached people
/// word for word — exception class names, player error codes, a file's full
/// path ("Source video does not exist: /data/user/0/…"). A toast says what
/// happened in plain words; the technical detail goes to the log, where it
/// helps someone fixing the app instead of alarming someone using it.
/// `userMessageFor` is how a caught error becomes a toast.
void main() {
  test('no ToastUtils.show interpolates or prints a caught error', () {
    final raw = RegExp(
      r'\$\{?(e|error|err|exception)\b(?!\w)'
      r'|\b(e|error|err|exception)\.(toString\(\)|message)',
    );
    final offences = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      var from = 0;
      while (true) {
        final start = source.indexOf('ToastUtils.show(', from);
        if (start == -1) break;
        final open = start + 'ToastUtils.show'.length;
        var depth = 0;
        var end = open;
        for (; end < source.length; end++) {
          final char = source[end];
          if (char == '(') depth++;
          if (char == ')' && --depth == 0) break;
        }
        final call = source.substring(start, end + 1);
        if (raw.hasMatch(call)) {
          final line = '\n'.allMatches(source.substring(0, start)).length + 1;
          offences.add('${entity.path}:$line  ${call.replaceAll(RegExp(r'\s+'), ' ')}');
        }
        from = end;
      }
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}
