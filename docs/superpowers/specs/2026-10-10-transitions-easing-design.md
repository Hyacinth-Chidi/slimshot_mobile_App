# Transitions round two, part 3 — easing, and the licences page

Stage 2 of `docs/roadmap.md`, part 3. Agreed with the user 2026-10-10.

## Easing

- **A curve button beside the transition's duration**, shown only while a transition is applied,
  opens the keyframes' own easing sheet (`showKeyframeEasingSheet`): Default / Quadratic / Cubic /
  Bounce, each None / Ease in / Ease out / Ease. Every choice applies at once and plays the
  transition on the canvas, as a tile tap does. The icon (`spline`, the keyframe curve's) is lit
  while the seam is eased. Bounce stays offered — the sheet is reused as it is.
- **The picture only.** `NativeTimelineTransitionIntent.pictureProgressAt` is `progressAt`
  through the curve; the shader reads it in the preview (both draw sites) and the export. The
  sound's equal-power crossfade keeps `progressAt`: an eased crossfade would surge, and under a
  bounce swing back.
- **Per seam**, on the clip that transitions out (`VideoSegment.transitionEasing`), like type
  and duration. Apply to all writes it to every seam; turning Apply to all on spreads it with the
  transition. A new type keeps it; **clearing the transition clears it** (in `copyWith`, so every
  existing clear site — None, reorder, a split's left half, the last seam — is covered). A split's
  right half carries it with the transition.
- **None is stored as nothing.** Linear is never written: a seam without a curve writes no
  `transitionEasing` to the draft and no `easing` to the engine, so every existing project is
  byte-identical. An unknown name reads as none.
- **Re-easing does not rebuild the lanes.** `NativeTimelineTransitionIntents.sameWindows`
  compares transitions with easing set aside, so an easing-only edit takes the soft path; a type
  change still rebuilds, as before.
- The tiles stay linear: they show a transition's shape, easing is the seam's timing.

## Licences

`registerThirdPartyLicences` (in `main()`) adds the GL Transitions MIT notice and every ported
author to Flutter's `LicenseRegistry`; Settings → LEGAL → **Open-source licences** opens
`LicensePage` on the root navigator, which also lists every pub package's licence. Until now the
app had no licences page, and the shader credits lived only in source comments, which the APK
does not carry.

## Tests

Kotlin: the curve shapes the picture's progress and leaves the audio's; every curve opens and
closes the window exactly; unknown names are linear; an easing-only change is the same windows.
Dart: draft round trip and byte-identity, the wire key only when eased, the notifier (one undo
step, none for no change, cut, Apply to all, type change, None, split), the sheet's curve button.
Licences: the notice and every author registered once; the page opens on the root navigator.
