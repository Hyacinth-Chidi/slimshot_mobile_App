package com.techfamz.slimshotai.nativepreview.gl.effects

/*
 * The zoom intros: a push in that settles.
 *
 * Five entries that differ only in their scale-over-progress curve, so they are
 * written together — a family sharing one geometry and one rule.
 *
 * **The rule is that every one of them lands on scale 1.0 at progress 1.** An
 * intro's settled state must be the untouched frame, because progress stays at 1
 * for the rest of the clip: a curve that ends at 1.02 leaves the clip
 * permanently 2% magnified, and the jump is at the *end* of the intro, which is
 * exactly where the eye is looking. Each curve below is written so the scale is
 * an identity at p == 1 by construction, not by arithmetic that happens to round
 * there — `easeOut(1.0)` is exactly 1.0 and every mix ends on the literal 1.0.
 *
 * **They zoom in, never out past the frame.** A scale above 1 samples a
 * sub-rectangle of the picture, so every texel read is inside the frame and the
 * off-frame rule never comes up. A zoom that started *below* 1 would show
 * background around the picture, which is a different effect (a drop-in) and not
 * what "punch in" means.
 *
 * GL thread only.
 */

/**
 * A slow, cinematic push in that settles — the Ken Burns opening.
 *
 * The gentlest of the family and the longest: 1.2s, because the whole character
 * of it is that the movement is barely perceptible until it stops. A fast
 * cinema zoom is just a zoom.
 */
