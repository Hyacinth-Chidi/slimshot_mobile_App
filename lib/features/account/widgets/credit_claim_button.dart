import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/toast_utils.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';

/// Credits claimed once a day, a week or a month, on the Credits screen alone
/// (the owner's call). The server decides everything — whether claims are on,
/// how many, how often, when the next one is due — and the app shows it:
/// "Claim daily credits · +5", then a countdown on the same button. Missed
/// periods never add up, so there is nothing to show about them.
///
/// Off, or an answer the app cannot read, is no button at all. [onClaimed]
/// hears a claim that paid, so the history can show it.
class CreditClaimButton extends ConsumerStatefulWidget {
  const CreditClaimButton({super.key, this.onClaimed});

  final VoidCallback? onClaimed;

  @override
  ConsumerState<CreditClaimButton> createState() => _CreditClaimButtonState();
}

class _CreditClaimButtonState extends ConsumerState<CreditClaimButton> {
  CreditClaimStatus? _status;
  bool _claiming = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final status = await ref.read(accountServiceProvider).claimStatus();
      if (!mounted) return;
      setState(() => _status = status);
      _countDown();
    } on SlimshotApiException catch (e) {
      debugPrint('CreditClaimButton: ${e.code}');
    }
  }

  DateTime _now() => ref.read(claimClockProvider)();

  /// The time left until [next], rounded up, so the button never reads
  /// 0:00:00 while it is still waiting.
  Duration? _left(CreditClaimStatus status) {
    final next = status.nextClaimAt;
    if (next == null) return null;
    final millis = next.difference(_now()).inMilliseconds;
    if (millis <= 0) return null;
    return Duration(seconds: (millis / 1000).ceil());
  }

  /// A second at a time while the claim waits; stops when it is due.
  void _countDown() {
    _tick?.cancel();
    final status = _status;
    if (status == null || _left(status) == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_left(status) == null) timer.cancel();
    });
  }

  Future<void> _claim() async {
    final status = _status;
    if (status == null || _claiming) return;
    HapticFeedback.selectionClick();
    setState(() => _claiming = true);
    try {
      final result = await ref.read(accountServiceProvider).claimCredits();
      await ref.read(accountProvider.notifier).applyBalance(result.balance);
      if (!mounted) return;
      setState(() => _status = status.claimedUntil(result.nextClaimAt));
      ToastUtils.show(context, '+${creditCount(result.credits)}');
      widget.onClaimed?.call();
    } on SlimshotApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        // Claimed already — on another phone, or by a second tap.
        case 'DAILY_REWARD_NOT_READY':
          final next = e.details['nextClaimAt'];
          final at = next is String ? DateTime.tryParse(next) : null;
          if (at != null) {
            setState(() => _status = status.claimedUntil(at));
          } else {
            unawaited(_read());
          }
        case 'DAILY_REWARD_OFF':
          setState(() => _status = null);
        default:
          ToastUtils.show(context, accountErrorMessage(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
    _countDown();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.enabled) return const SizedBox.shrink();
    final left = _left(status);
    final ready = left == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        key: const Key('credits_claim'),
        height: 46,
        child: OutlinedButton(
          onPressed: ready && !_claiming ? _claim : null,
          // Claimable, it is the one thing on the card that pays now: white
          // on purple. Waiting, it is the earn card's own outline.
          style: OutlinedButton.styleFrom(
            backgroundColor: ready ? AppColors.primaryStart : null,
            foregroundColor: Colors.white,
            disabledForegroundColor: AppColors.textSecondary,
            side: BorderSide(
              color: ready ? AppColors.primaryStart : AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            ready
                ? claimCreditsLabel(status.credits, status.intervalDays)
                : nextClaimLabel(left),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
