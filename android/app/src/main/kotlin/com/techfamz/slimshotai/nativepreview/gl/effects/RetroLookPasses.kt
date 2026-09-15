package com.techfamz.slimshotai.nativepreview.gl.effects

/*
 * The analogue artefacts: film grain, tape, broadcast, damaged signal.
 *
 * **Every one of these needs pseudo-randomness, and every one of them gets it
 * from a deterministic hash** — of the pixel's coordinate, and of `uProgress`
 * where the noise should move. Never `Random()`, never a frame counter, never
 * `System.nanoTime`. This is the single most repeated bug class in this
 * codebase: export renders faster than realtime, so anything stateful or
 * wall-clock-driven draws a different picture in the file than on the canvas,
 * and the user approves one and ships the other. `TextAnimationCurves` is a pure
 * function of a position for exactly this reason, and `ContinuousPasses` says
 * the same thing about the shakes.
 *
 * The hash is `EffectShaderLib`'s `hash11`/`hash21`, shared rather than
 * rewritten here — two hashes in one codebase is two things that can disagree,
 * and the grain would then differ from the shake for no reason a reader could
 * find.
 *
 * **Every seed is wrapped into 0..1 before it reaches the hash, and that is a
 * hard requirement rather than tidiness.**
 *
 * `hash11` is `fract(sin(n * 127.1) * 43758.5453)`. ES 2.0 guarantees `mediump`
 * only a ±2^14 range with 2^-10 relative precision, and a driver that backs it
 * with fp16 has a largest finite value of 65504 — so `n * 127.1` overflows to
 * infinity once `n` passes **~515**, and `sin(inf)` is undefined. Well before
 * that, the absolute spacing of representable values at `n * 127.1` exceeds
 * `sin`'s 6.28 period, at which point the "noise" is whatever the driver's range
 * reduction happens to produce — in practice flat bands, and different bands on
 * different GPUs.
 *
 * The seeds in this file would have run to ~1400 (grain) and ~950 (glitch) if
 * built the obvious way, by adding a scaled coordinate to a scaled frame
 * counter. Both are past the overflow cliff. The shipped, device-verified
 * `HandheldPass` keeps its seed under ~90, and **nothing here goes beyond what
 * that proves**: each shader folds its coordinate and clock terms into 0..1
 * with `fract` and then scales by a small constant, so the value handed to
 * `hash11` stays inside single digits.
 *
 * Wrapping costs nothing and changes nothing about determinism — `fract` is a
 * pure function, so preview and export still agree frame for frame.
 *
 * All five are [SingleFramePass]es, so `EffectShaders.releasePasses` covers
 * them through its existing `is SingleFramePass` branch. None needs one of its
 * own.
 *
 * GL thread only.
 */

/**
 * Film grain: fine luminance noise that moves.
 *
 * **Static grain looks like dirt on the lens; moving grain reads as film.** That
 * distinction is the entire design of this shader. Grain sampled from the pixel
 * coordinate alone is a fixed pattern welded to the frame — the eye locks onto
 * it immediately and reads it as a dirty sensor or a damaged file. Real grain is
 * a fresh distribution of silver halide crystals on every exposure, so it
 * changes completely from frame to frame, and that flicker is what the eye
 * recognises as film stock.
 *
 * So the hash is seeded from the pixel **and** from the clip's own position, and
 * the clock is quantised into discrete steps: grain that varied smoothly with a
 * continuous progress would crawl rather than flicker.
 */
