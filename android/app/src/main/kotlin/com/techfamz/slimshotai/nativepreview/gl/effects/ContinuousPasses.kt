package com.techfamz.slimshotai.nativepreview.gl.effects

/*
 * Continuous looks: effects that run for the whole clip rather than settling.
 *
 * **These declare no `introSeconds`**, so `uProgress` is the clip's position
 * across its whole length — 0 at the first frame, 1 at the last. That is the
 * catalog's existing contract for a static look, used here for motion instead of
 * ignored.
 *
 * Two consequences worth stating, because both look like bugs otherwise:
 *
 * * **The motion's rate is per clip, not per second.** A drift that crosses the
 *   frame over the clip takes 3s on a 3s clip and 90s on a 90s one. For a pan
 *   that is exactly right — the gesture is "across this clip". For the shakes
 *   it would be wrong, so they multiply progress by a rate constant and shake at
 *   a fixed number of cycles per clip; a shake tied to wall-clock seconds cannot
 *   exist here, because export runs faster than realtime and the file would
 *   shake at a different speed than the canvas.
 * * **There is no settle, and none is wanted.** A continuous look is displaced
 *   at its last frame as much as at its first. The settle rule belongs to the
 *   intro category.
 *
 * Every displacement here is a pure function of `uProgress` — **never
 * `Random()`**, never a frame counter, never `System.nanoTime`. Export renders
 * faster than realtime, so anything stateful draws a different picture in the
 * file than on the canvas; `TextAnimationCurves` is a pure function of a
 * position for exactly this reason, and the text shake already caught this
 * codebase out once.
 *
 * GL thread only.
 */

/**
 * A slow drift across the frame.
 *
 * The Ken Burns move without the zoom settling: the frame is pushed in enough to
 * have somewhere to travel, and the sampling window walks across it. Because the
 * window never leaves the picture, this needs no off-frame handling.
 */
