package com.techfamz.slimshotai.nativepreview.gl

/**
 * GLSL sources for every transition SlimShot renders.
 *
 * The transition identifiers here must match `EditorTransition` on the Dart
 * side (`lib/features/video_editor/logic/transitions/transition_catalog.dart`).
 * Adding a transition means one entry there and one shader body here.
 *
 * Conventions shared by every fragment shader:
 *
 * * `uOutgoing` and `uIncoming` are **both live decoder outputs** â€” external
 *   OES textures fed by two independent players. Neither is a frozen capture.
 * * Each has its own transform matrix (`uTexMatrixOutgoing`,
 *   `uTexMatrixIncoming`) because the two clips can differ in crop, rotation
 *   and scaling. Sampling helpers apply them, which also means a shader may
 *   offset a coordinate *before* the matrix â€” needed by slide and push, where
 *   offsetting afterwards would shift along the wrong axis on rotated media.
 * * `vTexCoord` is `0..1` with y increasing *up* the screen.
 * * `uProgress` runs `0..1` across the transition window.
 */
internal object TransitionShaders {

    /**
     * Shared vertex shader. It deliberately does **not** apply `uTexMatrix`:
     * transitions such as slide and push sample the incoming frame at shifted
     * coordinates, which has to happen before the matrix is applied or any
     * rotation baked into the matrix would shift the image along the wrong
     * axis.
     */
    const val VERTEX_SHADER = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
void main() {
    gl_Position = aPosition;
    vTexCoord = aTexCoord;
}
"""

    /**
     * Builds the shared header for a given pair of source kinds.
     *
     * A lane holds either decoder output (an external OES texture) or a still
     * photo (an ordinary 2D texture uploaded from a `Bitmap`). GLSL cannot pick
     * a sampler type at runtime and has no generic sampler parameter, so the
     * two sampling functions are generated per combination and the program
     * cache keys on it. Only the combinations a timeline actually uses ever get
     * compiled.
     */
    private fun fragmentHeader(
        incomingIsImage: Boolean,
        outgoingIsImage: Boolean,
    ): String {
        val incomingSampler = if (incomingIsImage) "sampler2D" else "samplerExternalOES"
        val outgoingSampler = if (outgoingIsImage) "sampler2D" else "samplerExternalOES"

        return """#extension GL_OES_EGL_image_external : require
precision mediump float;
varying vec2 vTexCoord;
uniform $incomingSampler uIncoming;
uniform $outgoingSampler uOutgoing;
uniform mat4 uTexMatrixIncoming;
uniform mat4 uTexMatrixOutgoing;
uniform vec2 uFitIncoming;
uniform vec2 uFitOutgoing;
uniform vec2 uPanIncoming;
uniform vec2 uPanOutgoing;
uniform float uRotationIncoming;
uniform float uRotationOutgoing;
uniform float uCanvasAspect;
uniform vec3 uBackground;
uniform sampler2D uBackgroundImage;
uniform float uBackgroundImageOn;
uniform vec2 uBackgroundImageFit;
uniform vec4 uContentRectIncoming;
uniform vec4 uContentRectOutgoing;
uniform mat4 uColorMatrix;
uniform vec4 uColorOffset;
uniform float uColorEnabled;
uniform mat4 uClipMatrixIncoming;
uniform vec4 uClipOffsetIncoming;
uniform float uClipColorIncoming;
uniform mat4 uClipMatrixOutgoing;
uniform vec4 uClipOffsetOutgoing;
uniform float uClipColorOutgoing;
uniform float uProgress;

// A clip's own filter, applied to that clip's pixels only.
//
// This runs *before* a transition mixes the two lanes, which is the whole point
// of a per-clip filter: two clips carrying different looks cross-fade between
// those looks rather than the blend being graded as one image. It is applied to
// sampled texels only, never to the letterbox, or the bars would take the
// filter's colour offset and stop being black.
vec4 gradeClip(vec4 c, mat4 m, vec4 o, float enabled) {
    if (enabled < 0.5) {
        return c;
    }
    vec4 graded = m * c + o;
    return vec4(clamp(graded.rgb, 0.0, 1.0), c.a);
}

// Fraction of the canvas each clip occupies once fitted inside it. A clip that
// matches the canvas is (1,1); a landscape clip in a portrait canvas is
// (1, canvasAspect/clipAspect), leaving bars above and below.
//
// uContentRect* is the part of *that lane's* source frame that reaches the
// canvas, with crop, zoom and pan already resolved into one rectangle. Sampling
// through it here means zoom magnifies the picture rather than the letterbox
// bars. **One per lane**, like the fit and the pan: a single canvas rect gave a
// transition one rect for two clips, which is what made a per-clip crop
// impossible.
//
// The two functions are identical apart from their sampler type — see
// fragmentHeader.
// uPan* is the clip's own position on the canvas, in canvas fractions — the
// user dragging a selected clip around. It moves where the picture *sits*,
// where uContentRect* moves what part of the source is *shown*.
//
// Pan is stored y-DOWN, like every other canvas coordinate in the contract
// (overlay centres, drag deltas, bitmap rows). This sampling space runs y-UP —
// texcoord (0,0) sits at the bottom-left vertex — so y is negated here, at the
// one place the two frames meet. Skip that and a downward drag moves the clip
// up, which shipped once.
// Rotates a canvas coordinate about the canvas centre by `radians`.
//
// **In an aspect-true space, or it shears.** The canvas is 9:16, so a unit of
// u is not a unit of v; rotating in raw uv squashes the picture into a rhombus
// at 45 degrees. Scale x by the aspect first so both axes are the same size,
// rotate, scale back. `OverlayRenderer.writeCorners` documents the identical
// trap for overlays.
//
// Applied to the point being *sampled*, so the rotation is inverse: to draw
// the clip turned clockwise we look up each pixel at its counter-clockwise
// source. Which is why the sign here is the opposite of what a diagram of the
// clip turning would suggest.
vec2 rotateCanvas(vec2 uv, float radians) {
    vec2 p = (uv - 0.5) * vec2(uCanvasAspect, 1.0);
    float s = sin(-radians);
    float c = cos(-radians);
    p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
    return p / vec2(uCanvasAspect, 1.0) + 0.5;
}

// **Order: pan, then rotate, then fit.** Undoing the transform in reverse of how
// the clip was built: the clip is fitted into the canvas, then spun about its
// own centre, then dragged into place. So sampling first removes the pan (to
// find the clip's centre), then un-rotates about it, then un-fits. Rotating
// *before* removing the pan would spin the clip about the canvas centre rather
// than its own, and a clip dragged to the corner would orbit instead of turn.
// The letterbox fill at this fragment: the project colour, or the background
// photo covering the canvas. Read at vTexCoord — the fragment's own canvas
// position — rather than at the uv a transition may have warped, so the photo
// stays put while the clips move over it. uBackgroundImageFit is the visible
// fraction of the photo per axis, centred (BackgroundFit.cover); bitmaps are
// top-left origin, so v is flipped.
vec4 backgroundAt() {
    if (uBackgroundImageOn < 0.5) {
        return vec4(uBackground, 1.0);
    }
    vec2 bg = (vTexCoord - 0.5) * uBackgroundImageFit + 0.5;
    return texture2D(uBackgroundImage, vec2(bg.x, 1.0 - bg.y));
}

vec4 incomingAt(vec2 uv) {
    vec2 centred = rotateCanvas(uv - uPanIncoming * vec2(1.0, -1.0), uRotationIncoming);
    vec2 fitted = (centred - 0.5) / uFitIncoming + 0.5;
    // Outside the fitted rect is background, not stretched edge pixels.
    if (fitted.x < 0.0 || fitted.x > 1.0 || fitted.y < 0.0 || fitted.y > 1.0) {
        return backgroundAt();
    }
    vec2 source = uContentRectIncoming.xy + fitted * uContentRectIncoming.zw;
    vec4 texel = texture2D(uIncoming, (uTexMatrixIncoming * vec4(source, 0.0, 1.0)).xy);
    return gradeClip(texel, uClipMatrixIncoming, uClipOffsetIncoming, uClipColorIncoming);
}

vec4 outgoingAt(vec2 uv) {
    vec2 centred = rotateCanvas(uv - uPanOutgoing * vec2(1.0, -1.0), uRotationOutgoing);
    vec2 fitted = (centred - 0.5) / uFitOutgoing + 0.5;
    if (fitted.x < 0.0 || fitted.x > 1.0 || fitted.y < 0.0 || fitted.y > 1.0) {
        return backgroundAt();
    }
    vec2 source = uContentRectOutgoing.xy + fitted * uContentRectOutgoing.zw;
    vec4 texel = texture2D(uOutgoing, (uTexMatrixOutgoing * vec4(source, 0.0, 1.0)).xy);
    return gradeClip(texel, uClipMatrixOutgoing, uClipOffsetOutgoing, uClipColorOutgoing);
}

float ease(float t) {
    return t * t * (3.0 - 2.0 * t);
}

// The project-wide look, applied once to the finished frame.
//
// This is the grade that belongs to the whole edit, so it must not be applied
// per clip: doing that would grade a transition's two lanes separately and then
// blend the results, which is not the same picture. A clip's *own* filter is a
// different thing and is applied in gradeClip, before the blend.
void outputColor(vec4 c) {
    if (uColorEnabled < 0.5) {
        gl_FragColor = c;
        return;
    }
    vec4 graded = uColorMatrix * c + uColorOffset;
    gl_FragColor = vec4(clamp(graded.rgb, 0.0, 1.0), c.a);
}
"""
    }

    private val PASSTHROUGH_BODY = """
void main() {
    outputColor(incomingAt(vTexCoord));
}
"""

    private val DISSOLVE = """
void main() {
    outputColor(mix(outgoingAt(vTexCoord), incomingAt(vTexCoord), uProgress));
}
"""

    private val FADE_TO_BLACK = """
void main() {
    float p = uProgress;
    vec3 c;
    if (p < 0.5) {
        c = outgoingAt(vTexCoord).rgb * (1.0 - p * 2.0);
    } else {
        c = incomingAt(vTexCoord).rgb * ((p - 0.5) * 2.0);
    }
    outputColor(vec4(c, 1.0));
}
"""

    private val FADE_TO_WHITE = """
void main() {
    float p = uProgress;
    vec3 white = vec3(1.0);
    vec3 c;
    if (p < 0.5) {
        c = mix(outgoingAt(vTexCoord).rgb, white, p * 2.0);
    } else {
        c = mix(white, incomingAt(vTexCoord).rgb, (p - 0.5) * 2.0);
    }
    outputColor(vec4(c, 1.0));
}
"""

    /** Incoming slides in from the right; the outgoing frame stays put. */
    private val SLIDE = """
void main() {
    float edge = 1.0 - ease(uProgress);
    if (vTexCoord.x >= edge) {
        outputColor(incomingAt(vec2(vTexCoord.x - edge, vTexCoord.y)));
    } else {
        outputColor(outgoingAt(vTexCoord));
    }
}
"""

    /** Incoming pushes the outgoing frame off to the left. */
    private val PUSH = """
void main() {
    float p = ease(uProgress);
    float edge = 1.0 - p;
    if (vTexCoord.x >= edge) {
        outputColor(incomingAt(vec2(vTexCoord.x - edge, vTexCoord.y)));
    } else {
        outputColor(outgoingAt(vec2(vTexCoord.x + p, vTexCoord.y)));
    }
}
"""

    /** Hard-edged reveal travelling right to left. */
    private val WIPE = """
void main() {
    float edge = 1.0 - uProgress;
    if (vTexCoord.x >= edge) {
        outputColor(incomingAt(vTexCoord));
    } else {
        outputColor(outgoingAt(vTexCoord));
    }
}
"""

    /**
     * Feathered directional wipe. [coordExpression] is the axis the soft edge
     * sweeps along, expressed so that it approaches 0 where the incoming clip
     * takes over first.
     */
    private fun smoothWipe(coordExpression: String) = """
void main() {
    const float feather = 0.35;
    float edge = ease(uProgress) * (1.0 + feather) - feather;
    float outgoingWeight = smoothstep(edge, edge + feather, $coordExpression);
    outputColor(mix(incomingAt(vTexCoord), outgoingAt(vTexCoord), outgoingWeight));
}
"""

    /** Both frames scale toward the viewer while the incoming settles to 1:1. */
    private val ZOOM_IN = """
void main() {
    float p = ease(uProgress);
    vec2 centre = vec2(0.5);
    vec2 outUv = (vTexCoord - centre) / (1.0 + 0.35 * p) + centre;
    vec2 inUv = (vTexCoord - centre) / (1.35 - 0.35 * p) + centre;
    outputColor(mix(outgoingAt(outUv), incomingAt(inUv), p));
}
"""

    private val bodiesByType: Map<String, String> = mapOf(
        "dissolve" to DISSOLVE,
        "fadeToBlack" to FADE_TO_BLACK,
        "fadeToWhite" to FADE_TO_WHITE,
        "slide" to SLIDE,
        "push" to PUSH,
        "wipe" to WIPE,
        // Named for the direction the wipe travels.
        "smoothLeft" to smoothWipe("1.0 - vTexCoord.x"),
        "smoothRight" to smoothWipe("vTexCoord.x"),
        "smoothUp" to smoothWipe("vTexCoord.y"),
        "smoothDown" to smoothWipe("1.0 - vTexCoord.y"),
        "zoomIn" to ZOOM_IN,
    )

    val supportedTypes: Set<String> = bodiesByType.keys

    fun isSupported(type: String?): Boolean = type != null && bodiesByType.containsKey(type)

    /**
     * Fragment shader for [type], for the given pair of source kinds.
     *
     * Unknown identifiers fall back to a crossfade so a draft naming a retired
     * transition still renders something sensible rather than failing to link.
     */
    fun fragmentShaderFor(
        type: String,
        incomingIsImage: Boolean,
        outgoingIsImage: Boolean,
    ): String {
        val body = bodiesByType[type] ?: DISSOLVE
        return fragmentHeader(incomingIsImage, outgoingIsImage) + body
    }

    /** Straight passthrough of one lane, used whenever no transition is active. */
    fun passthroughFragment(isImage: Boolean): String {
        // Only the incoming sampler is used; the outgoing one is declared but
        // optimised out by the compiler.
        return fragmentHeader(isImage, isImage) + PASSTHROUGH_BODY
    }
}