internal class GrainPass(program: FullFrameProgram) :
    SingleFramePass("grain", program) {

    internal companion object {
        /**
         * Peak noise amplitude at intensity 1, in signal units (0..1).
         *
         * Grain is judged against the mid-tones it sits on, and ±12% is already
         * a heavy stock. The catalog's 0.4 default lands near 5%, which is
         * roughly a fast colour negative — plainly present, and nowhere near the
         * "the video is broken" threshold.
         */
        const val MAX_AMPLITUDE = 0.12f

        /**
         * How many distinct grain fields the clip steps through.
         *
         * **Per clip, not per second** — the same rule `ContinuousPasses`
         * states for the shakes, and for the same reason: a rate in wall-clock
         * seconds cannot exist here, because export runs faster than realtime
         * and the file would flicker at a different speed than the canvas.
         *
         * 240 fields over a clip is about 48 changes a second on a 5s clip,
         * which is faster than the display and so reads as a continuous boil —
         * which is what grain looks like. A low count reads as strobing.
         */
        const val FIELDS = 240.0f

        /**
         * How much of the noise lands on the shadows rather than the highlights.
         *
         * Real grain is most visible in the mid-tones and falls away in both
         * directions: a blown highlight has no detail left to disturb and a
         * crushed black hides it. Weighting by `luma * (1 - luma)` reproduces
         * that, and it is also what stops the effect from speckling the
         * letterbox bars, which are flat black and would otherwise carry the
         * full amplitude — noise in the bars is the single most obvious tell
         * that an effect is applied to the canvas rather than to the picture.
         */
        const val SHADOW_BIAS = 4.0f

        /**
         * The grain.
         *
         * GLSL ES 1.00, compiled at runtime — a mistake here is a black frame on
         * a device, never a build error. No loops; `varying` and `texture2D`
         * only; an explicit fragment precision.
         *
         * The noise is **monochrome**, added equally to all three channels. Per
         * channel noise is chroma noise, which is what a bad sensor produces,
         * not what film does — colour speckle reads as a compression artefact
         * immediately.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    // **Quantised, so the field flickers rather than crawls.** A continuous
    // progress would slide the noise smoothly and read as a moving texture laid
    // over the picture; film replaces its grain wholesale every exposure.
    float field = floor(uProgress * ${FIELDS});

    // **Every intermediate is wrapped, not just the final seed.** Built the
    // obvious way — `x * 311.7 + y * 191.3 + field * 3.71` — the sum runs to
    // ~1400, and at `mediump` the damage is done by the *scaling*, before any
    // `fract` could undo it: once a term is that large its representable
    // spacing has already swallowed the low-order bits the noise is made of,
    // and `seed * 127.1` then overflows an fp16 range entirely. See the file
    // comment.
    //
    // So each term is folded back to 0..1 on its own, at the smallest scale
    // that still decorrelates neighbouring pixels, and the three are combined
    // while all of them are small. Nothing here exceeds single digits, which is
    // inside what the shipped `HandheldPass` already proves on a device.
    float sx = fract(vTexCoord.x * 37.3);
    float sy = fract(vTexCoord.y * 23.9);
    // The field advances the whole pattern. Wrapped too: FIELDS is 240, so the
    // raw product would be the largest term of the three.
    float sf = fract(field * 0.618);
    float seed = fract(sx + sy * 0.37 + sf * 0.71) * 6.0;
    // Centred on zero, so grain lightens and darkens equally and the picture's
    // average brightness is unchanged.
    float noise = hash11(seed) - 0.5;

    // Most visible in the mid-tones, absent from the flat black of the bars.
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    float weight = clamp(luma * (1.0 - luma) * ${SHADOW_BIAS}, 0.0, 1.0);

    float amount = noise * 2.0 * ${MAX_AMPLITUDE} * uIntensity * weight;

    // Monochrome: the same offset on every channel. Per-channel noise is chroma
    // speckle, which reads as a codec artefact rather than as film.
    gl_FragColor = vec4(clamp(color.rgb + amount, vec3(0.0), vec3(1.0)), color.a);
}
"""
    }
}

/**
 * A uniform horizontal displacement of the red and blue channels.
 *
 * **The glitch artefact, deliberately not the lens one.** See [ChromaticPass]
 * for the other half of this pair: there the displacement is radial and scales
 * with `r²`, so the centre is registered and the corners fringe — optics. Here
 * it is the *same* offset at every pixel in the frame, which is what a channel
 * arriving a few samples late on a signal path looks like, and there is no
 * position in the picture where it goes away.
 *
 * Written the same way the two would be the same effect at different strengths.
 * Written these two ways they read as glass and as damage respectively, which is
 * the only justification for shipping both.
 */
internal class RgbSplitPass(program: FullFrameProgram) :
    SingleFramePass("rgb_split", program) {

    internal companion object {
        /**
         * Peak separation at intensity 1, as a fraction of the frame's width.
         *
         * Larger than [ChromaticPass.MAX_SHIFT] because it has to be: a uniform
         * offset has no corner where it concentrates, so the same amount that
         * reads as heavy fringing at a corner is barely visible spread flat
         * across the frame. 1.8% of the width is ~19px at 1080, which is the
         * unmistakable-but-still-watchable amount the catalog's 0.35 default
         * lands at about a third of.
         */
        const val MAX_SHIFT = 0.018f

        /**
         * A faint vertical component, as a fraction of the horizontal one.
         *
         * **Purely horizontal is the tell that this is a shader.** Every
         * real signal path that separates channels has some vertical
         * misregistration too — a line-timing error, a misaligned head — and its
         * absence makes the effect look computed. A tenth of the horizontal
         * offset is enough to break the perfect row alignment without the
         * separation reading as diagonal.
         */
        const val VERTICAL_RATIO = 0.1f

        /**
         * The split.
         *
         * **A fraction of the width, not a pixel count**, so the ~400px preview
         * and the 1080p export separate by the same visible amount — the
         * resolution-dependence rule the catalog states for every intensity.
         *
         * Red goes one way and blue the other, green stays put: green carries
         * ~72% of the luminance, so displacing it would soften the whole picture
         * rather than colour-separate it.
         *
         * `uProgress` is deliberately **not** read. A split that wandered over
         * the clip would be a different effect — that is what [GlitchPass]
         * is — and this one is a steady misregistration.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
void main() {
    float shift = ${MAX_SHIFT} * uIntensity;
    vec2 offset = vec2(shift, shift * ${VERTICAL_RATIO});

    // The same offset at every pixel — no radius, no falloff. That uniformity
    // is the whole distinction from chromatic aberration.
    vec2 redUv = clamp(vTexCoord + offset, vec2(0.0), vec2(1.0));
    vec2 blueUv = clamp(vTexCoord - offset, vec2(0.0), vec2(1.0));

    vec4 green = texture2D(uTexture, vTexCoord);
    float red = texture2D(uTexture, redUv).r;
    float blue = texture2D(uTexture, blueUv).b;

    // Alpha from the undisplaced sample, so the letterbox keeps the opacity the
    // composite gave it.
    gl_FragColor = vec4(red, green.g, blue, green.a);
}
"""
    }
}

/**
 * CRT scan lines with a slight tube curvature in the brightness.
 *
 * The one retro look here that is a pure function of the pixel: a CRT's lines do
 * not move, and adding a roll would make this a different effect (which is what
 * [VhsPass]'s tracking band is). So no clock is read, and the picture is
 * identical at every frame of the clip.
 *
 * **The line count is fixed per frame, not per pixel**, which is the thing that
 * makes this resolution-independent: a shader drawing a dark line every other
 * *texel* produces 540 lines at 1080p and 200 in the preview — a different
 * picture in the file than on the canvas, and at export resolution fine enough
 * to alias into a moiré rather than read as a tube.
 */
internal class ScanlinesPass(program: FullFrameProgram) :
    SingleFramePass("scanlines", program) {

    internal companion object {
        /**
         * How many scan lines across the frame's height.
         *
         * A broadcast CRT the size of a phone in the hand is roughly this
         * coarse. It is a count per *frame*, so it is the same on any viewport —
         * the whole point of not deriving it from texels.
         */
        const val LINE_COUNT = 240.0f

        /** How dark a line's trough goes at intensity 1. */
        const val MAX_DARKEN = 0.45f

        /**
         * How much the tube's edge falls off, relative to the line darkening.
         *
         * A CRT is brightest at the centre of the tube and dims toward the
         * glass. Without it the scan lines sit on a perfectly even picture and
         * read as a texture laid over video; with it the frame has a shape, and
         * the two together are what says "screen" rather than "stripes".
         */
        const val TUBE_FALLOFF = 0.55f

        /**
         * The scan lines.
         *
         * A `cos` rather than a hard step: a real line has a soft profile, and a
         * hard one aliases badly the moment the line spacing approaches the
         * pixel grid — which it does at export resolution, where a step would
         * turn into a moiré pattern that is nothing like a tube.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    // Lines per frame height, so the count is identical at preview and export
    // resolution. 6.2831853 is 2*pi — one full cycle per line.
    float line = cos(vTexCoord.y * ${LINE_COUNT} * 6.2831853);
    // 0 at a trough, 1 at a crest. A soft profile, never a step: a hard edge
    // aliases into moire the moment the spacing nears the pixel grid.
    float lineLevel = 0.5 + 0.5 * line;
    float darken = 1.0 - (1.0 - lineLevel) * ${MAX_DARKEN} * uIntensity;

    // The tube's own falloff. Deliberately not aspect-corrected, for the same
    // reason VignettePass is not: a tube dims toward its own corners, and a
    // circle inscribed in a 9:16 frame would read as a band across the top and
    // bottom instead.
    float dist = length(vTexCoord - vec2(0.5)) / length(vec2(0.5));
    float tube = 1.0 - smoothstep(0.35, 1.25, dist) * ${TUBE_FALLOFF} * uIntensity;

    gl_FragColor = vec4(color.rgb * darken * tube, color.a);
}
"""
    }
}

/**
 * Worn videotape: a soft, warm picture with chroma bleed and a tracking band
 * drifting up the frame.
 *
 * Three artefacts of the format, which is what separates this from
 * [ScanlinesPass] (a CRT displaying a perfect signal) and from [RgbSplitPass]
 * (one fault, held still):
 *
 * * **Chroma smears horizontally and luma does not.** VHS carries colour at a
 *   fraction of the luminance bandwidth, so edges stay reasonably sharp while
 *   colour runs sideways off them. Sampling the chroma displaced while the luma
 *   is read at the pixel's own position reproduces exactly that, and it is the
 *   single artefact that most says "tape".
 * * **A tracking band drifts up the picture**, where the head's contact is
 *   poor: the line is displaced sideways and the colour drops out.
 * * **The picture is warm and slightly lifted**, because the tape's blacks are
 *   not black.
 */
internal class VhsPass(program: FullFrameProgram) :
    SingleFramePass("vhs", program) {

    internal companion object {
        /** Peak chroma smear at intensity 1, as a fraction of the frame width. */
        const val MAX_BLEED = 0.012f

        /** How tall the tracking band is, as a fraction of the frame height. */
        const val BAND_HEIGHT = 0.06f

        /**
         * How many times the tracking band crosses the frame over the clip.
         *
         * Per clip, not per second — the rule every continuous look here
         * follows, because export runs faster than realtime and a wall-clock
         * rate would drift at a different speed in the file. Two passes over a
         * clip is slow enough to read as a wandering fault rather than a
         * repeating animation.
         */
        const val BAND_SWEEPS = 2.0f

        /** Peak sideways displacement inside the band, as a fraction of width. */
        const val MAX_BAND_SHIFT = 0.05f

        /** How far the blacks lift at intensity 1 — tape has no true black. */
        const val MAX_LIFT = 0.06f

        /**
         * The tape.
         *
         * The band's position is a pure function of `uProgress`, and the
         * per-line jitter is a hash of the row **and** of a quantised clock —
         * deterministic, so preview and export agree frame for frame, while
         * still changing often enough to read as noise rather than as a fixed
         * pattern.
         *
         * Every sample is `clamp`ed into 0..1 before the read: the displacements
         * push sideways past the edge and the scene target's `GL_CLAMP_TO_EDGE`
         * would handle it, but saying so here makes the edge behaviour a
         * property of the effect rather than of a texture parameter set
         * somewhere else — the rule [FisheyePass] states.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float strength = uIntensity;

    // --- the tracking band --------------------------------------------------
    //
    // Drifts upward over the clip. `fract` wraps it, so it re-enters at the
    // bottom rather than stopping at the top.
    float bandCentre = fract(1.0 - uProgress * ${BAND_SWEEPS});
    // Distance to the band, measured on the wrapped axis so a band straddling
    // the frame's edge is one band rather than two half ones.
    float toBand = abs(vTexCoord.y - bandCentre);
    toBand = min(toBand, 1.0 - toBand);
    float band = 1.0 - smoothstep(0.0, ${BAND_HEIGHT}, toBand);

    // --- per-line jitter ----------------------------------------------------
    //
    // A hash of the row and of a coarsely quantised clock: deterministic, so
    // the file matches the canvas, and stepped rather than continuous so lines
    // snap between offsets the way a timing error does.
    //
    // **Both terms wrapped before combining**, as everywhere in this file: the
    // raw `row * 1.37 + tick * 2.13` reaches ~490, close enough to the fp16
    // overflow of `seed * 127.1` to be worth nothing on a driver that takes
    // `mediump` literally. See the file comment.
    float tick = floor(uProgress * 90.0);
    float row = floor(vTexCoord.y * 220.0);
    float rowSeed = fract(fract(row * 0.3179) + fract(tick * 0.1583) * 0.61) * 6.0;
    float jitter = (hash11(rowSeed) - 0.5) * 2.0;

    // The band carries most of the displacement; outside it a trace of line
    // noise keeps the picture from sitting perfectly still.
    float shift = jitter * ${MAX_BAND_SHIFT} * strength * (band * 0.9 + 0.1);

    // --- luma and chroma, sampled apart -------------------------------------
    //
    // **The artefact that says "tape".** Luma is read at the pixel's own
    // position so edges stay reasonably sharp; chroma is read displaced, so
    // colour runs sideways off them. VHS carries colour at a fraction of the
    // luminance bandwidth and this is what that looks like.
    vec2 lumaUv = clamp(vTexCoord + vec2(shift, 0.0), vec2(0.0), vec2(1.0));
    float bleed = ${MAX_BLEED} * strength;
    vec2 chromaUv = clamp(lumaUv + vec2(bleed, 0.0), vec2(0.0), vec2(1.0));

    vec4 lumaSample = texture2D(uTexture, lumaUv);
    vec3 chromaSample = texture2D(uTexture, chromaUv).rgb;

    float luma = dot(lumaSample.rgb, vec3(0.2126, 0.7152, 0.0722));
    float chromaLuma = dot(chromaSample, vec3(0.2126, 0.7152, 0.0722));
    // The displaced sample's *colour* carried onto this pixel's *brightness*:
    // chroma from over there, luma from here. Subtracting the displaced
    // sample's own luma leaves just its colour difference, so the smear moves
    // hue sideways without dragging brightness with it.
    vec3 smeared = lumaSample.rgb + (chromaSample - vec3(chromaLuma));
    // At strength 0 this is exactly `lumaSample.rgb`, so the effect vanishes
    // cleanly at the bottom of the slider rather than leaving a residual cast.
    vec3 rgb = mix(lumaSample.rgb, smeared, strength);

    // --- desaturation inside the band ---------------------------------------
    //
    // Where the head loses contact the colour goes before the picture does.
    rgb = mix(rgb, vec3(luma), band * 0.55 * strength);

    // --- the tape's own look ------------------------------------------------
    //
    // Lifted blacks and a warm cast. Tape has no true black, and its bias is
    // toward red — a cool VHS look is a colour-corrected one, which is not what
    // anybody picking this entry is asking for.
    float lift = ${MAX_LIFT} * strength;
    rgb = rgb * (1.0 - lift) + vec3(lift * 1.15, lift * 0.95, lift * 0.85);

    gl_FragColor = vec4(clamp(rgb, vec3(0.0), vec3(1.0)), lumaSample.a);
}
"""
    }
}

/**
 * Digital corruption: blocks of the picture torn sideways, with the channels
 * separating inside the tear.
 *
 * **Discrete, not continuous**, which is what distinguishes a digital glitch
 * from every analogue artefact here. A tape fault wanders; a corrupted frame is
 * fine, then wrong, then fine again, and the damage lands on *block boundaries*
 * because that is the granularity a codec works in. So both the vertical bands
 * and the time steps are quantised, and between steps nothing moves at all.
 *
 * **It is also mostly absent.** A glitch running on every frame is not a glitch,
 * it is a texture — the eye normalises it within a second and it stops reading
 * as damage. The shader therefore gates the whole effect behind a hashed
 * threshold, so most instants are the clean frame and the corruption arrives in
 * bursts. That gate is what makes this worth leaving on.
 */
internal class GlitchPass(program: FullFrameProgram) :
    SingleFramePass("glitch", program) {

    internal companion object {
        /** Peak sideways tear at intensity 1, as a fraction of the frame width. */
        const val MAX_TEAR = 0.09f

        /**
         * How many discrete instants the clip is divided into.
         *
         * Per clip, like every rate here. On a 5s clip this steps about 12 times
         * a second, which is slow enough that each state is legible as its own
         * frame of damage rather than blurring into a shimmer.
         */
        const val STEPS = 60.0f

        /** How many horizontal bands the frame is torn into. */
        const val BANDS = 22.0f

        /**
         * How often a band is glitched at all, at intensity 1.
         *
         * **The gate that keeps this watchable.** At 0.42 a little under half
         * the bands are disturbed during a burst and most instants leave the
         * frame almost untouched. Raising it toward 1 makes every band tear on
         * every step, at which point the picture is unreadable — damage rather
         * than a look.
         */
        const val MAX_RATE = 0.42f

        /** Channel separation inside a torn band, as a fraction of width. */
        const val MAX_SPLIT = 0.02f

        /**
         * The glitch.
         *
         * Two hashes, both deterministic and both seeded from small numbers so
         * `mediump`'s `sin` stays well-conditioned: one decides whether a given
         * band at a given instant is torn, the other decides how far. Nothing
         * here is stateful, so the file and the canvas corrupt on identical
         * frames — which is the whole reason `Random()` is barred.
         *
         * A `step` rather than a `smoothstep` on the gate: the corruption is
         * either happening to this band or it is not, and easing into it would
         * read as a smear.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    // Quantised in both axes: which band this pixel is in, and which instant
    // the clip is at. Between steps the picture is perfectly still, which is
    // what makes the damage read as digital rather than as a wobble.
    float band = floor(vTexCoord.y * ${BANDS});
    float tick = floor(uProgress * ${STEPS});

    // **Both terms wrapped before they are combined.** `band * 7.31 + tick *
    // 13.17` would reach ~950, past the point where `seed * 127.1` overflows an
    // fp16 `mediump` — and the low-order bits the hash needs are gone before
    // that. See the file comment. Folded first, the seed stays single-digit.
    float sb = fract(band * 0.4137);
    float st = fract(tick * 0.2731);
    float seed = fract(sb + st * 0.53) * 6.0;
    float roll = hash11(seed);
    float gate = step(1.0 - ${MAX_RATE} * uIntensity, roll);

    // How far, and which way. A second, independent seed — reusing the first
    // would tie the displacement's size to whether it happened at all, so every
    // tear would be the same width. Offset by a small constant rather than a
    // large one, for the same precision reason.
    float amount = (hash11(seed + 3.79) - 0.5) * 2.0;
    float tear = amount * ${MAX_TEAR} * uIntensity * gate;

    vec2 uv = clamp(vTexCoord + vec2(tear, 0.0), vec2(0.0), vec2(1.0));

    // Channels separate inside a tear and nowhere else — the split is gated on
    // the same roll, so an undisturbed band is byte-for-byte the source.
    float split = ${MAX_SPLIT} * uIntensity * gate;
    vec2 redUv = clamp(uv + vec2(split, 0.0), vec2(0.0), vec2(1.0));
    vec2 blueUv = clamp(uv - vec2(split, 0.0), vec2(0.0), vec2(1.0));

    vec4 base = texture2D(uTexture, uv);
    float red = texture2D(uTexture, redUv).r;
    float blue = texture2D(uTexture, blueUv).b;

    gl_FragColor = vec4(red, base.g, blue, base.a);
}
"""
    }
}
