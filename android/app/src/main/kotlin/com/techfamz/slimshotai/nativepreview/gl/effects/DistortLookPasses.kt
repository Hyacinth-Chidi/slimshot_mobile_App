package com.techfamz.slimshotai.nativepreview.gl.effects

/*
 * The distortions, and the one light effect that belongs beside them.
 *
 * Ripple, swirl and mirror are [FisheyePass]'s family — they **perturb the
 * sampling coordinate rather than the colour** — and they inherit its two rules
 * unchanged:
 *
 * * **The perturbation is computed in an aspect-corrected space.** Texture
 *   coordinates are 0..1 on both axes whatever the frame's shape, so a radius
 *   measured in them is a radius in a stretched space: a "circular" ripple on a
 *   9:16 canvas would be an egg, and a swirl would wind faster horizontally than
 *   vertically. `aspectScale` is applied on the way in and undone on the way
 *   out; correcting only on the way in squashes the whole picture.
 * * **The result is clamped back into 0..1 before sampling.** The scene target
 *   is `GL_CLAMP_TO_EDGE`, but saying so in the shader makes the edge behaviour
 *   a property of the effect rather than of a texture parameter set elsewhere.
 *
 * `LightLeakPass` is not a distortion — it adds light rather than moving pixels
 * — but it shares the aspect-corrected geometry and reads the same clock, so it
 * lives here rather than alone.
 *
 * All four are [SingleFramePass]es, covered by `EffectShaders.releasePasses`'s
 * existing `is SingleFramePass` branch. None needs a release branch of its own.
 *
 * GL thread only.
 */

/**
 * Concentric waves travelling outward from the frame's centre, like a stone
 * dropped in water.
 *
 * **The waves move**, driven by `uProgress`. A static ripple is a fixed
 * distortion of the picture — it reads as the lens being warped rather than as
 * water, because what the eye recognises as a ripple is the *propagation*, not
 * the shape. The travel is measured in wavelengths per clip, like every other
 * continuous rate in this codebase, because export runs faster than realtime and
 * a wall-clock rate would ripple at a different speed in the file.
 *
 * The displacement is **radial** — each pixel is pushed toward or away from the
 * centre, never sideways — which is what makes the wavefronts read as rings.
 */
