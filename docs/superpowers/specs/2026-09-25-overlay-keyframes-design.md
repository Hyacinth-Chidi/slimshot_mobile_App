# Overlay Keyframes — Design

**Status:** awaiting approval. Nothing in this document is built.

Keyframes for text, photo overlays and video overlays, on position, scale, rotation and
opacity, reusing the clip keyframe system. The clip design
(`2026-09-15-clip-keyframes-design.md`) left overlays out of scope; this brings them in with
the same rules, so a user learns keyframes once.

## What the user sees and does

It is CapCut's model, and it is what clips already do here:

1. **With a text, photo or video overlay selected, the diamond button appears in the playback
   bar**, where it appears for a clip. With nothing selected it is not there.
2. **Tapping it places a diamond on the overlay's own bar in its lane** — vertically centred,
   at the playhead. Not on the clip's filmstrip: an overlay's keyframe is a moment of the
   overlay, whose span can start mid-clip and run onto the next one, so the clip's thumbnail is
   the wrong place and an ambiguous one.
3. **When the playhead sits on a diamond the button becomes a minus** — tap to remove. Tapping
   a diamond moves the playhead onto it; long-press-drag moves the diamond.
4. **The curve icon opens the existing easing sheet** for the segment at the playhead.
5. **One diamond holds every property**: position, scale, rotation and opacity at that moment.
6. **Diamonds show only on the selected item.** Select a clip: its diamonds. Select a text: the
   text's, the clip's hidden. Exactly what clips do today when deselected.
7. **Any change to an overlay with diamonds writes at the playhead** — moving, pinching,
   rotating, the Opacity panel — placing a diamond first if there is none there. With no
   diamonds, edits are static, as today.
8. **Preset in/out/loop animations still play**, on top of the keyframed motion.
9. **Text gains Opacity** on its menu, beside Style, opening the same Opacity panel the
   overlays use.

Items with keyframes can overlap in time freely; a clip, a video overlay and a text may each
carry keyframes over the same seconds.

## Data model

**Keyframes ride beside the existing fields.** `position`, `scale`, `rotation` and `opacity`
on `TextOverlayModel`, `ImageOverlayModel` and `VideoOverlayModel` are unchanged and are the
**base values**. Each model gains one field:

```
keyframes: OverlayKeyframes   // by OverlayProperty {x, y, scale, rotation, opacity}: List<Keyframe>
```

Empty means no keyframes, which is every overlay that exists today. A property resolves at a
moment as `AnimatableDouble(baseValue: <plain field>, keyframes: <track>).resolveAt(progress)`
— the clips' `AnimatableDouble`, Dart and Kotlin, pinned by the existing fixture. There is no
second copy of interpolation or easing. Overlays use no envelope: keyframes, else base.

`TextOverlayModel` gains `opacity` (double, default 1.0).

**Progress is overlay-relative**, `(t − start) / (end − start)`, 0..1 across the overlay's own
span, as a clip's is across the clip. Trimming or extending the overlay stretches its motion
with it.

**Units.** A keyframe's value is in the units of the field it animates: position in
preview-canvas pixels as today, scale a multiplier, rotation radians, opacity 0..1. The
composer converts base and keyframes to canvas fractions at the same boundary, so the
conversion is one rule and a keyframed overlay renders identically on any device.

**One diamond, every property.** A diamond at `p` means every property carries a keyframe at
`p`, captured at its resolved value, so placing one changes nothing on screen. The diamonds an
overlay shows are the union of its tracks' progresses. Removing the last diamond writes each
property's value back as the base. A fresh keyframe is `linear`.

**Templates.** A template is the look; keyframes are placement. `TextTemplate.restyle` never
touches keyframes. Its `scale` writes the base, which keyframes override where they exist.

**Not keyframed:** volume, mask, chroma key, box width, lane, colour.

## The shared keyframe core

The pure functions in `logic/animation/clip_keyframes.dart` — capture, remove, move, nearest,
curve target, set curve/easing — are generalised into `logic/animation/keyframe_core.dart`,
parameterised over a set of named `AnimatableDouble` parameters (a property list, a reader and
a writer). `clip_keyframes.dart` becomes thin wrappers over the core with `ClipProperty`, so
every existing clip test passes unchanged; `logic/animation/overlay_keyframes.dart` wraps the
same core with `OverlayProperty`, reading each parameter as the plain field plus its track and
writing back the same way. One set of rules for clips and overlays.

## Engine

