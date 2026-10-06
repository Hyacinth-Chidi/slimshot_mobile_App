import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../account/logic/account_copy.dart';
import '../../../account/models/account_models.dart';
import '../../services/caption_errors.dart';
import '../../services/caption_pipeline.dart';
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
  });

  final CaptionPipeline pipeline;
  final CaptionRequest request;

  @override
  State<CaptionProgressSheet> createState() => _CaptionProgressSheetState();
}

class _CaptionProgressSheetState extends State<CaptionProgressSheet> {
  CaptionStage _stage = CaptionStage.preparing;
  double? _progress = 0;
  String? _error;
  bool _finished = false;

  /// The price waiting for an answer; null when none is asked.
  CreditQuote? _quote;
  Completer<bool>? _decision;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    if (!_finished) widget.pipeline.cancel();
    // Closed while the price was showing — Cancel, Back, a tap outside: no.
    final decision = _decision;
    if (decision != null && !decision.isCompleted) decision.complete(false);
    super.dispose();
  }

  Future<bool> _confirmPrice(CreditQuote quote) {
    final decision = Completer<bool>();
    setState(() {
      _quote = quote;
      _decision = decision;
    });
    return decision.future;
  }

  void _generate() {
    final decision = _decision;
    if (decision == null || decision.isCompleted) return;
    setState(() {
      _quote = null;
      _decision = null;
    });
    decision.complete(true);
  }

  Future<void> _run() async {
    try {
      final drafts = await widget.pipeline.run(
        widget.request,
        onProgress: (stage, progress) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _progress = progress;
          });
        },
        confirmPrice: _confirmPrice,
      );
      _finished = true;
      if (mounted) Navigator.of(context).pop(drafts);
    } on CaptionCancelled {
      // Closed by the user; the sheet is already on its way out.
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captionErrorMessage(error));
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _quote = null;
      _decision = null;
      _stage = CaptionStage.preparing;
      _progress = 0;
    });
    unawaited(_run());
  }

  static String _label(CaptionStage stage) => switch (stage) {
        CaptionStage.preparing => 'Preparing audio',
        CaptionStage.pricing => 'Checking price',
        CaptionStage.uploading => 'Uploading',
        CaptionStage.listening => 'Listening',
        CaptionStage.placing => 'Placing captions',
      };

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final quote = _quote;
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
                        onTap: _retry,
                      ),
                    ),
                  ],
                ),
              ] else if (quote != null) ...[
                Text(
                  quote.enough
                      ? priceLine(quote.credits, quote.balance)
                      : shortfallLine(quote.credits, quote.balance),
                  key: const Key('caption_price'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                if (quote.enough)
                  Row(
                    children: [
                      Expanded(
                        child: SheetActionButton(
                          key: const Key('caption_cancel'),
                          label: 'Cancel',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SheetActionButton(
                          key: const Key('caption_confirm'),
                          label: 'Generate',
                          filled: true,
                          onTap: _generate,
                        ),
                      ),
                    ],
                  )
                else
                  SheetActionButton(
                    key: const Key('caption_close'),
                    label: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
              ] else ...[
                Text(
                  _label(_stage),
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
                    value: _progress,
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