internal class RipplePass(program: FullFrameProgram) :
    SingleFramePass("ripple", program) {

    internal companion object {
        /**
         * Peak radial displacement at intensity 1, as a fraction of the short
         * half-axis.
         *
         * Water distorts far less than people expect. Past about 4% the picture
         * stops being a rippled image of something and becomes an abstraction,
         * which is squarely the damage side of the quality bar. The catalog's
         * 0.4 default lands near 1.4%, which is plainly rippling while every
         * feature in frame stays recognisable.
         */
        const val MAX_AMPLITUDE = 0.035f

        /**
         * How many wave crests fit between the centre and the frame's short
         * edge.
         *
         * Few enough that each ring is a broad swell rather than a fine
         * corrugation: a high count aliases badly at preview resolution, where
         * the rings approach the pixel grid, and reads as noise rather than as
         * water.
         */
        const val WAVES = 7.0f

        /**
         * How many wavelengths the pattern travels over the clip.
         *
         * Per clip, not per second — see the file comment. Six crossings is a
         * slow, heavy swell on a short clip, which is what water looks like at
         * the scale of a whole frame.
         */
        const val SPEED = 6.0f

        /**
         * The ripple.
         *
         * GLSL ES 1.00, compiled at runtime — a mistake here is a black frame on
         * a device, never a build error. No loops; `varying` and `texture2D`
         * only; an explicit fragment precision, which ES 2.0 requires because it
         * defines no default `float` precision in a fragment shader.
         *
         * The amplitude is **damped toward the centre**. At the exact centre the
         * radial direction is undefined, and an undamped wave there makes the
         * middle of the picture pump in and out — a pulsing blob that looks
         * nothing like water. Scaling the amplitude by the radius itself removes
         * the singularity and matches how a real ripple loses height as it
         * converges.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec2 scale = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scale;

    // Normalised so the frame's short half-axis is 1.0 — the wave count then
    // means the same thing whatever the canvas shape is.
    float radius = length(centred) * 2.0;

    // A travelling wave: the phase advances with the clock, so the crests move
    // outward. 6.2831853 is 2*pi, making WAVES a count of full cycles.
    float phase = (radius * ${WAVES} - uProgress * ${SPEED}) * 6.2831853;

    // **Damped toward the centre**, which removes the singularity where the
    // radial direction is undefined and stops the middle of the frame pumping.
    float damping = clamp(radius * 2.0, 0.0, 1.0);
    float amplitude = ${MAX_AMPLITUDE} * uIntensity * damping;

    // Radial: along the centre-to-pixel direction. Using the centred vector
    // itself rather than a normalise means the centre pixel (radius 0) is
    // displaced by zero rather than dividing by it.
    vec2 offset = centred * 2.0 * sin(phase) * amplitude;

    vec2 uv = (centred + offset) / scale + vec2(0.5);
    gl_FragColor = texture2D(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}
"""
    }
}

/**
 * The frame twisted about its centre, hardest in the middle and untouched at
 * the rim.
 *
 * Structurally [FisheyePass] with a rotation where the bulge is: the same
 * aspect-corrected space, the same falloff to identity at the edge, a different
 * thing done in between. The falloff is what keeps it a look rather than
 * damage — a swirl applied uniformly rotates the whole picture, and a picture
 * that is simply turned is not a swirl.
 *
 * **Static, deliberately.** `uProgress` is not read. A rotating swirl is a
 * different effect — an intro that unwinds, which is the `spin` entry's
 * territory — and a continuous one would never let the viewer read the frame.
 */
internal class SwirlPass(program: FullFrameProgram) :
    SingleFramePass("swirl", program) {

    internal companion object {
        /**
         * Rotation at the very centre at intensity 1, in radians.
         *
         * A bit over a third of a turn. Past roughly half a turn the centre of
         * the picture winds past itself and becomes an unrecognisable spiral,
         * which is the point where this stops being a stylisation of the
         * footage. The catalog's 0.4 default lands near 0.9 radians — about 50
         * degrees — which reads unmistakably as a twist while the subject stays
         * legible.
         */
        const val MAX_RADIANS = 2.3f

        /**
         * The swirl.
         *
         * The angle falls off as `(1 - r)²` to reach **exactly zero at the
         * rim**, not merely nearly zero: a residual rotation at the edge would
         * shear the frame's border and pull background in along it, which reads
         * as the effect being broken rather than as a twist. Squaring makes the
         * transition gentle instead of conical.
         *
         * `radius` is clamped to 1 before the falloff, so the corners of a
         * non-square frame — which sit past the short half-axis — are left
         * exactly alone rather than being rotated the other way by a negative
         * falloff.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec2 scale = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scale;

    // Normalised so the short half-axis is 1.0. Clamped, because a 9:16 frame's
    // corners sit beyond that and an unclamped falloff would go negative there
    // and rotate them backwards.
    float radius = clamp(length(centred) * 2.0, 0.0, 1.0);

    // Exactly zero at radius 1 — no residual shear along the frame's border.
    float falloff = (1.0 - radius) * (1.0 - radius);
    float angle = ${MAX_RADIANS} * uIntensity * falloff;

    float s = sin(angle);
    float c = cos(angle);
    vec2 turned = vec2(
        centred.x * c - centred.y * s,
        centred.x * s + centred.y * c
    );

    vec2 uv = turned / scale + vec2(0.5);
    gl_FragColor = texture2D(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}
"""
    }
}

/**
 * One half of the frame reflected onto the other.
 *
 * **The fold is vertical — the left half is mirrored onto the right.** That axis
 * rather than the horizontal one for a concrete reason: this app's canvas is
 * 9:16 and its subject is a person, and human faces and bodies are already
 * bilaterally symmetric about a vertical axis, so a vertical fold produces a
 * picture that reads as a real (if uncanny) portrait. A horizontal fold puts a
 * reflected head where the torso was, which reads as an accident every time.
 * The horizontal mirror is also the one every video app calls "reflection" and
 * pairs with water, which is a different look and would want its own entry.
 *
 * **Intensity moves the seam rather than blending the halves.** The catalog's
 * comment says so — "a mirror is a fold, not a strength" — and that is why the
 * default is 1.0. Cross-fading the two halves instead would produce a
 * double-exposed ghost at every intermediate value, which is a distinct and much
 * worse-looking effect; moving the fold line keeps every slider position a real
 * mirror, just of a different amount of the frame.
 */
internal class MirrorPass(program: FullFrameProgram) :
    SingleFramePass("mirror", program) {

    internal companion object {
        /**
         * Where the fold sits at intensity 0, as a fraction of the width.
         *
         * At the frame's right edge, which means nothing is reflected and the
         * picture is untouched — the honest bottom of the slider. Intensity then
         * walks the seam left to the centre, so at 1.0 the left half is mirrored
         * onto the right and the picture is symmetric, which is what people mean
         * by "mirror".
         */
        const val MIN_SEAM = 1.0f

        /** Where the fold sits at intensity 1 — the middle, the symmetric picture. */
        const val MAX_SEAM = 0.5f

        /**
         * The fold.
         *
         * One `texture2D` call, with the coordinate decided before it. Reading
         * twice and mixing would be the blend this effect deliberately is not.
         *
         * No aspect correction: a fold is at a *position*, not at a distance, so
         * the frame's shape cannot enter into it.
         *
         * Nothing is clamped beyond what the reflection already guarantees —
         * `seam * 2.0 - x` for `x` in `[seam, 1]` lands in `[2*seam - 1, seam]`,
         * which for `seam >= 0.5` is inside 0..1. The clamp is kept anyway,
         * because that reasoning depends on MAX_SEAM never dropping below 0.5
         * and a future edit should not have to rediscover it.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
void main() {
    float seam = mix(${MIN_SEAM}, ${MAX_SEAM}, uIntensity);

    // Left of the seam the frame is itself; right of it, the reflection of what
    // lies an equal distance to the left. At seam == 1.0 nothing is right of it
    // and the picture is untouched.
    float x = vTexCoord.x;
    if (x > seam) {
        x = seam * 2.0 - x;
    }

    vec2 uv = clamp(vec2(x, vTexCoord.y), vec2(0.0), vec2(1.0));
    gl_FragColor = texture2D(uTexture, uv);
}
"""
    }
}

/**
 * A warm bloom spilling in from one edge, as light does past a camera's seal.
 *
 * Additive rather than a grade: the leak is light **added** to the frame, so it
 * blows out what it lands on instead of tinting it. A multiply would darken the
 * picture toward orange, which is a tobacco filter — a completely different and
 * much more dated look.
 *
 * **It drifts with `uProgress`.** A stationary leak is a smudge welded to the
 * frame; a real one moves as the camera turns, and that slow travel across the
 * clip is what makes it read as light rather than as a graphic. The travel is
 * per clip, like every rate in this codebase, because export runs faster than
 * realtime.
 */
internal class LightLeakPass(program: FullFrameProgram) :
    SingleFramePass("light_leak", program) {

    internal companion object {
        /**
         * Peak added light at intensity 1, in signal units.
         *
         * Enough to blow the frame's edge to near white at the leak's core, and
         * no more. A leak that saturates a large area of the picture has erased
         * whatever was there, and the catalog's 0.5 default lands at about
         * half of this — a warm wash over one edge with the footage still fully
         * visible through it.
         */
        const val MAX_STRENGTH = 0.85f

        /**
         * The leak's colour — a warm amber, not white and not red.
         *
         * Light leaking past a seal is filtered by the camera's own body and
         * arrives orange; a white leak looks like a blown highlight (a fault,
         * not a look) and a red one looks like a colour-channel bug. Slightly
         * more red than green and very little blue is the colour of daylight
         * through a gap.
         */
        const val LEAK_R = 1.0f
        const val LEAK_G = 0.72f
        const val LEAK_B = 0.38f

        /**
         * How far the leak's centre travels along the edge over the clip, as a
         * fraction of the frame.
         *
         * Small. The leak should wander, not sweep — a visible traverse across
         * the frame turns it into an animation, and this is a look. A quarter of
         * the frame over the whole clip is barely perceptible as motion and yet
         * entirely removes the welded-on feeling of a static gradient.
         */
        const val DRIFT = 0.25f

        /**
         * How wide the bloom is, as a fraction of the frame's diagonal.
         *
         * Broad, because a leak is unfocused by definition — it has no lens
         * between it and the sensor. A tight one reads as a lens flare, which is
         * a different effect with hard geometry.
         */
        const val RADIUS = 0.85f

        /**
         * The leak.
         *
         * The bloom is a smooth radial falloff from a point parked **outside**
         * the frame's top-right corner, so what is in shot is the tail of it
         * rather than a disc with a visible centre — a leak whose brightest
         * point is inside the picture reads as a lamp in the scene.
         *
         * The falloff is computed in the aspect-corrected space, so the bloom is
         * round on any canvas shape rather than as oblong as the frame. The
         * `smoothstep` reaches exactly zero at the radius, so the far side of
         * the picture is byte-for-byte untouched.
         *
         * Screened rather than simply added: `a + b - a*b` approaches 1 without
         * crossing it, so the leak's core brightens toward white instead of
         * clipping to a flat patch of amber, which is what an unclamped add does
         * to any channel that saturates first.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);

    vec2 scale = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scale;

    // The source sits outside the top-right corner and wanders along that edge
    // over the clip, so only the tail of the bloom is ever in frame.
    float travel = (easeInOut(uProgress) - 0.5) * ${DRIFT};
    vec2 source = vec2(0.42 + travel, 0.46) * scale;

    float dist = length(centred - source) * 2.0;
    // Exactly zero past the radius: the far side of the frame is untouched.
    float falloff = 1.0 - smoothstep(0.0, ${RADIUS}, dist);
    // Squared, so the bloom has a soft shoulder and a bright core rather than a
    // linear ramp, which reads as a gradient overlay.
    falloff = falloff * falloff;

    vec3 leak = vec3($LEAK_R, $LEAK_G, $LEAK_B) *
        falloff * ${MAX_STRENGTH} * uIntensity;

    // Screen, not add: approaches 1 without clipping, so the core goes white
    // rather than flat amber.
    vec3 lit = color.rgb + leak - color.rgb * leak;

    gl_FragColor = vec4(clamp(lit, vec3(0.0), vec3(1.0)), color.a);
}
"""
    }
}
