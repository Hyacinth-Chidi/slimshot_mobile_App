import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/slimshot_api.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../../account/logic/account_copy.dart';
import '../../../account/models/account_models.dart';
import '../../logic/speech/speech_request.dart';
import '../../logic/speech/voice_clip.dart';
import '../../services/speech_run.dart';
import '../../services/speech_service.dart';
import '../../services/voice_sample_player.dart';
import 'apply_to_all_toggle.dart';
import 'caption_sheet_parts.dart';
import 'editor_sheet.dart';

/// What the sheet keeps for the session: the last voice list, shown while a
/// new one is asked for, and the voice last chosen, chosen again.
class SpeechSheetMemory {
  List<SpeechVoice>? voices;
  String? voiceId;
}

/// Text to speech, from a selected text: the voices (a tap hears one, free),
/// Apply to all texts, and Generate. The run is shown in place — a ring and
/// Cancel, a failure's line and Try again, a shortfall with the ways to earn
/// — and its voices are handed over through [onVoices] as the sheet closes.
///
/// No title: the tool's name is the text the user just tapped.
class TextToSpeechSheet extends StatefulWidget {
  const TextToSpeechSheet({
    super.key,
    required this.loadVoices,
    required this.plan,
    required this.newRun,
    required this.samples,
    required this.onVoices,
    this.earnCredits,
    this.memory,
  });

  /// The voices offered now — asked for on every opening.
  final Future<List<SpeechVoice>> Function() loadVoices;

  /// What Generate would send, with or without Apply to all.
  final SpeechPlan Function(bool applyToAll) plan;

  final SpeechRun Function(String voiceId, SpeechReady plan) newRun;

  /// Opened and disposed by whoever opened the sheet; the sheet stops it as
  /// it closes, and when the app leaves the screen.
  final VoiceSamplePlayer samples;

  final void Function(List<VoiceClip> voices) onVoices;

  /// The ways to earn the difference, under a shortfall. It reports the
  /// server's new balance through `onEarned`.
  final Widget Function(
    CreditQuote quote,
    void Function(int balance) onEarned,
  )? earnCredits;

  final SpeechSheetMemory? memory;

  @override
  State<TextToSpeechSheet> createState() => _TextToSpeechSheetState();
}

