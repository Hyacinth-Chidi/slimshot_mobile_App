import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_gate.dart';

/// The one door every auto-caption run passes, before its options open: a
/// signed-in, claimed account. The sign-in and claim sheets come first when
/// it is not.
class CaptionAccess {
  const CaptionAccess._();

  static Future<bool> ensureAllowed(BuildContext context, WidgetRef ref) =>
      requireAccount(context, ref, reason: 'Sign in to use Auto captions');
}
