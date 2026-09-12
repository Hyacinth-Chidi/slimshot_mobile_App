import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

import '../logic/text_animation_catalog.dart';
import '../logic/text_overlay_geometry.dart';
import '../logic/timeline/video_editor_timeline_composer.dart';
import '../models/editor_timeline.dart';
import '../models/text_overlay_model.dart';
import '../models/video_editor_state.dart';
import 'text_atlas_overlay.dart';
import 'text_overlay_rasterizer.dart';

const EventChannel _defaultEventChannel =
    EventChannel('slimshot_ai/native_timeline_preview/events');

class NativeTimelinePreviewService {
  NativeTimelinePreviewService({
    MethodChannel? methodChannel,
    EventChannel? playbackEventChannel,
    VideoEditorTimelineComposer timelineComposer =
        const VideoEditorTimelineComposer(),
  })  : _methodChannel = methodChannel ??
            const MethodChannel('slimshot_ai/native_timeline_preview'),
        _playbackEventChannel = playbackEventChannel ?? _defaultEventChannel,
        _timelineComposer = timelineComposer;

  final MethodChannel _methodChannel;
  final EventChannel _playbackEventChannel;
  final VideoEditorTimelineComposer _timelineComposer;

  Stream<NativeTimelinePreviewEvent>? _events;

  /// Shared across every service instance that uses the default channel.
  ///
  /// `receiveBroadcastStream()` opens a **new** platform subscription per call,
  /// and the platform side keeps only one `eventSink`. Two instances therefore
  /// fight: the second one's `onListen` replaces the sink, and its `onCancel`
  /// nulls it — silencing the first, which is still listening and has no way to
  /// know. That is what stopped the editor's playhead the moment the export
  /// screen was closed, while playback itself carried on perfectly.
  ///
  /// One shared stream means the platform sees a single subscription with
  /// several Dart listeners, and it is only torn down when the last one goes.
  static Stream<NativeTimelinePreviewEvent>? _sharedEvents;

  Stream<NativeTimelinePreviewEvent> get events {
    // A channel injected for a test gets its own stream; the default channel is
    // shared, because that is the one several screens listen to at once.
    if (!identical(_playbackEventChannel, _defaultEventChannel)) {
      return _events ??= _playbackEventChannel
          .receiveBroadcastStream()
          .map(NativeTimelinePreviewEvent.fromPlatformEvent);
    }

    return _sharedEvents ??= _defaultEventChannel
        .receiveBroadcastStream()
        .map(NativeTimelinePreviewEvent.fromPlatformEvent);
  }

