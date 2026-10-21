/// An effect tile's preview: one atlas of frames the engine draws, and which
/// of them a tile shows as its loop turns.
///
/// **One image per effect, not one per frame.** A tile decodes the atlas once
/// and owns the picture, so there is one thing to free; frames decoded one by
/// one through `Image.memory` would fill Flutter's shared image cache instead.
/// Cells sit on 16-pixel boundaries so no JPEG block straddles two frames.
library;

import 'dart:ui';

import '../../models/editor_timeline.dart';
import 'effect_bar_placement.dart';
import 'effect_catalog.dart';

/// One frame's cell in the atlas, in pixels.
const int kEffectPreviewCellWidth = 160;
const int kEffectPreviewCellHeight = 144;

/// Cells per atlas row.
const int kEffectPreviewColumns = 5;

/// Frames in an atlas: frame 0 is the plain picture, frames 1–24 the bar.
const int kEffectPreviewFrames = 25;

/// How fast the bar's frames play — and how far apart in the bar they are
/// drawn, so a tile plays the effect in real time.
const int kEffectPreviewFps = 15;

/// How long a tile rests on the plain picture before the effect begins.
const double kEffectPreviewLeadSeconds = 0.4;

/// One turn of a tile's loop: the plain beat, then the bar's frames.
const Duration kEffectPreviewLoop = Duration(milliseconds: 2000);

/// The frame a tile shows at [phase] (0..1) of its loop: the plain picture
/// for the opening beat, then the bar at [kEffectPreviewFps], holding the last
/// frame.
int effectPreviewFrameAt(double phase) {
  final seconds = phase * kEffectPreviewLoop.inMilliseconds / 1000.0;
  if (seconds < kEffectPreviewLeadSeconds) return 0;
  final frame =
      1 + ((seconds - kEffectPreviewLeadSeconds) * kEffectPreviewFps).floor();
  return frame.clamp(1, kEffectPreviewFrames - 1);
}

/// Where [frame] sits in the atlas, in pixels, row by row — inset by a pixel
/// so filtering cannot reach a neighbour's edge.
Rect effectPreviewCellRect(int frame) {
  final column = frame % kEffectPreviewColumns;
  final row = frame ~/ kEffectPreviewColumns;
  return Rect.fromLTWH(
    (column * kEffectPreviewCellWidth).toDouble(),
    (row * kEffectPreviewCellHeight).toDouble(),
    kEffectPreviewCellWidth.toDouble(),
    kEffectPreviewCellHeight.toDouble(),
  ).deflate(1);
}

/// The bar a tile is drawn from: exactly what a tap on [effect] adds — three
/// seconds, the catalog's strength and envelope, its intro — so a tile cannot
/// show a look a new bar does not have.
EditorTimelineEffect effectPreviewSampleBar(VideoEffect effect) =>
    EditorTimelineEffect(
      id: 'preview_${effect.id}',
      effectId: effect.id,
      start: 0,
      end: kDefaultEffectBarSeconds,
      lane: 0,
      intensity: freshEffectIntensity(effect),
      introSeconds: effect.introSeconds,
    );
