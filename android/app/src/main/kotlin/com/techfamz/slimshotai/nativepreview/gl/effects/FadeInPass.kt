package com.techfamz.slimshotai.nativepreview.gl.effects

/**
 * The clip rises from black over its opening and settles.
 *
 * **The first effect that is a function of time rather than of the pixel**, and
 * deliberately the simplest one that can be: a single multiply by `uProgress`.
 * That is the whole point of it — an intro that is only one multiply has
 * nowhere for a bug to hide, so a picture that starts black, rises smoothly and
 * then stays put is proof that the clock reaching the shader really is the
 * clip's own position through its own window. On anything more elaborate — a
 * zoom, a shutter — a wrong clock and a right one look alike for the first few
 * frames, which is exactly when the difference matters.
 *
 * The window is `fade_in`'s `introSeconds` in the Dart catalog, resolved by the
 * composer and carried on the clip, so this shader knows nothing about how long
 * a fade lasts. Progress reaches 1 at the end of that window and **stays** at 1
 * for the rest of the clip: `p == 1` is a plain passthrough, which is what lets
 * an intro settle without the effect having to be taken off the clip.
 *
 * GL thread only.
 */
internal class FadeInPass(program: FullFrameProgram) :
    SingleFramePass("fade_in", program) {

    internal companion object {
        /**
         * The fade, as one multiply on the sampled colour.
         *
         * GLSL ES 1.00, compiled at runtime — a mistake here is a black frame
         * on a device, never a build error:
         *
         * * `attribute`/`varying`, never `in`/`out`; `texture2D`, never
         *   `texture`.
         * * An explicit fragment precision, because ES 2.0 defines no default
         *   `float` precision in a fragment shader.
         * * No loops, so no constant-bound question arises.
         *
         * **`smoothstep`, not a linear ramp.** A linear fade spends its first
         * frames in the range where a few code values are the whole picture, so
         * on 8-bit output it steps visibly out of black; easing both ends puts
         * the fast part in the middle where there is headroom for it. It is
         * also what the eye reads as a fade rather than as a dissolve.
         *
         * **Intensity is how far down the fade starts, not how much of the
         * frame it covers.** At 1 the clip opens on true black; at 0.4 it opens
         * at 60% brightness and lifts from there, which is the gentler version
         * of the same gesture. Mapping intensity onto the *duration* instead
         * was rejected: the window is the catalog's to state, and an effect
         * quietly redefining its own length from a slider would put two answers
         * in the timeline for how long the intro runs.
         *
         * Alpha is carried through untouched. The lanes composite a letterboxed
         * frame, and fading alpha would make the bars translucent against
         * whatever the output surface happens to hold — the picture would fade
         * up from whatever is *behind* the canvas instead of from black. The
         * bars go dark with the picture because the RGB is multiplied, which is
         * the intended look: the whole frame opens from black.
         */
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uProgress;
void main() {
    vec4 color = texture2D(uTexture, vTexCoord);
    // Eased so the fade does not step out of black in its first frames, where
    // 8-bit output has the fewest code values to spend.
    float eased = smoothstep(0.0, 1.0, uProgress);
    // `uIntensity` is the depth the fade starts from: 1 opens on true black,
    // lower opens part-way up. At progress 1 this is exactly 1.0 whatever the
    // intensity, which is what makes the settled clip a plain passthrough.
    float lift = mix(1.0 - uIntensity, 1.0, eased);
    gl_FragColor = vec4(color.rgb * lift, color.a);
}
"""
    }
}
