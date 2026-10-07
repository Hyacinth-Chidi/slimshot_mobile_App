import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// [onEarned] hears every rise in the balance while the block is on screen
/// — a granted ad, or a reward that landed after its poll gave up ("on its
/// way"). Always the server's number; the app never adds credits itself.
class EarnCreditsBlock extends ConsumerStatefulWidget {
  const EarnCreditsBlock({super.key, this.onEarned});

  final void Function(int balance)? onEarned;

  @override
  ConsumerState<EarnCreditsBlock> createState() => _EarnCreditsBlockState();
}

class _EarnCreditsBlockState extends ConsumerState<EarnCreditsBlock> {
  bool _watching = false;

  /// Waiting for the ad itself, before it shows.
  bool _loadingAd = false;

  bool _prepared = false;

  /// After "on its way": AdMob can call the server after the poll gave up,
  /// so the balance is looked at again later (contract §13).
  static const List<Duration> lateLooks = [
    Duration(seconds: 30),
    Duration(seconds: 90),
  ];
  final List<Timer> _looks = [];

  @override
  void dispose() {
    for (final look in _looks) {
      look.cancel();
    }
    super.dispose();
  }

  Future<void> _watch() async {
    setState(() {
      _watching = true;
      _loadingAd = true;
    });
    final notifier = ref.read(accountProvider.notifier);
    try {
      final reward = await ref.read(creditAdServiceProvider).watch(
        onPlayed: () {
          if (mounted) setState(() => _loadingAd = false);
        },
      );
      final balance = reward.balance;
      if (reward.outcome == AdRewardOutcome.granted && balance != null) {
        await notifier.applyBalance(balance);
      }
      if (reward.outcome == AdRewardOutcome.pending) {
        for (final wait in lateLooks) {
          _looks.add(Timer(wait, () => unawaited(notifier.refresh())));
        }
      }
      if (mounted) {
        ToastUtils.show(
          context,
          adRewardMessage(reward, withReason: kDebugMode),
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
      if (mounted) {
        setState(() {
          _watching = false;
          _loadingAd = false;
        });
      }
    }
  }

  Future<void> _invite(String code) =>
      ref.read(shareTextProvider)(inviteMessage(code));

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) ToastUtils.show(context, 'Code copied');
  }

  @override
  Widget build(BuildContext context) {
    // The balance rising is what earning means here, however it arrived.
    ref.listen<AccountState>(accountProvider, (previous, next) {
      final before = previous?.user?.creditBalance;
      final now = next.user?.creditBalance;
      if (before != null && now != null && now > before) {
        widget.onEarned?.call(now);
      }
    });
    final user = ref.watch(accountProvider).user;
    if (user == null) return const SizedBox.shrink();
    final adsOn = ref.watch(creditAdsEnabledProvider);
    final allowance = user.ads;
    // Only a known allowance can be spent; unknown is not "none left".
    final atCap = allowance.known && allowance.remainingToday <= 0;
    if (adsOn && !atCap && !_prepared) {
      // An ad loading while the user reads, so the tap plays it at once.
      _prepared = true;
      unawaited(ref.read(rewardedAdPlayerProvider).prepare());
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (adsOn) ...[
          _EarnButton(
            key: const Key('earn_watch_ad'),
            label: atCap
                ? kBackTomorrow
                : _loadingAd
                    ? kLoadingAd
                    : allowance.known
                        ? watchAdLabel(allowance.rewardCredits)
                        : kWatchAd,
            busy: _watching && !_loadingAd,
            onPressed: atCap || _watching ? null : _watch,
          ),
          if (allowance.known && !atCap)
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
        // A friend types it on their claim step, so it is shown, not only
        // shared.
        GestureDetector(
          onTap: () => unawaited(_copyCode(user.referralCode)),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Your code · ${user.referralCode}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
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
