import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_build.dart';
import '../logic/effects/effect_preview_layout.dart';
import '../logic/tile_preview_store.dart';
import '../logic/transitions/transition_preview_frames.dart';

/// What a kept tile drawing is made of, beside the build that drew it: the
/// transitions' frame count and size and the effects' atlas layout. A change
/// to any of these — Dart alone, so no new install to move the build — still
/// names a new folder, rather than playing old drawings in a new layout.
const String kTilePreviewFormat =
    't${kTransitionPreviewFrameCount}x${kTransitionPreviewWidth}x'
    '${kTransitionPreviewHeight}_e${kEffectPreviewFrames}x'
    '${kEffectPreviewCellWidth}x${kEffectPreviewCellHeight}c'
    '$kEffectPreviewColumns';

/// The Transitions and Effects sheets' kept tile drawings — one store for the
/// app's session, opened by the editor before either sheet can be, so a tile
/// drawn on an earlier launch is known to be on the phone the moment its
/// sheet opens. A test overrides it.
final tilePreviewStoreProvider = Provider<TilePreviewStore>(
  (ref) => TilePreviewStore(
    version: () async {
      final build = await appBuildStamp();
      return build == null ? null : '${build}_$kTilePreviewFormat';
    },
  ),
);
