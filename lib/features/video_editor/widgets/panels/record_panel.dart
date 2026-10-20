import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/lucide_icons.dart';
import '../../../audio_tools/record_controller.dart';

/// Recording mode's panel: one round button — record, and pause while
/// recording, with a purple ring pulsing round it — the speaker toggle for
/// hearing the video while recording, and the take's length so far.
class RecordPanel extends StatefulWidget {
  const RecordPanel({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final RecordController controller;

  /// Opens the phone's Settings, for a microphone refused for good.
  final VoidCallback onOpenSettings;

  @override
  State<RecordPanel> createState() => _RecordPanelState();
}

class _RecordPanelState extends State<RecordPanel> with SingleTickerProviderStateMixin {
  static const double _kButton = 64;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  RecordController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(RecordPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _pulse.dispose();
    super.dispose();
  }

  void _changed() {
    if (_c.phase == RecordPhase.recording) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 72,
              child: IconButton(
                key: const ValueKey('record-monitor'),
                onPressed: _c.toggleMonitor,
                icon: Icon(
                  _c.monitorMuted ? LucideIcons.volumeX : LucideIcons.volume2,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
            _button(),
            SizedBox(
              width: 72,
              child: Text(
                _clock(_c.takeLength),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        if (_c.needsSettings)
          TextButton(
            onPressed: widget.onOpenSettings,
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryStart),
            child: const Text('Open Settings'),
          ),
      ],
    );
  }

  Widget _button() {
    final phase = _c.phase;
    final Widget glyph;
    if (phase == RecordPhase.recording) {
      glyph = const Icon(
        LucideIcons.pause,
        key: ValueKey('record-glyph-pause'),
        color: AppColors.textPrimary,
        size: 26,
      );
    } else {
      glyph = Container(
        key: const ValueKey('record-glyph-record'),
        width: 26,
        height: 26,
        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
      );
    }

    return GestureDetector(
      key: const ValueKey('record-button'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_c.toggle()),
      child: SizedBox(
        width: _kButton + 24,
        height: _kButton + 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (phase == RecordPhase.recording)
              AnimatedBuilder(
                key: const ValueKey('record-pulse'),
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return Container(
                    width: _kButton + 20 * t,
                    height: _kButton + 20 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryStart.withValues(alpha: 0.35 * (1 - t)),
                      border: Border.all(
                        color: AppColors.primaryStart.withValues(alpha: 0.9 - 0.5 * t),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: _kButton,
              height: _kButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(color: AppColors.textPrimary, width: 3),
              ),
              child: glyph,
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(double seconds) {
    final whole = seconds.floor();
    final tenths = ((seconds - whole) * 10).floor();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}.$tenths';
  }
}