internal class CameraPanPass(program: FullFrameProgram) :
    SingleFramePass("camera_pan", program) {

    internal companion object {
        /**
         * How far in the frame is pushed, at intensity 1.
         *
         * **This is what creates the room to pan.** At scale 1 there is nowhere
         * to travel — every sample outside the original frame would be
         * background. At 1.25 the sampling window is 80% of the frame, so it can
         * walk 20% of the width without ever leaving it, which is the pan.
         */
        const val MAX_SCALE = 1.25f

        /**
         * The drift.
         *
         * **The travel is derived from the scale**, not a constant: the window
         * can move exactly as far as the zoom cropped away, so the pan is always
         * the largest one that never shows background — and at intensity 0 both
         * fall to zero together and the clip is untouched, rather than a
         * zero-zoom frame sliding off its own edge.
         *
         * `easeInOut` over the whole clip so the drift starts and ends gently
         * rather than beginning at full speed, which is the difference between a
         * camera move and a slide.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
${EffectShaderLib.COMMON}
void main() {
    float scale = 1.0 + (${MAX_SCALE} - 1.0) * uIntensity;
    // Half the cropped-away margin, in source UV: exactly how far the window
    // can travel from centre in each direction without leaving the frame.
    float room = 0.5 * (1.0 - 1.0 / scale);

    // -room at the start, +room at the end. Never outside the picture, so no
    // off-frame sampling can arise.
    float offset = mix(-room, room, easeInOut(uProgress));

    vec2 uv = zoomUv(vTexCoord, scale, vec2(0.5));
    uv.x = uv.x + offset;
    gl_FragColor = texture2D(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}
"""
    }
}

/**
 * Subtle continuous camera shake — the handheld look.
 *
 * The same deterministic hash as [SteadyInPass] without the decay, plus a slow
 * drift underneath it: a real handheld camera wanders as well as jitters, and
 * jitter alone reads as a mechanical vibration rather than as a person holding
 * something.
 */
internal class HandheldPass(program: FullFrameProgram) :
    SingleFramePass("handheld", program) {

    internal companion object {
        /** Peak jitter at intensity 1, as a fraction of the frame's short side. */
        const val MAX_AMPLITUDE = 0.012f

        /**
         * Jitter samples across the clip.
         *
         * High, because this is measured per *clip*: on a 5s clip 90 samples is
         * about 18Hz, which is the frequency range a hand actually shakes at.
         */
        const val RATE = 90.0f

        /** How far the slow wander travels, relative to the jitter. */
        const val DRIFT_SCALE = 1.6f

        /**
         * The cover zoom.
         *
         * Enough to keep the displaced frame's edges off screen at full
         * intensity: the jitter and the drift together reach about 3% of the
         * frame, and 6% of headroom covers it with margin. Without it the frame
         * would show a black sliver along one edge on every shake.
         */
        const val COVER_SCALE = 1.06f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    float amplitude = ${MAX_AMPLITUDE} * uIntensity;

    // Fast jitter: deterministic, a pure function of the clip's own position.
    vec2 jitter = (hash21(uProgress * ${RATE}) - vec2(0.5)) * 2.0 * amplitude;
    // Slow wander underneath it, so the camera drifts as well as shakes. Two
    // incommensurable frequencies, so the pair never repeats within a clip.
    vec2 drift = vec2(
        sin(uProgress * 7.0),
        cos(uProgress * 5.0)
    ) * amplitude * ${DRIFT_SCALE};

    vec2 scaleVec = aspectScale(uAspect);
    // Displaced in the square space so the shake travels equally on both axes.
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec + jitter + drift;
    vec2 uv = centred / scaleVec / ${COVER_SCALE} + vec2(0.5);
    gl_FragColor = sampleFrame(uTexture, uv);
}
"""
    }
}

/**
 * Aggressive shake, with rotation.
 *
 * [HandheldPass] turned up is not the same effect: past a certain amplitude a
 * pure translation reads as the picture sliding rather than as a camera being
 * shaken, and what sells the difference is the frame **rotating** slightly with
 * each jolt. So this is its own shader rather than the same one at a higher
 * intensity — and it keeps its own slider, which a shared entry could not.
 */
internal class SuperShakePass(program: FullFrameProgram) :
    SingleFramePass("super_shake", program) {

    internal companion object {
        /** Peak displacement at intensity 1, as a fraction of the frame's short side. */
        const val MAX_AMPLITUDE = 0.05f

        /** Peak rotation at intensity 1, in radians — about 3 degrees. */
        const val MAX_RADIANS = 0.055f

        /** Jitter samples across the clip — faster than handheld, as a jolt is. */
        const val RATE = 150.0f

        /**
         * The cover zoom.
         *
         * Larger than handheld's because both the displacement and the rotation
         * pull the frame's corners inward: at 5% displacement and 3 degrees the
         * corners need roughly 12% of headroom to stay off screen.
         */
        const val COVER_SCALE = 1.16f

        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
uniform float uAspect;
${EffectShaderLib.COMMON}
void main() {
    float amplitude = ${MAX_AMPLITUDE} * uIntensity;
    float seeded = uProgress * ${RATE};

    vec2 jitter = (hash21(seeded) - vec2(0.5)) * 2.0 * amplitude;
    // A third independent hash for the roll, offset well away from the two the
    // displacement uses so the rotation is not correlated with either axis —
    // a correlated roll reads as the frame swinging on a pendulum.
    float roll = (hash11(seeded + 313.7) - 0.5) * 2.0 * ${MAX_RADIANS} * uIntensity;

    vec2 scaleVec = aspectScale(uAspect);
    vec2 centred = (vTexCoord - vec2(0.5)) * scaleVec + jitter;

    float s = sin(roll);
    float c = cos(roll);
    vec2 turned = vec2(centred.x * c - centred.y * s, centred.x * s + centred.y * c);

    vec2 uv = turned / scaleVec / ${COVER_SCALE} + vec2(0.5);
    gl_FragColor = sampleFrame(uTexture, uv);
}
"""
    }
}
