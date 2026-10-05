import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/colour_field_backdrop.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/responsive_layout.dart';
import '../core/widgets/settings_rows.dart';
import '../features/account/widgets/settings_account_section.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: ColourFieldBackdrop()),

          SafeArea(
            child: ResponsiveCenter(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 44),
                        const Expanded(
                          child: Text(
                            'Settings',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ).animate().fadeIn().slideY(begin: -0.2, end: 0),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SettingsAccountSection(),
                        const SettingsSectionHeader(
                          title: 'GENERAL',
                        ).animate().fadeIn(delay: 100.ms),
                        const SizedBox(height: 8),
                        SettingsGroup(
                          children: [
                            SettingsItem(
                              icon: LucideIcons.info,
                              title: 'App Version',
                              subtitle: 'v2.0.0 (2)',
                              showChevron: false,
                              onTap: () {},
                            ),
                          ],
                        ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),

                        const SizedBox(height: 28),

                        const SettingsSectionHeader(
                          title: 'DATA & STORAGE',
                        ).animate().fadeIn(delay: 250.ms),
                        const SizedBox(height: 8),
                        SettingsGroup(
                          children: [
                            SettingsItem(
                              icon: LucideIcons.refreshCw,
                              title: 'Reset Onboarding',
                              subtitle: 'Show welcome screen again',
                              onTap: () => _showConfirmDialog(
                                context,
                                title: 'Reset Onboarding',
                                message:
                                    'This will show the onboarding screen again on next app launch.',
                                confirmLabel: 'Reset',
                                onConfirm: () async {
                                  final prefs =
                                      await SharedPreferences.getInstance();
                                  await prefs.setBool(
                                    'hasSeenOnboarding',
                                    false,
                                  );
                                  if (context.mounted) {
                                    ToastUtils.show(
                                      context,
                                      'Onboarding will show on next launch',
                                    );
                                  }
                                },
                              ),
                            ),
                            const SettingsDivider(),
                            SettingsItem(
                              icon: LucideIcons.trash2,
                              title: 'Clear Cache',
                              subtitle: 'Remove temporary files',
                              isDanger: true,
                              onTap: () => _showConfirmDialog(
                                context,
                                title: 'Clear Cache',
                                message:
                                    'This will remove all cached compression data.',
                                confirmLabel: 'Clear',
                                isDanger: true,
                                onConfirm: () async {
                                  final count = await FileUtils.clearCache();
                                  if (context.mounted) {
                                    ToastUtils.show(
                                      context,
                                      '$count cached files cleared',
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                        const SizedBox(height: 28),

                        const SettingsSectionHeader(
                          title: 'LEGAL',
                        ).animate().fadeIn(delay: 350.ms),
                        const SizedBox(height: 8),
                        SettingsGroup(
                          children: [
                            SettingsItem(
                              icon: LucideIcons.shield,
                              title: 'Privacy Policy',
                              subtitle: 'Review our data practices',
                              onTap: () async {
                                final url = Uri.parse(
                                  'https://slimshotai.vercel.app/privacy',
                                );
                                if (!await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                )) {
                                  if (context.mounted) {
                                    ToastUtils.show(
                                      context,
                                      'Could not open privacy policy',
                                      isError: true,
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

                        const SizedBox(height: 48),
                        Column(
                              children: [
                                RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'SlimShot',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'AI',
                                        style: TextStyle(
                                          color: AppColors.lilac,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Powered by TechFamz',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                            .animate()
                            .fadeIn(delay: 600.ms)
                            .slideY(begin: 0.2, end: 0),
                        const SizedBox(
                          height: 100,
                        ), // Padding for global nav bar
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required VoidCallback onConfirm,
    bool isDanger = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: isDanger ? AppColors.error : AppColors.primaryStart,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
