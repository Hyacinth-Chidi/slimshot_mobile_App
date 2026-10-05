import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/widgets/settings_rows.dart';
import '../../video_editor/widgets/panels/editor_sheet.dart';
import '../account_gate.dart';
import '../providers/account_providers.dart';
import 'delete_account_sheet.dart';
import 'username_sheet.dart';

/// Settings' Account section: Sign in when signed out; username, email,
/// sign out and delete account when signed in. Absent in a build with no
/// server.
class SettingsAccountSection extends ConsumerWidget {
  const SettingsAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(accountFeatureProvider)) return const SizedBox.shrink();
    final user = ref.watch(accountProvider).user;

    void signIn() => unawaited(
      requireAccount(context, ref, reason: 'Sign in to get free credits'),
    );

    final rows = user == null
        ? [
            SettingsItem(
              icon: LucideIcons.user,
              title: 'Sign in',
              onTap: signIn,
            ),
          ]
        : [
            SettingsItem(
              icon: LucideIcons.atSign,
              title: 'Username',
              subtitle: user.username ?? 'Not set',
              onTap: () {
                final current = user.username;
                if (current == null) {
                  signIn(); // not claimed yet: the claim sets the name
                  return;
                }
                unawaited(
                  showEditorSheet<void>(
                    context,
                    useRootNavigator: true,
                    builder: (_) => UsernameSheet(current: current),
                  ),
                );
              },
            ),
            const SettingsDivider(),
            SettingsItem(
              icon: LucideIcons.mail,
              title: 'Email',
              subtitle: user.email,
              showChevron: false,
              onTap: () {},
            ),
            const SettingsDivider(),
            SettingsItem(
              icon: LucideIcons.logOut,
              title: 'Sign out',
              showChevron: false,
              onTap: () async {
                await ref.read(accountProvider.notifier).signOut();
                if (context.mounted) ToastUtils.show(context, 'Signed out');
              },
            ),
            const SettingsDivider(),
            SettingsItem(
              icon: LucideIcons.trash2,
              title: 'Delete account',
              isDanger: true,
              onTap: () => unawaited(
                showEditorSheet<void>(
                  context,
                  useRootNavigator: true,
                  builder: (_) => const DeleteAccountSheet(),
                ),
              ),
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionHeader(title: 'ACCOUNT'),
        const SizedBox(height: 8),
        SettingsGroup(children: rows),
        const SizedBox(height: 28),
      ],
    );
  }
}
