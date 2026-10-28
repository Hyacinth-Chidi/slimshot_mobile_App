import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';
import 'package:slimshotai/features/video_editor/providers/effect_preview_provider.dart';
import 'package:slimshotai/features/video_editor/providers/tile_preview_store_provider.dart';
import 'package:slimshotai/features/video_editor/providers/transition_preview_provider.dart';

import '../../../support/memory_tile_store.dart';

/// Both sheets keep their tiles in the one store the editor opens with.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the transitions and effects sheets read the one store', () {
    final store = MemoryTileStore();
    store.saved[TilePreviewKind.transitions]!['swirl'] = Uint8List(1);
    store.saved[TilePreviewKind.effects]!['vignette'] = Uint8List(1);
    final container = ProviderContainer(overrides: [
      tilePreviewStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);

    expect(container.read(transitionPreviewFramesProvider).isSaved('swirl'),
        isTrue);
    expect(container.read(effectPreviewAtlasesProvider).isSaved('vignette'),
        isTrue);
  });

  // A name the store would refuse leaves every tile drawn every launch, as
  // before, with nothing to say so.
  test('the folder named for a build and a format is one the store accepts',
      () {
    expect(isPlainTileName('2-1793141004000_$kTilePreviewFormat'), isTrue);
  });
}
