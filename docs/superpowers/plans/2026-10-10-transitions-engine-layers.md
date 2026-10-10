# Transitions part 1 — lane layers and Zoom Blur: plan

Spec: `docs/superpowers/specs/2026-10-10-transitions-engine-layers-design.md`. Executed natively,
test-first, on `stage2-transitions-engine`.

1. **Pin the existing shaders.** `TransitionShadersGoldenTest` hashes every existing fragment
   source (11 types × 4 sampler pairings, both passthroughs) before anything changes.
2. **Shared names.** `test/fixtures/transition_names.json` (+ the copy under
   `android/app/src/test/resources/`), a Dart test against `EditorTransition`, a Kotlin test
   against `TransitionShaders.supportedTypes`. Add `zoomBlur` to the fixture: both fail.
3. **Layered shaders.** `TransitionShaders`: `isLayered`, `layerFragment(isImage)` (one lane as a
   premultiplied layer), `layeredFragmentFor(type, light)` (the GL-Transitions API over two
   layers, laid over `backgroundAt()`), the Zoom Blur port with a step count. The old header is
   assembled from the same text, so step 1 stays green. Validate with `glslangValidator`.
4. **The speed decision.** `TransitionQualityGovernor` (pure), tested.
5. **Renderer.** Layer targets (lazy, size-guarded, released with the effect targets and when
   unused); layers drawn before the frame's target binds; the layered draw in `drawLanes`; the
   dissolve fallback with one warning; the governor fed from `renderFrame`, preview only;
   `TransitionProgram` gains `bindLayers`.
6. **Dart.** `EditorTransition.zoomBlur` ('Zoom Blur', `LucideIcons.focus`), appended.
7. **Verify.** Kotlin suite, `flutter test`, `flutter analyze --no-pub` (44), debug APK.
   CLAUDE.md and the roadmap updated; Stage 1 marked device-verified.
