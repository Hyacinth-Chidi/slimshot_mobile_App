import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/glass_card.dart';
import '../core/utils/file_utils.dart';
import '../core/utils/toast_utils.dart';
import '../core/widgets/responsive_layout.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [

          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryStart.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

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
                        const _SectionHeader(
                          title: 'GENERAL',
                        ).animate().fadeIn(delay: 100.ms),
                        const SizedBox(height: 8),
                        GlassCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _SettingsItem(
                                icon: LucideIcons.info,
                                title: 'App Version',
                                subtitle: 'v2.0.0 (2)',
                                showChevron: false,
                                onTap: () {},
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),

                        const SizedBox(height: 28),

                        const _SectionHeader(
                          title: 'DATA & STORAGE',
                        ).animate().fadeIn(delay: 250.ms),
                        const SizedBox(height: 8),
                        GlassCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _SettingsItem(
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
                                      _showSnackBar(
                                        context,
                                        'Onboarding will show on next launch',
                                        Icons.check_circle,
                                        AppColors.success,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const _Divider(),
                              _SettingsItem(
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
                                      _showSnackBar(
                                        context,
                                        '$count cached files cleared',
                                        Icons.check_circle,
                                        AppColors.success,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
                        const SizedBox(height: 28),

                        const _SectionHeader(
                          title: 'LEGAL',
                        ).animate().fadeIn(delay: 350.ms),
                        const SizedBox(height: 8),
                        GlassCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _SettingsItem(
                                icon: LucideIcons.shield,
                                title: 'Privacy Policy',
                                subtitle: 'Review our data practices',
                                onTap: () async {
                                  final url = Uri.parse('https://slimshotai.vercel.app/privacy');
                                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                                    if (context.mounted) {
                                      _showSnackBar(
                                        context,
                                        'Could not open privacy policy',
                                        Icons.error_outline,
                                        AppColors.error,
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
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
                                          color: AppColors.primaryStart,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Powered by TechFamz',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            )
                            .animate()
                            .fadeIn(delay: 600.ms)
                            .slideY(begin: 0.2, end: 0),
                        const SizedBox(height: 100), // Padding for global nav bar
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

  void _showSnackBar(
    BuildContext context,
    String message,
    IconData icon,
    Color color,
  ) {
    final isError = color == AppColors.error;
    ToastUtils.show(context, message, isError: isError);
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


class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDanger;
  final bool showChevron;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.isDanger = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDanger
                      ? AppColors.error.withValues(alpha: 0.15)
                      : AppColors.surfaceLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isDanger ? AppColors.error : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDanger
                            ? AppColors.error
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.textTertiary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(height: 1, color: AppColors.border.withValues(alpha: 0.4)),
    );
  }
}
