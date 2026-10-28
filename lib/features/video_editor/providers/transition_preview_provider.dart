import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/transitions/transition_preview_frames.dart';
import '../services/native_timeline_preview_service.dart';
import 'tile_preview_store_provider.dart';

/// The transitions sheet's tile frames, held for the app's session — not
/// autoDispose, so reopening the sheet shows them at once instead of drawing
/// them again — and kept on the phone, so the next launch reads them back
/// rather than drawing them. Only the method channel is used, never the
/// preview's event stream, so a second service instance here cannot steal
/// its events.
final transitionPreviewFramesProvider = Provider<TransitionPreviewFrames>(
  (ref) {
    final service = NativeTimelinePreviewService();
    return TransitionPreviewFrames(
      service.renderTransitionPreview,
      store: ref.watch(tilePreviewStoreProvider),
    );
  },
);