  /// Creates the native preview texture and returns its Flutter texture id.
  ///
  /// The preview renders straight into a Flutter texture rather than a
  /// platform view, so it is composited by Flutter with no virtual display and
  /// no extra per-frame copy. Safe to call more than once — the native side
  /// returns the existing texture.
  Future<int?> initialize() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'initialize',
    );
    return (result?['textureId'] as num?)?.toInt();
  }

  Future<void> setTimeline(
    VideoEditorState state, {
    Size? previewCanvasSize,
  }) {
    final timeline = _timelineComposer.compose(
      state,
      previewCanvasSize: previewCanvasSize,
    );
    return _methodChannel.invokeMethod<void>('setTimeline', timeline.toJson());
  }

  /// Identity of everything the native engine would need to rebuild playback.
  ///
  /// The editor pushes a new timeline only when this changes, so a signature
  /// that misses a field means edits silently fail to reach the engine, and one
  /// that includes a field the engine ignores means playback restarts for no
  /// reason.
  String playbackSignature(
    VideoEditorState state, {
    Size? previewCanvasSize,
  }) {
    final timeline = _timelineComposer.compose(
      state,
      previewCanvasSize: previewCanvasSize,
    );
    return jsonEncode({
      'sourceVideoPath': timeline.sourceVideoPath,
      'durationSeconds': timeline.durationSeconds,
      'canvas': timeline.canvas.toJson(),
      'playbackClips': timeline.playbackClips
          .map((clip) => clip.toJson())
          .toList(growable: false),
      'transitions': timeline.transitions
          .map((transition) => transition.toJson())
          .toList(growable: false),
      // Overlays are deliberately absent. In the preview they are Flutter
      // widgets stacked over the canvas — the engine never draws them — so
      // putting them in the signature made every overlay add, drag or trim
      // push a whole new timeline, and the resulting player re-prepare showed
      // as the canvas flashing to the background. Export composes its own
      // timeline and is unaffected.
      'audioTracks': timeline.audioClips
          .map((clip) => clip.toJson())
          .toList(growable: false),
    });
  }

  Future<void> play() {
    return _methodChannel.invokeMethod<void>('play');
  }

  Future<void> pause() {
    return _methodChannel.invokeMethod<void>('pause');
  }

  Future<void> seek(double seconds) {
    return _methodChannel.invokeMethod<void>('seek', {'seconds': seconds});
  }

  /// Live pinch/drag transform for one clip, while the gesture is in flight.
  ///
  /// Deliberately not a timeline push: a gesture updates sixty times a second
  /// and recomposing the timeline per frame would re-prepare the players. The
  /// engine holds this as an override until the released gesture's committed
  /// values arrive with the next `setTimeline`.
  Future<void> setClipTransform({
    required String clipId,
    required double scale,
    required double offsetX,
    required double offsetY,
  }) {
    return _methodChannel.invokeMethod<void>('setClipTransform', {
      'clipId': clipId,
      'scale': scale,
      'offsetX': offsetX,
      'offsetY': offsetY,
    });
  }

  /// Tells the engine a timeline drag is in progress.
  ///
  /// While this is on, the engine coalesces the seeks the drag produces
  /// instead of flushing a decoder for each one. Must be turned off when the
  /// gesture ends, or playback stays silent — scrubbing mode drops the audio
  /// track.
  Future<void> setScrubbing(bool enabled) {
    return _methodChannel.invokeMethod<void>(
      'setScrubbing',
      {'enabled': enabled},
    );
  }

  /// Renders the timeline to [outputPath] through the preview's own renderer.
  ///
  /// The exported frame is the previewed frame: both go through the same
  /// `composite` call in `TransitionRenderer`, so transitions, letterboxing,
  /// crop, per-clip grades and the project look cannot differ between them.
  ///
  /// Progress arrives as `exportProgress` events, and a device that forces a
  /// compromise — a transition it could not run two decoders for — reports it
  /// as an `exportWarning` rather than silently producing a different file.
  ///
  /// [onWarning] carries the **Dart-side** half of that rule. The native
  /// warnings travel up the event channel, which only Kotlin can write to; a
  /// compromise decided here — a text overlay that could not take the
  /// animation-capable glyph path — has no such route, so it is handed to the
  /// caller directly. Same contract, same destination (a toast over the export
  /// screen), just the only direction that exists for a decision made before
  /// the platform call.
  Future<NativeExportResult> exportVideo(
    VideoEditorState state, {
    required String outputPath,
    Size? previewCanvasSize,
    int frameRate = 30,
    int targetShortSidePx = 1080,
    void Function(String message)? onWarning,
  }) async {
    // Text is rasterised by Flutter's own text engine and handed to the
    // native overlay pass as images — reimplementing text layout in Android
    // Canvas would drift (font metrics, stroke, shadow), and PVE cannot
    // handle photo clips at all. This is what took `pro_video_editor` off the
    // export path for text projects.
    final textRasters = await _rasterizeTextOverlays(
      state,
      previewCanvasSize,
      targetShortSidePx,
    );
    for (final warning in textRasters.warnings) {
      onWarning?.call(warning);
    }

    final timeline = _timelineComposer.compose(
      state,
      previewCanvasSize: previewCanvasSize,
      extraOverlays: textRasters.overlays,
    );

    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'exportVideo',
        {
          'timeline': timeline.toJson(),
          'outputPath': outputPath,
          'frameRate': frameRate,
          // The export's own resolution, independent of the preview canvas.
          // The preview is deliberately capped at `kMaxPreviewCanvasPx` because
          // a 4K clip previewed at 4K costs fill rate nobody can see — but an
          // export inheriting that cap would ship a 720p-maximum editor.
          'targetShortSidePx': targetShortSidePx,
        },
      );

      if (result == null) {
        throw StateError('Native export returned no result.');
      }
      return NativeExportResult.fromMap(result);
    } finally {
      for (final path in textRasters.tempFiles) {
        unawaited(() async {
          try {
            await File(path).delete();
          } catch (_) {}
        }());
      }
    }
  }

  /// Rasterised text overlays as native image-overlay entries, the temp files
  /// to delete once the export is done with them, and any degradation the user
  /// has to be told about.
  Future<
      ({
        List<EditorTimelineOverlay> overlays,
        List<String> tempFiles,
        List<String> warnings,
      })> _rasterizeTextOverlays(
    VideoEditorState state,
    Size? previewCanvasSize,
    int targetShortSidePx,
  ) async {
    final canvas = previewCanvasSize;
    if (state.textOverlays.isEmpty ||
        canvas == null ||
        canvas.width <= 0 ||
        canvas.height <= 0) {
      return (
        overlays: <EditorTimelineOverlay>[],
        tempFiles: <String>[],
        warnings: <String>[],
      );
    }

    // Raster at export density, not preview density: the canvas is preview
    // pixels (~400), the export short side is 1080+, and a 1:1 raster would
    // upscale soft.
    final rasterScale =
        (targetShortSidePx / canvas.shortestSide).clamp(1.0, 4.0).toDouble();

    final overlays = <EditorTimelineOverlay>[];
    final tempFiles = <String>[];
    final warnings = <String>[];

    for (final text in state.textOverlays) {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: text,
        canvasSize: canvas,
        rasterScale: rasterScale,
      );

      // The atlas is the animation-capable path, and it is preferred wherever
      // it can draw the overlay faithfully. Two cases fall back to the flat
      // raster instead:
      //
      // 1. No atlas, or an empty one — text too large to pack inside the
      //    4096px texture limit even at floor density.
      // 2. Text with a background box. The native glyph pass draws letters
      //    only, so a background would simply vanish; backgrounds keep the
      //    flat raster until the background quad lands.
      //
      // Both used to be silent, because the flat path produced the same file
      // the atlas did. **That is no longer true**: the preview now animates
      // per character from the catalog, and the flat raster can only carry the
      // image overlay's whole-box animation. So a fallback is a real
      // divergence between the canvas and the file, and the degrade-loudly
      // rule applies — see [textFallbackWarning].
      final RasterizedTextAtlas? usableAtlas = atlas != null &&
              atlas.glyphs.isNotEmpty &&
              atlas.backgroundRect == null
          ? atlas
          : null;
      if (usableAtlas == null) {
        final warning = textFallbackWarning(
          text,
          hasBackground: atlas?.backgroundRect != null,
        );
        if (warning != null) warnings.add(warning);
      }

      final String pngPath;
      final Size boxPxSize;
      final List<EditorTimelineGlyph>? glyphs;
      if (usableAtlas != null) {
        pngPath = usableAtlas.pngPath;
        boxPxSize = usableAtlas.canvasPxSize;
        glyphs = glyphsForAtlas(usableAtlas);
      } else {
        // The atlas PNG, if one was written, is still on disk — register it
        // for deletion even though it is not used, or an unusable atlas leaks
        // a file per export.
        if (atlas != null) tempFiles.add(atlas.pngPath);
        final flat = await TextOverlayRasterizer.rasterize(
          overlay: text,
          canvasSize: canvas,
          rasterScale: rasterScale,
        );
        if (flat == null) continue;
        pngPath = flat.pngPath;
        boxPxSize = flat.canvasPxSize;
        glyphs = null;
      }
      tempFiles.add(pngPath);

      // The layer's own placement, in canvas fractions: the box centre is the
      // canvas centre plus the (clamped) offset — the same helper the layer
      // positions its widget with.
      final renderScale = textOverlayRenderScale(text, canvas);
      final center = textOverlayCenter(text, canvas, renderScale);

      // The two raster paths need different boxes — see `textOverlayBoxPx`.
      // The flat path contain-fits the PNG and so takes a pixel square; the
      // glyph path multiplies each cell's fraction by the box directly and so
      // takes the true text box. Sending the square down the glyph path
      // stretched every exported text vertically by the box's own aspect.
      final fitBox = textOverlayBoxPx(boxPxSize, usingAtlas: usableAtlas != null);
      final boxDivW = boxPxSize.width == 0 ? 1.0 : boxPxSize.width;
      final boxDivH = boxPxSize.height == 0 ? 1.0 : boxPxSize.height;

      overlays.add(
        EditorTimelineOverlay(
          id: 'text_${text.id}',
          kind: glyphs == null ? 'image' : 'text',
          path: pngPath,
          glyphs: glyphs,
          backgroundLeft: (usableAtlas?.backgroundRect?.left ?? 0) / boxDivW,
          backgroundTop: (usableAtlas?.backgroundRect?.top ?? 0) / boxDivH,
          backgroundRight: (usableAtlas?.backgroundRect?.right ?? 0) / boxDivW,
          backgroundBottom:
              (usableAtlas?.backgroundRect?.bottom ?? 0) / boxDivH,
          backgroundRadius: (usableAtlas?.borderRadius ?? 0) / boxDivW,
          centerX: center.dx / canvas.width,
          centerY: center.dy / canvas.height,
          boxWidth: fitBox.width / canvas.width,
          boxHeight: fitBox.height / canvas.height,
          scale: text.scale,
          rotation: text.rotation,
          opacity: 1.0,
          startSeconds: text.startTime.inMilliseconds / 1000.0,
          endSeconds: text.endTime.inMilliseconds / 1000.0,
          // Above every image/video overlay, matching the preview's stacking
          // where the text layer sits on top.
          laneIndex: 1000 + text.laneIndex,
          // flutter_animate slides by the widget's own size, not the image
          // overlays' fixed 200px, so the travel is the raster's own box.
          slideOffsetX: boxPxSize.width / canvas.width,
          slideOffsetY: boxPxSize.height / canvas.height,
          // **Two different vocabularies, chosen by which path draws.**
          //
          // The glyph path resolves ids through the catalog
          // (`TextAnimationCurves.resolveAnimationId`), which knows the legacy
          // names and resolves them *by slot*; it must receive the id as the
          // model stores it. The flat-raster fallback draws through the image
          // overlay's own `stateAt`, whose arms are the older vocabulary with
          // no legacy names in them at all — so that path still needs the
          // translation. Sending either one down the other's route is a
          // silently wrong animation, not a missing one.
          animationIn: glyphs == null
              ? _mapTextAnimation(text.inAnimation, isOut: false)
              : _catalogTextAnimation(text.inAnimation),
          animationOut: glyphs == null
              ? _mapTextAnimation(text.outAnimation, isOut: true)
              : _catalogTextAnimation(text.outAnimation),
          // A loop has no image-overlay equivalent, so the fallback cannot draw
          // one; sending it anyway would be read by `stateAt`'s default arm as
          // nothing, but stating the asymmetry is clearer than relying on that.
          animationLoop:
              glyphs == null ? null : _catalogTextAnimation(text.loopAnimation),
          // Speeds, not durations. Native resolves the window lengths itself
          // from the catalog, the glyph count and the speed — a staggered
          // animation's length depends on how many characters there are, which
          // the composer would otherwise have to recompute and keep in step
          // across the boundary.
          speedIn: text.animationInDuration,
          speedOut: text.animationOutDuration,
          speedLoop: text.loopSpeed,
          // The flat path is still timed here, because the image-overlay
          // animation it takes has no catalog duration to resolve. 0.5s is what
          // the preview's flutter_animate chain actually plays.
          animationInSeconds: 0.5,
          animationOutSeconds: 0.5,
        ),
      );
    }
    return (overlays: overlays, tempFiles: tempFiles, warnings: warnings);
  }

  /// A stored animation id on its way to the **glyph** path, which resolves it
  /// through the catalog on the Kotlin side.
  ///
  /// Deliberately no translation: `TextAnimationCurves.resolveAnimationId`
  /// holds the legacy tables and applies them **by slot**, which is the only
  /// place that mapping may live — a second copy here would be one more thing
  /// to keep in step across a boundary nothing type-checks. All this does is
  /// spell `'none'` as null, which is what the contract's nullable field means.
  String? _catalogTextAnimation(String name) {
    if (name.isEmpty || name == 'none') return null;
    return name;
  }

  /// Text animation names → the **image overlay's** animation names, for the
  /// flat-raster fallback only.
  ///
  /// That path is drawn by `NativeTimelineOverlay.stateAt`, whose arms are the
  /// older, smaller vocabulary — it has no `'fade'` or `'scale'` arm, so a
  /// legacy id must be translated before it arrives or it silently animates
  /// nothing. The glyph path goes through [_catalogTextAnimation] instead.
  ///
  /// It maps exactly what `text_overlay_layer.dart` actually plays. The layer
  /// has no out-variant for the bare slide names, so those export as no
  /// animation — parity with the preview, not with what the name suggests.
  ///
  /// **Its `'scale'` out-mapping does not match the catalog's**, and the
  /// difference is real rather than cosmetic: this sends `'scale'` to
  /// `zoom_out_out` (swell to 2×) where the catalog resolves it to
  /// `zoom_in_out` (shrink to nothing), which is what the layer's
  /// `scaleXY(end: 0)` arm draws. The catalog is right. This is left as it is
  /// because it is the behaviour the flat path has shipped, and the flat path
  /// is scheduled to start warning and then to go away; changing it here would
  /// alter existing exports for the one case in the one path that is on its way
  /// out. Fix it by deleting the fallback, not by editing this table.
  String? _mapTextAnimation(String name, {required bool isOut}) {
    if (name == 'none' || name.isEmpty) return null;
    if (!isOut) {
      return switch (name) {
        'fade' || 'fade_in' => 'fade_in',
        'scale' || 'zoom_in' => 'zoom_in',
        'zoom_out' => 'zoom_out',
        'slide_up' || 'slide_down' || 'slide_left' || 'slide_right' => name,
        _ => null,
      };
    }
    return switch (name) {
      'fade' || 'fade_out' => 'fade_out',
      // **These names mean the opposite of what the catalog's do**, and the
      // collision is a live trap: this function targets the *image overlay*
      // vocabulary in `NativeTimelineOverlay.stateAt`, where `zoom_in_out`
      // scales by `(1 + p)` — it **grows** — and `zoom_out_out` by `(1 - p)`,
      // which **shrinks**. The text catalog reads them the other way round.
      //
      // So `'scale'` belongs on `zoom_out_out` here: the preview layer draws
      // it as `scaleXY(end: 0)`, shrinking away, and on this path only
      // `zoom_out_out` shrinks. Checking the name against the text layer or
      // the catalog and "correcting" it inverts the animation — a mistake
      // already made once against this exact line.
      'scale' || 'zoom_out_out' => 'zoom_out_out',
      'zoom_in_out' => 'zoom_in_out',
      'slide_up_out' ||
      'slide_down_out' ||
      'slide_left_out' ||
      'slide_right_out' =>
        name,
      _ => null,
    };
  }

  Future<void> cancelExport() {
    return _methodChannel.invokeMethod<void>('cancelExport');
  }

  /// Asks the device what its codecs will actually do for an export.
  ///
  /// Export holds two decoders and an encoder at once, and low-end parts limit
  /// concurrent codec instances — so this is the one constraint that can change
  /// the shape of the export pipeline rather than just its settings. Call it
  /// with the preview loaded, so the encoder is created while playback already
  /// holds its decoders.
  Future<Map<String, dynamic>?> probeExportCapabilities(Size canvasSize) {
    return _methodChannel.invokeMapMethod<String, dynamic>(
      'probeExportCapabilities',
      {
        'width': canvasSize.width.round(),
        'height': canvasSize.height.round(),
      },
    );
  }

  Future<void> setVolume(double volume) {
    return _methodChannel.invokeMethod<void>('setVolume', {'volume': volume});
  }

  Future<void> dispose() {
    return _methodChannel.invokeMethod<void>('dispose');
  }

}