internal class CinemaZoomPass(program: FullFrameProgram) :
    SingleFramePass("cinema_zoom", program) {

    internal companion object {
        /**
         * How far in it starts, at intensity 1.
         *
         * Small on purpose. A cinematic push is a drift, and past roughly this
         * the movement announces itself — which is the `zoom_in` entry's job,
         * not this one's.
         */
        const val MAX_START_SCALE = 1.18f

        /**
         * GLSL ES 1.00: `varying`, `texture2D`, explicit fragment precision, no
         * loops. Compiled at runtime, so a mistake is a black frame on a device.
         *
         * **`easeInOut`, not `easeOut`.** An ease-out starts at its fastest, and
         * a cinema zoom that lurches on the first frame and then slows is the
         * opposite of the look — it should ease into the movement as well as out
         * of it.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float start = 1.0 + (${MAX_START_SCALE} - 1.0) * uIntensity;
    // Ends on the literal 1.0 whatever the intensity, so the settled frame is
    // the untouched one.
    float scale = mix(start, 1.0, easeInOut(uProgress));
    gl_FragColor = texture2D(uTexture, zoomUv(vTexCoord, scale, vec2(0.5)));
}
"""
    }
}

/**
 * A punch in: starts hard in and snaps out to the frame.
 *
 * The same geometry as [CinemaZoomPass] on a much shorter window and a harder
 * curve. Short — 0.5s — because a punch that takes a second is a drift.
 */
internal class ZoomInPass(program: FullFrameProgram) :
    SingleFramePass("zoom_in", program) {

    internal companion object {
        /** How far in it starts, at intensity 1. */
        const val MAX_START_SCALE = 1.6f

        /**
         * **`easeOut`, not `easeInOut`.** A punch is all front-loaded: it should
         * be fastest on its first frame and decelerate into place, which is what
         * makes it read as an impact rather than as a move.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float start = 1.0 + (${MAX_START_SCALE} - 1.0) * uIntensity;
    float scale = mix(start, 1.0, easeOut(uProgress));
    gl_FragColor = texture2D(uTexture, zoomUv(vTexCoord, scale, vec2(0.5)));
}
"""
    }
}

/**
 * [ZoomInPass] with the gain turned up: a much harder punch, still 0.5s.
 *
 * Its own entry rather than the same shader at a higher intensity, because the
 * intensity slider must stay usable on both: a user who wants a *gentle* super
 * zoom has nowhere to go if the two are one entry whose default is maximum.
 */
internal class SuperZoomPass(program: FullFrameProgram) :
    SingleFramePass("super_zoom", program) {

    internal companion object {
        /**
         * Far enough in that the opening frame is a detail rather than a
         * picture, which is the point of it.
         *
         * Capped short of where the magnification turns the source's own texels
         * into visible blocks — at 2.6x a 1080 export is sampling from an
         * effective 415px, which on phone footage is still a picture.
         */
        const val MAX_START_SCALE = 2.6f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float start = 1.0 + (${MAX_START_SCALE} - 1.0) * uIntensity;
    float scale = mix(start, 1.0, easeOut(uProgress));
    gl_FragColor = texture2D(uTexture, zoomUv(vTexCoord, scale, vec2(0.5)));
}
"""
    }
}

/**
 * Zoom pulsing on a beat, then settling.
 *
 * **A decaying oscillation, not a loop.** It is an intro, so it has to end: the
 * pulse amplitude is multiplied by `(1 - p)` so the last beat is the smallest
 * and the scale arrives at exactly 1.0. A constant-amplitude pulse would be a
 * continuous look and would belong in a different category — and would jump the
 * moment progress pinned at 1 and the movement stopped mid-beat.
 */
internal class PulseZoomPass(program: FullFrameProgram) :
    SingleFramePass("pulse_zoom", program) {

    internal companion object {
        /** How deep each pulse goes at intensity 1. */
        const val MAX_AMPLITUDE = 0.22f

        /**
         * How many pulses fit in the window.
         *
         * Three over 1.0s is 3Hz — around 180bpm, which is fast for music but
         * right for a short-form intro, where the pulse has to be legible in
         * under a second.
         */
        const val PULSES = 3.0f

        /**
         * **The decay and the phase both have to land on zero together.**
         *
         * `cos(2*pi*n*p)` is 1 at p == 0 and, with an integer `n`, exactly 1
         * again at p == 1 — so `(1 - cos)` is 0 at both ends and the pulse
         * neither starts nor ends mid-swing. The `(1 - p)` decay then only has
         * to bring the *amplitude* down; the two together mean the scale is
         * exactly 1.0 at the end by two independent routes, which is the belt
         * and braces an intro's settle deserves.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float decay = 1.0 - uProgress;
    // 0 at both ends of the window with an integer pulse count, so the
    // oscillation itself starts and finishes at rest.
    float swing = 1.0 - cos(uProgress * ${PULSES} * 6.2831853);
    float scale = 1.0 + swing * 0.5 * ${MAX_AMPLITUDE} * uIntensity * decay;
    gl_FragColor = texture2D(uTexture, zoomUv(vTexCoord, scale, vec2(0.5)));
}
"""
    }
}

/**
 * Overshoots the frame and settles back — a spring landing.
 *
 * The one member of the family that passes *through* its resting scale rather
 * than approaching it, which is what "bounce" means. It still ends exactly at
 * 1.0: the overshoot is a decaying cosine whose envelope is zero at p == 1.
 */
internal class BouncePass(program: FullFrameProgram) :
    SingleFramePass("bounce", program) {

    internal companion object {
        /** How far in it starts. */
        const val MAX_START_SCALE = 1.45f

        /**
         * How far past the resting scale the first rebound goes, as a fraction
         * of the starting overshoot.
         */
        const val BOUNCE_DAMPING = 5.0f

        /** Oscillations across the window. */
        const val BOUNCES = 2.5f

        /**
         * A damped spring, written so the envelope is zero at both ends.
         *
         * `exp(-k*p)` alone never reaches zero, so the scale would arrive a hair
         * off 1.0 and the clip would sit permanently magnified by a fraction of
         * a percent — invisible in a still and a visible snap the moment the
         * intro ends. Multiplying by `(1 - p)` forces the envelope to exactly
         * zero, which is the settle guarantee this family is built on.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float amplitude = (${MAX_START_SCALE} - 1.0) * uIntensity;
    // Exponential decay for the spring's feel; the linear term forces the
    // envelope to exactly zero at p == 1 so the settle is exact.
    float envelope = exp(-${BOUNCE_DAMPING} * uProgress) * (1.0 - uProgress);
    float scale = 1.0 + amplitude * envelope * cos(uProgress * ${BOUNCES} * 6.2831853);
    gl_FragColor = texture2D(uTexture, zoomUv(vTexCoord, scale, vec2(0.5)));
}
"""
    }
}