**Wire.** `EditorTimelineOverlay.centerX/centerY/scale/rotation/opacity` become
`AnimatableDouble`. `toJson` writes a bare number when a parameter has no keyframes, as clips
do, so an overlay without keyframes sends byte-identical JSON to today; a test pins it.

**Kotlin.** `NativeTimelineOverlay` reads the five through `AnimatableDouble.fromWire` (number
or keyframe map, as `NativeTimelineClip` does). `stateAt(t)` resolves them at the overlay's
progress first, then applies the in/out preset multipliers on top as now; `restingState()`,
used by text with per-character animation, resolves the same way. The text glyph pass
multiplies the overlay's opacity into each glyph's alpha, so a text fade reaches the file
through the glyph path and the flat raster alike.

**Preview and export share it.** Both run `OverlayDrawBuilder` on the same
`NativeTimelineOverlay`, so interpolation happens once for canvas and file.

**Redraw.** `OverlayClock.needsRedraw` gains a case: an overlay with keyframes redraws whenever
the playhead moves inside its span. It currently redraws only on appear/disappear and inside a
preset window; a keyframed overlay moves every frame.

**Text in the preview** is painted by Flutter, so `text_overlay_layer.dart` resolves position,
scale, rotation and opacity through the Dart `AnimatableDouble` at the playhead and applies them
through the transforms it already has, plus an `Opacity` wrapper. Photo and video overlays are
drawn by the engine; their Flutter layers place only the selection handles, resolved the same
way so the frame sits where the picture is.

No new fixture is needed for the resolvers — both are the existing pinned ports. A small
overlay fixture pins that Dart and Kotlin turn the same overlay into the same placement at
sampled progresses.

## UI

**One target.** `VideoEditorState.keyframeTarget`: the selected item (clip, text, photo, video)
with its progress at the playhead, or null when nothing is selected or the playhead is outside
the item's span (never clamped — the clip rule). The playback bar (button shown, plus/minus,
curve lit) and the notifier (`addKeyframeAtPlayhead`, `removeKeyframeAtPlayhead`,
`setKeyframeCurve`, `moveKeyframe`) read this one target and dispatch on its kind. Clips work
through it unchanged.

**Diamonds on the bar.** `LaneKeyframeDiamonds` draws the selected overlay's diamonds on its
bar, positioned by the bar's own geometry so they follow trims and lane moves. Same drawing and
gestures as `ClipKeyframeDiamonds`: tap seeks, long-press-drag moves (playhead rides along, one
undo step, stops short of a neighbour). Hit tolerance is `kKeyframeHitSeconds` converted through
the overlay's duration.

**The edit rule.** `_writeOverlayValue` mirrors `_writeClipValue`: no diamonds → base;
playhead on a diamond → that keyframe; between → capture a diamond, then write. The canvas
gestures (drag, pinch, two-finger rotate, corner handle, width pills' centre shift) and the
Opacity panel route through it. A gesture snapshots undo once at its start and writes live per
frame, as now.

**Copy and split.** A duplicate copies keyframes. `splitVideoOverlay` pins a keyframe at the cut
and rescales each half into its own 0..1, as `_cutSegments` does for clips.

## Persistence

Each overlay's `toJson` writes `keyframes` only when non-empty; text writes `opacity` always and
reads it back as 1.0 when absent. Old drafts load unchanged. A hand-edited draft with an unknown
property name is ignored; an unknown curve name reads as `linear`, as clips do.

## Undo and tools

A diamond placed, removed, moved or eased is one undo step; a gesture is one. The Opacity
panel's ✕ restores the overlay whole through the existing tool-discard record, keyframes
included.

## Testing

- Placing a diamond never changes the picture, at several positions and with existing diamonds.
- Removing the last diamond writes its value back as the base.
- Wire byte-identical for an un-keyframed overlay; a keyframed one sends the map.
- Dart and Kotlin resolve the same overlay to the same placement (fixture + Kotlin test).
- Redraw: keyframed overlay redraws on a playhead move inside its span; un-keyframed does not.
- The edit rule's three cases for a text, a photo and a video overlay.
- Diamonds land where the bar's geometry says, through a trim and a lane move.
- Split rescales and pins at the cut; duplicate copies.
- Every existing clip keyframe test passes unchanged through the core extraction.

**Device verification** (Kotlin changes): a text gliding and fading, a photo overlay growing, a
video overlay spinning — each in preview then export — and one project with clip and overlay
keyframes over the same seconds.

## Out of scope

Colour keyframes on text (the next feature, together with the export's colour pass and the two
hidden colour animations); volume keyframes on video overlays; faded diamonds for unselected
items; a custom easing graph; keyframing the mask or chroma key.
