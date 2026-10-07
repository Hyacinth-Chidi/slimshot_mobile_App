import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/services/slimshot_api.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/widgets/colour_field_backdrop.dart';
import '../../../core/widgets/frosted_glass.dart';
import '../logic/account_copy.dart';
import '../models/account_models.dart';
import '../providers/account_providers.dart';
import '../widgets/earn_credits_block.dart';

/// Opens Credits on the root navigator — above the app shell's floating
/// nav, from a tab.
void openCreditsScreen(BuildContext context) {
  unawaited(Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => const CreditsScreen()),
  ));
}

/// The balance, the ways to earn, and the history.
class CreditsScreen extends ConsumerStatefulWidget {
  const CreditsScreen({super.key});

  @override
  ConsumerState<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends ConsumerState<CreditsScreen> {
  final List<CreditEntry> _entries = [];
  String? _next;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // The balance and today's ads as the server has them now: a reward
    // that landed while the screen was closed shows on opening.
    unawaited(ref.read(accountProvider.notifier).refresh());
  }

  /// The first page until one has loaded, then the page after [_next]. A
  /// failed page leaves [_next] alone and offers Try again on the same
  /// button.
  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(accountServiceProvider)
          .history(cursor: _loaded ? _next : null);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.items);
        _next = page.nextCursor;
        _loaded = true;
      });
    } on SlimshotApiException catch (e) {
      if (mounted) setState(() => _error = accountErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(accountProvider).user?.creditBalance ?? 0;
    final error = _error;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(child: ColourFieldBackdrop()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        LucideIcons.arrowLeft,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Credits',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.coins,
                      color: AppColors.credit,
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$balance',
                      key: const Key('credits_balance'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FrostedGlass(
                  borderRadius: BorderRadius.circular(24),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: EarnCreditsBlock(),
                  ),
                ),
                const SizedBox(height: 28),
                for (final entry in _entries) _HistoryRow(entry),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                if (_next != null || error != null)
                  TextButton(
                    key: const Key('credits_more'),
                    onPressed: _loading ? null : _load,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: Text(error != null ? 'Try again' : 'More'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.entry);

  final CreditEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creditHistoryLabel(entry.type),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeago.format(entry.createdAt),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              creditAmountLabel(entry.amount),
              style: TextStyle(
                color: entry.amount >= 0
                    ? AppColors.success
                    : AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
