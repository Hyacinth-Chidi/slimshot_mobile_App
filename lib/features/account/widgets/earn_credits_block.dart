import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../providers/account_providers.dart';
import '../services/credit_ads.dart';

/// The ways to earn credits: Watch an ad, Invite a friend. One block for the
/// caption shortfall and the Credits screen, so the two cannot drift.
///
/// [onEarned] hears the balance a granted ad left — the server's number;
/// the app never adds credits itself.
class EarnCreditsBlock extends ConsumerStatefulWidget {
  const EarnCreditsBlock({super.key, this.onEarned});

  final void Function(int balance)? onEarned;

  @override
  ConsumerState<EarnCreditsBlock> createState() => _EarnCreditsBlockState();
}

class _EarnCreditsBlockState extends ConsumerState<EarnCreditsBlock> {
  bool _watching = false;

  Future<void> _watch() async {
    setState(() => _watching = true);
    final notifier = ref.read(accountProvider.notifier);
    try {
      final reward = await ref.read(creditAdServiceProvider).watch();
      final balance = reward.balance;
      if (reward.outcome == AdRewardOutcome.granted && balance != null) {
        await notifier.applyBalance(balance);
        widget.onEarned?.call(balance);
      }
      if (mounted) {
        ToastUtils.show(
          context,
          adRewardMessage(reward),
          isError: reward.outcome != AdRewardOutcome.granted &&
              reward.outcome != AdRewardOutcome.pending,
        );
      }
    } on SlimshotApiException catch (e) {
      if (mounted) {
        ToastUtils.show(context, accountErrorMessage(e), isError: true);
      }
    } finally {
      // Today's count, and a late grant, come from the server.
      unawaited(notifier.refresh());
      if (mounted) setState(() => _watching = false);
    }
  }

  Future<void> _invite(String code) =>
      ref.read(shareTextProvider)(inviteMessage(code));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(accountProvider).user;
    if (user == null) return const SizedBox.shrink();
    final adsOn = ref.watch(creditAdsEnabledProvider);
    final allowance = user.ads;
    final atCap = allowance.remainingToday <= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adsOn) ...[
          _EarnButton(
            key: const Key('earn_watch_ad'),
            label: atCap ? kBackTomorrow : watchAdLabel(allowance.rewardCredits),
            busy: _watching,
            onPressed: atCap || _watching ? null : _watch,
          ),
          if (!atCap)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                adsLeftLabel(allowance.remainingToday),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        _EarnButton(
          key: const Key('earn_invite'),
          label: 'Invite a friend',
          onPressed: () => unawaited(_invite(user.referralCode)),
        ),
      ],
    );
  }
}

class _EarnButton extends StatelessWidget {
  const _EarnButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            disabledForegroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textPrimary,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      );
}