/// What to tell the user when [overlay] could not take the glyph-atlas path,
/// or null when there is nothing to tell them.
///
/// **The warning is about the animation, not about the fallback.** The flat
/// raster draws the same letters in the same place; what it cannot do is move
/// them one at a time, because it is a single image and the native pass only
/// knows how to animate a whole quad. So a text with no animation set is not
/// degraded at all and must stay silent — warning there would train the user to
/// dismiss a message that usually means nothing.
///
/// "Has an animation" is decided by **slot resolution**, not by the strings
/// being non-`'none'`. A legacy in-only id sitting in `outAnimation` resolves to
/// nothing at all (the old widget layer played no out-animation for one), so
/// such an overlay animates in neither path and has lost nothing. Reading the
/// raw fields would warn about it every export.
///
/// [hasBackground] separates the two fallback causes so the message names the
/// one the user can actually act on — removing a background box is a choice they
/// can make; an atlas overflowing the texture limit is not.
String? textFallbackWarning(
  TextOverlayModel overlay, {
  required bool hasBackground,
}) {
  final animates = resolveTextAnimation(
            overlay.inAnimation,
            TextAnimationCategory.inAnim,
          ) !=
          null ||
      resolveTextAnimation(
            overlay.outAnimation,
            TextAnimationCategory.outAnim,
          ) !=
          null ||
      resolveTextAnimation(
            overlay.loopAnimation,
            TextAnimationCategory.loop,
          ) !=
          null;
  if (!animates) return null;

  // A short label rather than the whole string: a caption can be a paragraph,
  // and a toast that runs off the screen tells the user less than one that
  // fits.
  final label = _textOverlayLabel(overlay);
  return hasBackground
      ? 'Text "$label" has a background box, so its animation exports as a '
          'whole-block effect rather than character by character.'
      : 'Text "$label" is too large to animate character by character; it '
          'exports as a whole-block effect.';
}

