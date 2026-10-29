import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../account/logic/account_copy.dart';
import '../../../account/models/account_models.dart';
import '../../services/caption_pipeline.dart';
import '../../services/caption_run.dart';
import 'caption_sheet_parts.dart';

/// Runs [pipeline] and says where it is. Pops the caption drafts on success.
///
/// It holds the editor on purpose: the audio is a snapshot of the timeline,
/// and a clip moved while the server listens would misplace every later word.
/// Any way the sheet closes before the words land — Cancel, a tap outside,
/// Back — stops the run.
class CaptionProgressSheet extends StatefulWidget {
  const CaptionProgressSheet({
    super.key,
    required this.pipeline,
    required this.request,
    this.earnCredits,
  });

  final CaptionPipeline pipeline;
  final CaptionRequest request;

  /// The ways to earn the difference, under the shortfall line. It reports
  /// the server's new balance through `onEarned`.
  final Widget Function(
    CreditQuote quote,
    void Function(int balance) onEarned,
  )? earnCredits;

  @override
  State<CaptionProgressSheet> createState() => _CaptionProgressSheetState();
}

class _CaptionProgressSheetState extends State<CaptionProgressSheet> {
  late final CaptionRun _run = CaptionRun(
    pipeline: widget.pipeline,
    request: widget.request,
  );
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    // The run holds the app while the sheet is open: closing the sheet stops
    // it, so a tap on the home screen widget only brings the app forward.
    _run
      ..addListener(_changed)
      ..start();
  }

  @override
  void dispose() {
    _run
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    final drafts = _run.drafts;
    if (drafts != null) {
      if (!_popped && mounted) {
        _popped = true;
        Navigator.of(context).pop(drafts);
      }
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final error = _run.error;
    final quote = _run.shortfall;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetGrabHandle()),
              const SizedBox(height: 8),
              if (error != null) ...[
                Text(
                  error,
                  key: const Key('caption_error'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SheetActionButton(
                        key: const Key('caption_close'),
                        label: 'Close',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SheetActionButton(
                        key: const Key('caption_retry'),
                        label: 'Try again',
                        filled: true,
                        onTap: _run.retry,
                      ),
                    ),
                  ],
                ),
              ] else if (quote != null) ...[
                Text(
                  shortfallLine(quote.credits, quote.balance),
                  key: const Key('caption_price'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                if (widget.earnCredits != null) ...[
                  widget.earnCredits!(quote, _run.earned),
                  const SizedBox(height: 12),
                ],
                SheetActionButton(
                  key: const Key('caption_close'),
                  label: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ] else ...[
                Text(
                  captionStageLabel(_run.stage),
                  key: const Key('caption_progress_stage'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _run.progress,
                    minHeight: 4,
                    color: AppColors.primaryStart,
                    backgroundColor: AppColors.surfaceLight,
                  ),
                ),
                const SizedBox(height: 20),
                SheetActionButton(
                  key: const Key('caption_cancel'),
                  label: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
