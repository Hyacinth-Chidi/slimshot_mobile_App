# Transitions round two, part 2b — Light, Glitch, 3D

Stage 2 of `docs/roadmap.md`, part 2b, on the sheet part 2a built. Thirteen more layered
transitions, appended to the catalog; every pill now holds something.

| Category | Type | Label | From |
| :--- | :--- | :--- | :--- |
| Light | `overexposure` | Overexpose | Overexposure (Ben Zhang, MIT) |
| Light | `filmBurn` | Film Burn | FilmBurn (Anastasia Dunbar, MIT) |
| Light | `flash` | Flash | ours — a short white flash over the cut |
| Glitch | `glitchMemories` | RGB Split | GlitchMemories (Gunnar Roth, MIT) |
| Glitch | `lostSignal` | Lost Signal | old_tv_lost_signal (mernking, MIT) |
| Glitch | `tvStatic` | Static | StaticFade (Ben Lucas, MIT) |
| Glitch | `datamosh` | Datamosh | StripDatamoshGlitch (bread, MIT) |
| Glitch | `glitchDisplace` | Displace | GlitchDisplace (Matt DesLauriers, MIT) |
| Glitch | `flicker` | Flicker | Drop_Zone_Flicker (bread, MIT) |
| 3D | `revolveLeft`, `revolveRight` | Revolve L/R | Revolve_Left (bread, MIT), mirrored for Right |
| 3D | `cubeLeft`, `cubeRight` | Cube L/R | cube (gre, MIT), mirrored for Right |

The cubes were added to the roadmap's shortlist so the 3D pill holds more than the two revolves.
`tvStatic` is not `static` because that is a Dart keyword; GlitchMemories is labelled RGB Split
because a tile reading "Glitch" under the Glitch pill says one word twice.

## Port rules, beyond part 2a's

- **One hash, `slimHash`, for every sin-fract hash.** The glitch ports draw a value per block,
  row and frame; `fract(sin(x) * 43758.5)` keeps no fraction in `mediump`, and
  Drop_Zone_Flicker's `p * 443.9` overflows it. `slimHash` folds each input into 0..1 before
  combining, so nothing grows past a few hundred. The ports that hash also ask for `highp`
  where the GPU has it (`#ifdef GL_FRAGMENT_PRECISION_HIGH`); without it they run in
  `mediump`, coarser but finite.
- **Light is light on the lens; damage is to the picture.** Film Burn's leaks, Flash, and
  Datamosh's sparks and strobe are added over the whole frame, bars included (as Fade White
  already does). Scanlines, noise and exposure pulses are scaled by the picture's coverage, so
  bars stay clean.
- **Alpha is carried through**: every port that returned alpha 1 now returns its green
  sample's alpha. Cube's floor reflects over the background, not over black.
- GlitchDisplace computed a voronoi it never used — dropped, with its hash. Its reversed
  `smoothstep(1.0, 0.5, t)` is undefined in GLSL; written as `1.0 - smoothstep(0.5, 1.0, t)`.
- Right is Left mirrored: Revolve flips its direction (and the swirl centre with it); Cube
  mirrors its geometry and never the pictures on its faces. Each pair differs by one line.
- Light versions: Film Burn (5 leaks and 12 blur taps for 13 and 50, brightness kept) and
  both Revolves (5 motion-blur samples for 17).

## The sheet

Six pills no longer fit a phone at their natural width, and a pill that has to be scrolled to is
one people miss. They now **share the row equally**, each label scaled down where large text
would not fit; a test pins all six inside a 360px screen at 1.3× text.

## Tests

The names fixture grows by thirteen; each is supported, layered and binds no stray uniform; no
layered source contains a sin-fract hash; the hashing ports carry the precision guard and
`slimHash`; Left and Right differ by one line; the light versions are exactly the step-heavy
ones; every shader validated with `glslangValidator`. Dart: the categories, no tile labelled
like a pill, an empty category hidden, all six pills in order and on screen.