/// The first few characters of an overlay's text, for a message the user has
/// to match against something on their timeline.
String _textOverlayLabel(TextOverlayModel overlay) {
  final trimmed = overlay.text.trim();
  if (trimmed.isEmpty) return overlay.id;
  final firstLine = trimmed.split('\n').first;
  return firstLine.characters.length <= 24
      ? firstLine
      : '${firstLine.characters.take(24)}…';
}

/// What a finished native export produced.
class NativeExportResult {
  const NativeExportResult({
    required this.outputPath,
    required this.durationSeconds,
    required this.frameCount,
    required this.degradedTransitions,
  });

  final String outputPath;
  final double durationSeconds;
  final int frameCount;

  /// Transitions this device could not render, exported as a hard cut.
  ///
  /// Non-zero means the file legitimately differs from the preview, and the
  /// user has to be told — a success message over a file that quietly lost its
  /// transitions is exactly the "success before the result is usable" failure.
  final int degradedTransitions;

  bool get isExact => degradedTransitions == 0;

  factory NativeExportResult.fromMap(Map<String, dynamic> map) {
    return NativeExportResult(
      outputPath: map['outputPath'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      frameCount: (map['frameCount'] as num?)?.toInt() ?? 0,
      degradedTransitions: (map['degradedTransitions'] as num?)?.toInt() ?? 0,
    );
  }
}

class NativeTimelinePreviewEvent {
  const NativeTimelinePreviewEvent({
    required this.type,
    this.positionSeconds,
    this.isReady,
    this.message,
    this.progress,
  });

  final String type;
  final double? positionSeconds;
  final bool? isReady;
  final String? message;

  /// Export completion, `0..1`, on `exportProgress` events.
  final double? progress;

  factory NativeTimelinePreviewEvent.fromPlatformEvent(dynamic event) {
    if (event is! Map) {
      return NativeTimelinePreviewEvent(
        type: 'unknown',
        message: event?.toString(),
      );
    }

    return NativeTimelinePreviewEvent(
      type: event['type'] as String? ?? 'unknown',
      positionSeconds: (event['positionSeconds'] as num?)?.toDouble(),
      isReady: event['isReady'] as bool?,
      message: event['message'] as String?,
      progress: (event['progress'] as num?)?.toDouble(),
    );
  }
}

