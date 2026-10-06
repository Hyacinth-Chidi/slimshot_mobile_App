import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/widgets/frosted_glass.dart';
import '../account_gate.dart';
import '../providers/account_providers.dart';
import '../screens/credits_screen.dart';

/// Top right of the home screen: the balance when signed in and claimed,
/// otherwise "Free credits", which opens the way to them.
///
/// No number is promised before sign-in: the bonus is set by the admin and
/// not every email or phone is eligible, so only the claim names an amount.
/// The balance is read again whenever the app comes back to the front.
class CreditsPill extends ConsumerStatefulWidget {
  const CreditsPill({super.key});

  @override
  ConsumerState<CreditsPill> createState() => _CreditsPillState();
}

class _CreditsPillState extends ConsumerState<CreditsPill> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () {
      if (ref.read(accountFeatureProvider)) {
        unawaited(ref.read(accountProvider.notifier).refresh());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(accountFeatureProvider)) return const SizedBox.shrink();
    final user = ref.watch(accountProvider).user;
    if (user != null && !user.needsClaim) {
      return _Pill(
        key: const Key('credits_pill_balance'),
        icon: LucideIcons.coins,
        label: '${user.creditBalance}',
        onTap: () => openCreditsScreen(context),
      );
    }
    return _Pill(
      key: const Key('credits_pill_free'),
      icon: LucideIcons.gift,
      label: 'Free credits',
      onTap: () => unawaited(
        requireAccount(context, ref, reason: 'Sign in to get free credits'),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The home cards' glass, so the pill sits on the colour field as one of
    // them. The coin is gold: a purple one vanished into the field behind it.
    return FrostedGlass(
      borderRadius: BorderRadius.circular(999),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.credit),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