class _TextToSpeechSheetState extends State<TextToSpeechSheet> {
  late List<SpeechVoice>? _voices = widget.memory?.voices;
  Object? _voicesError;
  late String? _voiceId = widget.memory?.voiceId;
  bool _applyToAll = false;
  SpeechRun? _run;
  bool _handedOver = false;
  int _listTurn = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: () => widget.samples.stop());
    unawaited(_loadVoices());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(widget.samples.stop());
    _run
      ?..removeListener(_runChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    final turn = ++_listTurn;
    if (_voicesError != null) setState(() => _voicesError = null);
    try {
      final voices = await widget.loadVoices();
      if (!mounted || turn != _listTurn) return;
      widget.memory?.voices = voices;
      setState(() {
        _voices = voices;
        if (!voices.any((v) => v.id == _voiceId)) {
          _voiceId = voices.isEmpty ? null : voices.first.id;
        }
      });
    } catch (error) {
      if (!mounted || turn != _listTurn) return;
      debugPrint('Voices could not be listed: $error');
      setState(() => _voicesError = error);
    }
  }

  void _tapVoice(SpeechVoice voice) {
    setState(() => _voiceId = voice.id);
    widget.memory?.voiceId = voice.id;
    if (widget.samples.playing.value == voice.sampleUrl) {
      unawaited(widget.samples.stop());
    } else {
      unawaited(widget.samples.play(voice.sampleUrl));
    }
  }

  bool get _voicesReady =>
      _voicesError == null && (_voices?.isNotEmpty ?? false) && _voiceId != null;

  void _generate() {
    final plan = widget.plan(_applyToAll);
    final voiceId = _voiceId;
    if (!_voicesReady || voiceId == null || plan is! SpeechReady) return;
    unawaited(widget.samples.stop());
    final run = widget.newRun(voiceId, plan)..addListener(_runChanged);
    setState(() => _run = run);
    run.start();
  }

  void _runChanged() {
    final voices = _run?.voices;
    if (voices != null) {
      if (!_handedOver) {
        _handedOver = true;
        widget.onVoices(voices);
        if (mounted) Navigator.of(context).pop();
      }
      return;
    }
    if (mounted) setState(() {});
  }

  /// Cancel, or Back from a failure or a shortfall: the run stops and the
  /// voices come back. After a failure the list is asked for again — a voice
  /// switched off in the meantime is what "Choose another" means.
  void _leaveRun({bool reloadVoices = false}) {
    final run = _run;
    if (run == null) return;
    run
      ..removeListener(_runChanged)
      ..dispose();
    setState(() => _run = null);
    if (reloadVoices) unawaited(_loadVoices());
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    return CaptionSheetFrame(
      maxHeight: MediaQuery.sizeOf(context).height * kEditorSheetPreviewFraction,
      children: run == null ? _picker() : [_runView(run)],
    );
  }

  List<Widget> _picker() {
    final plan = widget.plan(_applyToAll);
    final message = speechPlanMessage(plan);
    final canGenerate = _voicesReady && plan is SpeechReady;
    return [
      Flexible(child: _voicesArea()),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: ApplyToAllToggle(
          key: const Key('speech_apply_all'),
          label: 'Apply to all texts',
          value: _applyToAll,
          onChanged: (value) => setState(() => _applyToAll = value),
        ),
      ),
      if (message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            message,
            key: const Key('speech_plan_message'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Opacity(
          opacity: canGenerate ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !canGenerate,
            child: SheetActionButton(
              key: const Key('speech_generate'),
              label: 'Generate',
              filled: true,
              onTap: _generate,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _voicesArea() {
    final error = _voicesError;
    if (error != null) {
      return _VoicesNotice(
        line: error is SlimshotApiException &&
                error.code == SlimshotApiException.network
            ? 'No internet connection.'
            : 'Text to speech is unavailable right now.',
        onRetry: () => unawaited(_loadVoices()),
      );
    }
    final voices = _voices;
    if (voices == null) {
      return const SizedBox(
        height: 112,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primaryStart,
            ),
          ),
        ),
      );
    }
    if (voices.isEmpty) {
      return const _VoicesNotice(line: 'Text to speech is unavailable right now.');
    }
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 52,
      ),
      itemCount: voices.length,
      itemBuilder: (_, i) => _VoiceTile(
        voice: voices[i],
        selected: voices[i].id == _voiceId,
        playing: widget.samples.playing,
        onTap: () => _tapVoice(voices[i]),
      ),
    );
  }

  Widget _runView(SpeechRun run) {
    final error = run.error;
    final quote = run.shortfall;
    const line = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Text(
              error,
              key: const Key('speech_error'),
              textAlign: TextAlign.center,
              style: line.copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SheetActionButton(
                    key: const Key('speech_back'),
                    label: 'Back',
                    onTap: () => _leaveRun(reloadVoices: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SheetActionButton(
                    key: const Key('speech_retry'),
                    label: 'Try again',
                    filled: true,
                    onTap: run.retry,
                  ),
                ),
              ],
            ),
          ] else if (quote != null) ...[
            Text(
              shortfallLine(quote.credits, quote.balance),
              key: const Key('speech_price'),
              textAlign: TextAlign.center,
              style: line.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 20),
            if (widget.earnCredits != null) ...[
              widget.earnCredits!(quote, run.earned),
              const SizedBox(height: 12),
            ],
            SheetActionButton(
              key: const Key('speech_back'),
              label: 'Back',
              onTap: _leaveRun,
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primaryStart,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              speechStageLabel(run.stage, count: run.plan.targets.length),
              key: const Key('speech_stage'),
              textAlign: TextAlign.center,
              style: line,
            ),
            const SizedBox(height: 20),
            SheetActionButton(
              key: const Key('speech_cancel'),
              label: 'Cancel',
              onTap: _leaveRun,
            ),
          ],
        ],
      ),
    );
  }
}

/// One voice: its name, and play or stop for its sample. A tap chooses it
/// and plays it; a tap on the one playing stops it.
class _VoiceTile extends StatelessWidget {
  const _VoiceTile({
    required this.voice,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  final SpeechVoice voice;
  final bool selected;
  final ValueListenable<String?> playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: playing,
      builder: (context, url, _) {
        final isPlaying = url == voice.sampleUrl;
        return Semantics(
          button: true,
          selected: selected,
          label: isPlaying ? '${voice.label}, playing' : voice.label,
          excludeSemantics: true,
          child: GestureDetector(
            key: Key('speech_voice_${voice.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.highlight : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primaryStart : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isPlaying ? LucideIcons.square : LucideIcons.play,
                    size: 16,
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      voice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Why there are no voices to choose, and Retry where trying again can help.
class _VoicesNotice extends StatelessWidget {
  const _VoicesNotice({required this.line, this.onRetry});

  final String line;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            line,
            key: const Key('speech_voices_error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              key: const Key('speech_voices_retry'),
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryStart),
            ),
          ],
        ],
      ),
    );
  }
}
