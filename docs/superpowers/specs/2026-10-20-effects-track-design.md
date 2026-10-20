# Effects track — design

**Date:** 2026-10-20 · **Branch:** `effects-track` · **Status:** awaiting the owner's review

Roadmap Stage 6, item 16. Today every clip carries at most one effect (`VideoSegment.effectId`).
This moves effects onto the timeline as **bars on the lanes**, the way text and audio already
live there, and moves the 39 existing effects with them.

Marked **(owner)** where the owner decided, **(proposed, accepted)** where I proposed it and the
owner agreed, **(my call)** where I decided and the owner has not yet ruled, and
**(builder's call)** where the detail is left to whoever implements it.

## Intent

An effect is something that happens *at a moment of the video* — a blur over three seconds, a
glitch on the drop — not a property of whichever clip happens to be there. Editors coming from
CapCut expect to drop an effect at the playhead, see it as a bar, drag it, stretch it and stack a
second one on top. Owning one effect per clip can do none of that: it cannot span a cut, cannot
stack, cannot start mid-clip, and through a transition only the outgoing clip's effect shows.

**"Do it perfectly" (owner):** what the canvas shows, the exported file shows; old projects look
the same after the update; nothing hitches when playback crosses the edge of a bar.

## Goals

1. **Effects** on the main menu opens the effects sheet; a tap drops a bar at the playhead.
2. A bar is an ordinary lane item: selected by a tap, moved, trimmed, changed lane, snapped,
   copied, deleted — each gesture one undo step, through the existing lane rules.
3. Bars **stack**: every bar under the playhead applies.
4. A bar applies to the **main video** — the clips and the background, under every photo, video
   overlay, text and emoji, which stay sharp on top. **(owner)**
5. Intensity per bar, keyframable with the same diamonds, plus button and easing sheet as clips
   and overlays.
6. Preview and export draw a bar identically, through one shared definition.
7. Projects saved before this open looking the same: each clip's effect becomes a bar.

## Non-goals (this version)

- **Whole frame** (an effect over everything, text included) and **one overlay** (an effect on a
  single photo or video on top). **(owner)** Whole frame needs the preview to draw text in the
  engine — today Flutter paints text above the engine's picture, so an effect cannot reach it on
  screen. It is the next step, together with that move. One overlay comes after.
- Splitting a bar (Copy covers the need). **(my call)**
- Effects that follow a clip when the clip is moved or trimmed — bars stay in timeline time, as in
  CapCut. **(my call)**
- Parameters beyond intensity; moving previews on the effect tiles.

## Anti-goals — failures even if it "works"

- **The file differs from the canvas** — a bar drawn on one and not the other, or at a different
  strength or moment.
- **A hitch or a flash when playback crosses a bar's edge.** Linking a GL program in the render
  path is exactly that (see `TransitionShaders.warmUpShaders`).
- **An old project that looks different** after the update.
- **An effect placed and silently not drawn** (the pass budget, below).
- **Undo that walks a drag back frame by frame**, or an action that takes an undo step and
  changes nothing.
- **A bar that cannot be reached** — drawn where taps do not land.

## What exists today (for the builder)

- `logic/effects/effect_catalog.dart`: 39 `VideoEffect`s in categories, `defaultIntensity`,
  `defaultEnvelope`, `introSeconds`. The sheet is `widgets/panels/effects_panel.dart` (`EffectsPanel`,
  category tabs over a tile grid, one intensity slider), opened from the clip menu's `effects`.
- `VideoSegment.effectId` / `effectIntensity` (`AnimatableDouble`, one of the clip's seven
  keyframable properties) / `effectIntroSeconds`; `VideoEditorNotifier.setClipEffect`,
  `applyEffectToAllClips`.
- Engine: both engines resolve **one clip** per frame (`TimelinePlaybackEngine.applyClipEffect`,
  `VideoExportEngine`'s `effectClip`), the outgoing clip inside a transition window, none in the
  tail, and hand it to `ClipEffectController`, which rebuilds programs on an id change and pushes
  intensity and progress as uniforms. `TransitionRenderer.composite` runs the passes
  (`EffectPassChain`, `MAX_EFFECT_PASSES` 4) over the lanes and background **before** overlays.
- **A latent mismatch this design ends:** Dart places intensity keyframes on whole-clip progress
  (`clipProgressAt`), while Kotlin resolves them at the *effect* clock
  (`effectIntensityAt(effectProgressAt(t))`), which for a timed effect is the intro window. A
  keyframed intro therefore draws a different strength than the slider shows.

## How it works for the user

### Adding — the sheet **(proposed, accepted; details my call)**

- **Effects** on the main menu (id `effects`, sparkles icon), right after **Overlay**. The clip
  menu's Effects entry and its Apply-to-all copy go.
- It opens the same `EffectsPanel` sheet (same categories, tiles, 45% height) with no bar yet.
  **The first tap adds a bar at the playhead and selects it**; further taps while the sheet is
  open **change that bar's effect** rather than adding more, so browsing does not litter the
  timeline; closing keeps the last choice. Closing before any tap adds nothing.
- **The intensity slider** appears once there is a bar, and writes that bar.
- **No None tile** on the track: a bar is removed with Delete, and backing out of an add is Undo.
- One undo step per tap; a slider drag is one undo step; a tap on the effect the bar already
  wears changes nothing and takes no step. A new or replaced effect starts at its catalog
  `defaultIntensity` and `defaultEnvelope`.

### Where a new bar lands **(proposed, accepted; fitting my call)**

- At the playhead, **3 seconds** long (the length a new text gets), on the **first free lane** at
  that time (`firstFreeLane`) — never on top of anything.
- **It fits inside the project**: where fewer than 3 s remain before the project's end it ends at
  the end; where less than `kMinClipDurationSeconds` remains it starts earlier so it keeps that
  minimum. A new bar never makes the project longer.

### The bar on the timeline

- Drawn like a text or photo bar: square, the effect's **icon and name** on it, in its own colour
  — a new `AppColors` token distinct from every other lane's (my call: teal; the device look
  decides). The lane gutter gains an effect glyph (sparkles) beside music, text, image and video.
- Tap selects it, **as the only selection**; the toolbar shows its menu.
- **Long-press-drag moves it** (time and lane), **handles trim it**, everything snaps by the rules
  in `timeline_snapping.dart`, and the lane rules in `lane_layout.dart` have the last word: no
  overlap on a lane, no empty lane left behind. One undo step per gesture
  (`beginTimelineGesture` / `endTimelineGesture`). An item at 0:00 keeps its left handle inside.
- Its intensity diamonds sit on the bar, under its handles, as an overlay's do.
- Hidden in recording mode with every other lane.

### A selected bar's menu **(my call)**

**Edit · Copy · Delete.**
- **Edit** opens the effects sheet on this bar: its effect's category open and its tile marked,
  the slider on its intensity. A tap changes the effect (dropping the intensity's keyframes, as
  `setClipEffect` does today — that curve belonged to the old effect).
- **Copy** places a copy **straight after** the original on its lane when there is room there,
  else on the nearest free lane below — the audio rule (`duplicateAudioTrack`): an effect
  continuing. Same effect, intensity and keyframes. Selected; one undo step.
- **Delete**: one undo step; empty lanes close.

### Keyframes

A bar has **one** keyframable property, its intensity. The plus button, the easing sheet and the
edit rule work on a selected bar exactly as on a clip or an overlay: no diamonds → the slider
writes the base; on a diamond → that keyframe; between diamonds → a diamond is placed, then
written. **Progress is the bar's own 0..1** (`(t - start) / (end - start)`), so trimming a bar
stretches its curve with it — the overlay rule. Built on `keyframe_core.dart` with a one-parameter
adapter; the selected bar becomes a third kind of keyframe target beside clips and overlays.

## The rules that make it right

- **Bars live in timeline time.** Trimming, moving, splitting or deleting a clip does not move a
  bar. **(my call)** — CapCut's behaviour, and the reason a bar can span a cut.
- **Bars count toward the project's end like every other lane item** (`_projectEndSeconds`). A bar
  moved past the last clip extends the project over the background, exactly as a text does there;
  a new bar is placed to fit inside the project, so adding one never does (a Copy may, as an audio
  or text copy may). **(my call)** — every lane item already obeys this, and the alternative (bars
  that do not count) leaves a bar past the end drawn outside the timeline's content, where taps do
  not land. All three places that measure the project count bars: the composer's
  `_projectEndSeconds`, `totalEditedDurationProvider` and `ScrollableTimeline._totalEditedDuration`.
- **Stacking order is lane order**: the bar nearest the clips (lowest lane) applies first, each
  later one to the result. Lanes are paint order for overlays already. A bar's lane says nothing
  about overlays: Main video is always under all of them.
- **Through a transition** a bar simply applies to the blended frame. The old rule — the outgoing
  clip's effect owns the window — goes, with nothing to replace it.
- **In the tail** past the last clip, a bar applies to what Main video is there: the background.
- **The effect clock is the timeline clock, in both engines** — never a frame counter or wall
  time. A timed effect's shader progress runs over its `introSeconds` **from the bar's start** and
  rests at 1; a static or looping effect's runs across the whole bar. **Intensity keyframes and
  envelopes resolve at whole-bar progress** (the diamonds' clock), not at the shader's — which is
  what ends the mismatch above. In the preview, effects read the same clock the overlays draw at
  (`overlayClockNow`), so a bar in the tail follows the tail's playhead.
- **Pass budget.** A frame may run at most `MAX_EFFECT_PASSES` (4) passes. Bars are taken in lane
  order, **whole bars only** — a blur is never cut in half — and a bar that does not fit is skipped
  while later ones that do fit still draw. Each effect's pass cost is known to Dart (a `passCost`
  on the catalog, pinned to Kotlin's `EffectShaders.passesFor` by a shared fixture), and **an edit
  after which some bar is skipped at an instant where it was not before says so in one toast**,
  naming it ("Blur is skipped: too many effects at once") — compared over the instants where bars
  start and end, before and after the edit, so a bar already skipped does not toast again on every
  later edit. The same greedy rule runs on both sides and a fixture pins them together.
  (36 of 39 effects cost one pass; only stacked blur-class effects reach the limit.)

## Drawing — the engine **(proposed, accepted; mechanics builder's call within these rules)**

- **Contract**: `EditorTimeline` gains `effects`: per bar `id`, `effectId`, `start`, `end`,
  `lane`, `intensity` (the `AnimatableDouble` wire form), `introSeconds` (from the catalog, or
  absent). Sorted by lane. A bar whose `effectId` the catalog does not know is not sent — unknown
  degrades to no effect, never a crash. `videoClips[]` no longer carry effect fields.
- **Delivery to the preview on its own light channel** (`setEffects`), the `setOverlays` pattern:
  a bar drag, trim or slider drag must show live, and `setTimeline` re-prepares decoders and is
  skipped during gestures. Identity-checked so a position event never re-sends it. Export composes
  the timeline from state as it does now.
- **Kotlin**: `NativeTimelineEffect` (parse), and one shared resolver — which bars are drawn at `t`,
  in order, within the budget, each with its intensity and progress — used by **both** engines.
  It replaces `applyClipEffect` and `effectClip`.
- **No program is linked in the render path.** `ClipEffectController` becomes a stack controller
  that builds a bar's passes **when the effects list arrives** (on the GL thread, inline when
  already there — the export deadlock lesson) and frees them when the bar goes; which bars are
  active is then a choice among built passes, so crossing a bar's edge costs nothing. Intensity
  and progress stay `@Volatile` uniforms per pass. Whether two bars of one effect share programs
  is the builder's call; each needs its own uniforms.
- **`composite` is unchanged in shape**: lanes and background into the scene, the stack's passes
  over it, then overlays — so text and stickers stay sharp. With no bar active, the single-pass
  path exactly as today.
- **One writer at a time**: the export hold (`exportOwnsRenderer`) covers the effect stack as it
  covers fits and grades.

## Old projects

On draft load (`loadDraft`), every clip with an `effectId` becomes a bar, and the clip's effect
fields are dropped; the draft is saved in the new form. **The bar covers exactly where the clip's
effect showed**: from the end of the transition window into the clip (or the clip's start when
there is none) to the clip's end — the outgoing clip owned each window. Same effect, intensity
base value and envelope; **keyframes are re-placed on the same timeline instants** (rescaled from
clip progress to bar progress, any that fall before the bar's start dropped, with one pinned at the
start carrying the value there). Each bar on the first free lane at its time.

**One accepted difference:** a *timed* effect on a clip entered through a transition used to join
its intro part-way through (the window had shown the outgoing clip's effect); its bar now plays the
intro whole from the window's end. **(my call)** Nothing else changes.

Drafts gain `effects` (omitted when empty); clip JSON stops writing effect fields; a draft without
effects is byte-identical apart from that.

## What goes

The clip menu's Effects entry; `setClipEffect`, `applyEffectToAllClips` and the Effects sheet's
Apply-to-all button; `ClipProperty.effectIntensity` (clips keep six keyframable properties);
the effect checks in `_canMergeForPlayback`; the effect in `clipToOverlayLosses` (nothing is lost
any more); the effect copy in freeze frame; `applyClipEffect` and `effectClip` in the engines; the
CLAUDE.md "outgoing clip's effect owns the window" rule and the `editor_menu_test` pin that the main
menu has no Effects entry (it has one again, now with a handler).

## Testing

Test-first, as the project works; every rule a test can reach is pinned in Dart or JVM Kotlin.

- **Model/JSON**: a bar round-trips; drafts without effects unchanged; unknown effect ids dropped.
- **Placement**: at the playhead, 3 s, first free lane; fitting at the project's end; minimum length.
- **Lanes**: bars in `laneSpansOf`; move, trim, copy and delete through the lane rules; snapping to
  and from bar edges; one undo step per gesture and none for a gesture that changes nothing.
- **Sheet**: add mode (first tap adds, later taps replace, closing before a tap adds nothing, slider
  writes the bar), edit mode (opens on the bar's effect, replace drops intensity keyframes).
- **Menus**: Effects on the main menu with a handler; gone from the clip menu; the bar menu.
- **Keyframes**: the edit rule on a bar; bar-relative progress; trim stretches the curve.
- **Resolver**: active bars at `t` in lane order; budget skipping whole bars and continuing;
  progress for timed and static effects; intensity at whole-bar progress — **one fixture** generated
  from Dart, asserted in Kotlin (the project's usual mechanism, with its usual caveat: it catches
  divergence tomorrow, not a wrong rule today); pass costs pinned against `passesFor`.
- **Migration**: a clip without a transition; one entered through a transition; keyframes
  re-placed on the same instants; an intro; two adjacent effected clips; the draft re-saved.
- **Composer**: `effects` on the wire; clips without effect fields.
- **Engine (JVM)**: parsing; the stack controller builds on list arrival and never on a boundary.

**Device checks** (GLSL and timing only run there): a bar starts and stops on the right frame in
the preview and the export; two stacked bars; a bar across a transition; an intro plays from the
bar's start; playback crossing bar edges does not hitch; an old project with effects looks the
same; a bar in the tail; a bar dragged and trimmed updates the canvas live.

## Left to the builder

The bar colour's exact value; channel and class names; whether programs are shared between bars of
one effect; the toast's wording within the copy rules; the fixture's file names; the tile marking
in edit mode within the existing sheet look.
