import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../video_editor/widgets/panels/editor_sheet.dart';
import 'providers/account_providers.dart';
import 'widgets/claim_sheet.dart';
import 'widgets/sign_in_sheet.dart';

/// The one door to anything that needs an account: the sign-in sheet when
/// signed out, then the claim sheet for an account that has not claimed.
/// Answers whether the user came through signed in and claimed.
///
/// [reason] is the sign-in sheet's heading — why it opened.
Future<bool> requireAccount(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final notifier = ref.read(accountProvider.notifier);
  if (!ref.read(accountProvider).isSignedIn) {
    // A kept session whose profile has not loaded yet is still a session.
    await notifier.refresh();
  }
  if (!context.mounted) return false;
  if (!ref.read(accountProvider).isSignedIn) {
    final signedIn = await showEditorSheet<bool>(
      context,
      builder: (_) => SignInSheet(reason: reason),
    );
    if (signedIn != true || !context.mounted) return false;
  }
  if (ref.read(accountProvider).needsClaim) {
    final claimed = await showEditorSheet<bool>(
      context,
      builder: (_) => const ClaimSheet(),
    );
    if (claimed != true) return false;
  }
  return ref.read(accountProvider).isSignedIn;
}
