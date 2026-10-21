package com.techfamz.slimshotai.nativepreview.gl.effects

import android.opengl.GLES20

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
 * * **A pan's rate is per bar; a shake's is per second.** A drift that crosses
 *   the frame over the bar takes 3s on a 3s bar and 90s on a 90s one — for a
 *   pan exactly right, the gesture is "across this bar". A shake has a speed
 *   of its own, so the shakes keep time in the bar's own seconds
 *   (`barSeconds`) — timeline time, never wall clock, so the file shakes as
 *   the canvas did however fast the export runs.
 * * **There is no settle, and none is wanted.** A continuous look is displaced
 *   at its last frame as much as at its first. The settle rule belongs to the
 *   intro category.
 *
 * Every displacement here is a pure function of the bar's clock — **never
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
 * The shake shaders' shared mapping: the canvas point at [uv] sampled through a
 * camera pose `(dx, dy, radians, zoom)`, offsets in short sides. **The same
 * arithmetic as [CameraShake.sampleOf]**, which the cover is checked against —
 * if one changes the other must.
 */
private const val SHAKE_UV = """
vec2 shakeUv(vec4 pose, vec2 uv) {
    vec2 extent = vec2(0.5 * max(1.0, uAspect), 0.5 * max(1.0, 1.0 / uAspect));
    vec2 p = (uv - vec2(0.5)) * 2.0 * extent;
    vec2 q = (p - pose.xy) / pose.w;
    float c = cos(pose.z);
    float s = sin(pose.z);
    vec2 r = vec2(c * q.x + s * q.y, -s * q.x + c * q.y);
    return r / (2.0 * extent) + vec2(0.5);
}
"""

/**
 * A camera held in a hand: a slow sway, a faint tremor, a slight turn.
 *
 * The pose is worked out on the CPU each frame ([CameraShake.HANDHELD]) from the
 * bar's own seconds and arrives as `uPose`. It used to be a fresh hashed offset
 * per frame, which on the device sat still and elsewhere vibrated
 * (device-reported: not realistic).
 */
internal class HandheldPass(program: FullFrameProgram) :
    SingleFramePass("handheld", program) {

    private val uPose = program.location("uPose")

    override fun bindExtraUniforms(viewportWidth: Int, viewportHeight: Int) {
        val aspect = viewportWidth.toDouble() / viewportHeight.toDouble()
        val pose = CameraShake.poseAt(CameraShake.HANDHELD, seconds.toDouble(), intensity, aspect)
        GLES20.glUniform4f(uPose, pose.dx.toFloat(), pose.dy.toFloat(), pose.radians.toFloat(), pose.zoom.toFloat())
    }

    internal companion object {
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uAspect;
uniform vec4 uPose;
$SHAKE_UV
void main() {
    gl_FragColor = texture2D(uTexture, clamp(shakeUv(uPose, vTexCoord), 0.0, 1.0));
}
"""
    }
}

/**
 * A hard shake: fast jolts, turns of a few degrees, a punch in now and then,
 * and the blur a shutter records of a camera moving that fast.
 *
 * Its own motion ([CameraShake.SUPER_SHAKE]), not Handheld turned up: past a
 * certain speed a shake is jolts, not sway. The blur samples along the path
 * each point travelled during the exposure — from the pose
 * [CameraShake.EXPOSURE_SECONDS] earlier (`uPosePrev`) to the pose now — so a
 * turn blurs round and a jolt blurs straight, exactly as far as it moved. Five
 * taps, no loop.
 */
internal class SuperShakePass(program: FullFrameProgram) :
    SingleFramePass("super_shake", program) {

    private val uPose = program.location("uPose")
    private val uPosePrev = program.location("uPosePrev")

    override fun bindExtraUniforms(viewportWidth: Int, viewportHeight: Int) {
        val aspect = viewportWidth.toDouble() / viewportHeight.toDouble()
        val now = seconds.toDouble()
        val style = CameraShake.SUPER_SHAKE
        val pose = CameraShake.poseAt(style, now, intensity, aspect)
        val prev = CameraShake.poseAt(style, now - CameraShake.EXPOSURE_SECONDS, intensity, aspect)
        GLES20.glUniform4f(uPose, pose.dx.toFloat(), pose.dy.toFloat(), pose.radians.toFloat(), pose.zoom.toFloat())
        GLES20.glUniform4f(uPosePrev, prev.dx.toFloat(), prev.dy.toFloat(), prev.radians.toFloat(), prev.zoom.toFloat())
    }

    internal companion object {
        val FRAGMENT = """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uAspect;
uniform vec4 uPose;
uniform vec4 uPosePrev;
$SHAKE_UV
void main() {
    vec2 now = shakeUv(uPose, vTexCoord);
    vec2 then = shakeUv(uPosePrev, vTexCoord);
    vec4 sum = texture2D(uTexture, clamp(now, 0.0, 1.0));
    sum += texture2D(uTexture, clamp(mix(now, then, 0.25), 0.0, 1.0));
    sum += texture2D(uTexture, clamp(mix(now, then, 0.5), 0.0, 1.0));
    sum += texture2D(uTexture, clamp(mix(now, then, 0.75), 0.0, 1.0));
    sum += texture2D(uTexture, clamp(then, 0.0, 1.0));
    gl_FragColor = sum * 0.2;
}
"""
    }
}
