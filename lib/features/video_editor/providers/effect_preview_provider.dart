import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/effects/effect_preview_atlases.dart';

/// What draws an effect tile's atlas. Answers busy until the engine is wired
/// to it; a test overrides it.
final effectPreviewRendererProvider = Provider<EffectPreviewRenderer>(
  (ref) => (_) async => const EffectPreviewBusy(),
);

/// The Effects sheet's preview atlases, kept for the app's session — not
/// autoDispose, so reopening the sheet shows them at once instead of drawing
/// them again. Dropped when the system reports memory pressure: tiles on
/// screen keep the pictures they decoded, and the rest are drawn again when
/// next asked.
final effectPreviewAtlasesProvider = Provider<EffectPreviewAtlases>((ref) {
  final atlases = EffectPreviewAtlases(ref.watch(effectPreviewRendererProvider));
  final observer = _MemoryPressure(atlases.clear);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  return atlases;
});

class _MemoryPressure with WidgetsBindingObserver {
  _MemoryPressure(this._onPressure);

  final VoidCallback _onPressure;

  @override
  void didHaveMemoryPressure() => _onPressure();
}
