import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/lucide_icons.dart';
import 'frosted_glass.dart';

/// One card of Settings rows: the home screen's frosted glass, so Settings
/// sits on the same colour field in the same material.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FrostedGlass(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDanger;
  final bool showChevron;

  const SettingsItem({
    super.key,
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
      type: MaterialType.transparency,
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
                // The home tool cards' tile: a little white on the glass.
                decoration: BoxDecoration(
                  color: isDanger
                      ? AppColors.error.withValues(alpha: 0.15)
                      : AppColors.textPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDanger
                        ? AppColors.error.withValues(alpha: 0.30)
                        : AppColors.textPrimary.withValues(alpha: 0.14),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isDanger ? AppColors.error : AppColors.textPrimary,
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
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        color: AppColors.textPrimary.withValues(alpha: 0.08),
      ),
    );
  }
}
