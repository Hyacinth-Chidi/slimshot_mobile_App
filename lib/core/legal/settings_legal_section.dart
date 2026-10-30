import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/lucide_icons.dart';
import '../utils/toast_utils.dart';
import '../widgets/settings_rows.dart';
import 'legal_links.dart';
import 'third_party_licences.dart';

/// Settings' Legal group: the privacy policy and the terms, both pages on the
/// SlimShot website, and the open-source notices the app carries.
class SettingsLegalSection extends ConsumerWidget {
  const SettingsLegalSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> open(String url, String name) async {
      final opened = await ref.read(legalLinkOpenerProvider)(Uri.parse(url));
      if (!opened && context.mounted) {
        ToastUtils.show(context, 'Could not open the $name', isError: true);
      }
    }

    return SettingsGroup(
      children: [
        SettingsItem(
          icon: LucideIcons.shield,
          title: 'Privacy Policy',
          subtitle: 'What the app does with your data',
          onTap: () => open(kPrivacyPolicyUrl, 'Privacy Policy'),
        ),
        const SettingsDivider(),
        SettingsItem(
          icon: LucideIcons.scrollText,
          title: 'Terms of Service',
          subtitle: 'The rules for using SlimShot',
          onTap: () => open(kTermsOfServiceUrl, 'Terms of Service'),
        ),
        const SettingsDivider(),
        SettingsItem(
          icon: LucideIcons.fileText,
          title: 'Open-source licences',
          subtitle: 'Notices for code SlimShot uses',
          onTap: () => openSourceLicences(context),
        ),
      ],
    );
  }
}
