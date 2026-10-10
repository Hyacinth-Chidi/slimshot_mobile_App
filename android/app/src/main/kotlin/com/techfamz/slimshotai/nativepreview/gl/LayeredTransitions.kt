package com.techfamz.slimshotai.nativepreview.gl

/**
 * The bodies of the layered transitions — each a `vec4 transition(vec2 uv)`
 * written against the GL Transitions API that `TransitionShaders`' layered
 * header provides over the two layers (`getFromColor`, `getToColor`,
 * `progress`, `ratio`).
 *
 * Most are ports from gl-transitions.com (MIT). Each keeps its author's credit
 * and lists its changes, which are only ever these:
 *
 * * **Parameters are constants**, at the library's defaults. A uniform nothing
 *   binds reads as zero on a device, which silently breaks a port.
 * * **Loops count with an int against a constant** — ES 2.0's Appendix A
 *   form, which every driver must take.
 * * **No sin-fract hash.** `fract(sin(x) * 43758.5)` loses its fraction in
 *   `mediump`, the grain banding CLAUDE.md records; jitter is interleaved
 *   gradient noise on `gl_FragCoord` instead.
 * * **Alpha is carried through.** A layer is premultiplied and transparent
 *   where no clip is, and the result is laid over the background; a port that
 *   forces alpha to 1 paints black where the background should show.
 *
 * How a transition *looks* can only be checked on a device. Their structure is
 * pinned by `TransitionShadersLayeredTest`, and every one is validated with
 * `glslangValidator`.
 */
internal object LayeredTransitions {

    /**
     * A layered transition's body, a cheaper one where it has many steps, and
     * its own vertex shader where it has work that is the same for every
     * pixel of a frame — null for the shared one.
     */
    class Body(val full: String, val light: String? = null, val vertex: String? = null)

    private fun withSteps(source: String, full: Int, light: Int): Body = Body(
        full = source,
        light = source.replace("const int STEPS = $full;", "const int STEPS = $light;"),
    )

    /** The interleaved-gradient-noise jitter several ports use in place of a hash. */
    private const val IGN = "fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))))"

    // ---------------------------------------------------------------- Blur

    /**
     * Zoom Blur — CrossZoom. License: MIT. Author: rectalogic, ported by gre
     * from https://gist.github.com/rectalogic/b86b90161503a0023231, itself based
     * on glfx.js's zoom blur (Evan Wallace). 41 steps, each reading both layers.
     */
    private const val ZOOM_BLUR = """
const float STRENGTH = 0.4;
const float PI = 3.141592653589793;
const int STEPS = 40;

float Linear_ease(float begin, float change, float duration, float time) {
    return change * time / duration + begin;
}

float Exponential_easeInOut(float begin, float change, float duration, float time) {
    if (time == 0.0) {
        return begin;
    } else if (time == duration) {
        return begin + change;
    }
    time = time / (duration / 2.0);
    if (time < 1.0) {
        return change / 2.0 * pow(2.0, 10.0 * (time - 1.0)) + begin;
    }
    return change / 2.0 * (-pow(2.0, -10.0 * (time - 1.0)) + 2.0) + begin;
}

float Sinusoidal_easeInOut(float begin, float change, float duration, float time) {
    return -change / 2.0 * (cos(PI * time / duration) - 1.0) + begin;
}

vec4 crossFade(vec2 uv, float dissolve) {
    return mix(getFromColor(uv), getToColor(uv), dissolve);
}

vec4 transition(vec2 uv) {
    // The centre travels across the middle half of the frame.
    vec2 center = vec2(Linear_ease(0.25, 0.5, 1.0, progress), 0.5);
    float dissolve = Exponential_easeInOut(0.0, 1.0, 1.0, progress);
    // Mirrored sinusoidal loop: 0 -> strength -> 0.
    float strength = Sinusoidal_easeInOut(0.0, STRENGTH, 0.5, progress);
    vec4 color = vec4(0.0);
    float total = 0.0;
    vec2 toCenter = center - uv;
    // Jitter the steps so their fixed count does not show as rings.
    float offset = $IGN;
    for (int i = 0; i <= STEPS; i++) {
        float percent = (float(i) + offset) / float(STEPS);
        float weight = 4.0 * (percent - percent * percent);
        color += crossFade(uv + toCenter * percent * strength, dissolve) * weight;
        total += weight;
    }
    return color / total;
}
"""

    /**
     * Dreamy Zoom — DreamyZoom. License: MIT. Author: Zeh Fernando. The flash
     * is added to the colour and leaves alpha alone, which laid over the
     * background is exactly the original's `c + flash`.
     */
    private const val DREAMY_ZOOM = """
#define DEG2RAD 0.03926990816987241548078304229099 // 1/180*PI

// In degrees
const float rotation = 6.0;
// Multiplier
const float scale = 1.2;

vec4 transition(vec2 uv) {
  float phase = progress < 0.5 ? progress * 2.0 : (progress - 0.5) * 2.0;
  float angleOffset = progress < 0.5 ? mix(0.0, rotation * DEG2RAD, phase) : mix(-rotation * DEG2RAD, 0.0, phase);
  float newScale = progress < 0.5 ? mix(1.0, scale, phase) : mix(scale, 1.0, phase);

  vec2 center = vec2(0.0, 0.0);

  vec2 p = (uv.xy - vec2(0.5, 0.5)) / newScale * vec2(ratio, 1.0);

  float angle = atan(p.y, p.x) + angleOffset;
  float dist = distance(center, p);
  p.x = cos(angle) * dist / ratio + 0.5;
  p.y = sin(angle) * dist + 0.5;
  vec4 c = progress < 0.5 ? getFromColor(p) : getToColor(p);

  float flash = progress < 0.5 ? mix(0.0, 1.0, phase) : mix(1.0, 0.0, phase);
  return vec4(c.rgb + flash, c.a);
}
"""

    /**
     * Motion Blur — tangentMotionBlur. License: MIT. Author: chenkai, ported
     * from https://codertw.com/%E7%A8%8B%E5%BC%8F%E8%AA%9E%E8%A8%80/671116/.
     * The outgoing clip is flung away along a curve. 21 steps, one layer each.
     */
    private const val MOTION_BLUR = """
const int STEPS = 20;

vec4 motionBlurFrom(vec2 _st, vec2 speed) {
    vec4 color = vec4(0.0);
    float total = 0.0;
    float offset = $IGN;
    for (int i = 0; i <= STEPS; i++) {
        float percent = (float(i) + offset) / float(STEPS);
        float weight = 4.0 * (percent - percent * percent);
        vec2 newuv = fract(_st + speed * percent);
        color += getFromColor(newuv) * weight;
        total += weight;
    }
    return color / total;
}

vec4 motionBlurTo(vec2 _st, vec2 speed) {
    vec4 color = vec4(0.0);
    float total = 0.0;
    float offset = $IGN;
    for (int i = 0; i <= STEPS; i++) {
        float percent = (float(i) + offset) / float(STEPS);
        float weight = 4.0 * (percent - percent * percent);
        vec2 newuv = fract(_st + speed * percent);
        color += getToColor(newuv) * weight;
        total += weight;
    }
    return color / total;
}

// bezier in gpu
float A(float aA1, float aA2) {
    return 1.0 - 3.0 * aA2 + 3.0 * aA1;
}
float B(float aA1, float aA2) {
    return 3.0 * aA2 - 6.0 * aA1;
}
float C(float aA1) {
    return 3.0 * aA1;
}
float GetSlope(float aT, float aA1, float aA2) {
    return 3.0 * A(aA1, aA2) * aT * aT + 2.0 * B(aA1, aA2) * aT + C(aA1);
}
float CalcBezier(float aT, float aA1, float aA2) {
    return ((A(aA1, aA2) * aT + B(aA1, aA2)) * aT + C(aA1)) * aT;
}
float GetTForX(float aX, float mX1, float mX2) {
    float aGuessT = aX;
    for (int i = 0; i < 4; ++i) {
        float currentSlope = GetSlope(aGuessT, mX1, mX2);
        if (currentSlope == 0.0) return aGuessT;
        float currentX = CalcBezier(aGuessT, mX1, mX2) - aX;
        aGuessT -= currentX / currentSlope;
    }
    return aGuessT;
}
float KeySpline(float aX, float mX1, float mY1, float mX2, float mY2) {
    if (mX1 == mY1 && mX2 == mY2) return aX;
    return CalcBezier(GetTForX(aX, mX1, mX2), mY1, mY2);
}

float normpdf(float x) {
    float d = x - 0.5;
    return exp(-20.0 * d * d);
}

vec2 rotateUv(vec2 uv, float angle, vec2 anchor) {
    uv = uv - anchor;
    float s = sin(angle);
    float c = cos(angle);
    mat2 m = mat2(c, -s, s, c);
    uv = m * uv;
    uv += anchor;
    return uv;
}

vec4 transition(vec2 uv) {
    vec2 myst = uv;
    float easingTime = KeySpline(progress, 0.68, 0.01, 0.17, 0.98);
    float blur = normpdf(easingTime);
    float r = 0.0;
    float rotation = 3.14159;
    if (easingTime <= 0.5) {
        r = rotation * easingTime;
    } else {
        r = -rotation + rotation * easingTime;
    }

    vec2 mystCurrent = myst;
    mystCurrent.y *= 1.0 / ratio;
    mystCurrent = rotateUv(mystCurrent, r, vec2(1.0, 0.0));
    mystCurrent.y *= ratio;

    // One frame ahead at 30fps, for the speed along the tangent.
    float timeInterval = 0.0167 * 2.0;
    if (easingTime <= 0.5) {
        r = rotation * (easingTime + timeInterval);
    } else {
        r = -rotation + rotation * (easingTime + timeInterval);
    }

    vec2 mystNext = myst;
    mystNext.y *= 1.0 / ratio;
    mystNext = rotateUv(mystNext, r, vec2(1.0, 0.0));
    mystNext.y *= ratio;

    vec2 speed = (mystNext - mystCurrent) / timeInterval * blur * 0.5;
    if (easingTime <= 0.5) {
        return motionBlurFrom(mystCurrent, speed);
    } else {
        return motionBlurTo(mystCurrent, speed);
    }
}
"""

    /** Defocus — DefocusBlur. License: MIT. Author: Sergey Kosarevsky. 13 taps per layer. */
    private const val DEFOCUS = """
const float blurSize = 0.02;

vec4 transition(vec2 uv) {
  float T = progress;
  float half_ = 0.5;
  float D = (T < half_) ? mix(0.0, blurSize, T / half_) : mix(blurSize, 0.0, (T - half_) / half_);
  vec4 C0 = getFromColor(uv);
  vec4 C1 = getToColor(uv);
  C0 += getFromColor(vec2(-0.326, -0.406) * D + uv);
  C1 += getToColor(vec2(-0.326, -0.406) * D + uv);
  C0 += getFromColor(vec2(-0.840, -0.074) * D + uv);
  C1 += getToColor(vec2(-0.840, -0.074) * D + uv);
  C0 += getFromColor(vec2(-0.696,  0.457) * D + uv);
  C1 += getToColor(vec2(-0.696,  0.457) * D + uv);
  C0 += getFromColor(vec2(-0.203,  0.621) * D + uv);
  C1 += getToColor(vec2(-0.203,  0.621) * D + uv);
  C0 += getFromColor(vec2( 0.962, -0.195) * D + uv);
  C1 += getToColor(vec2( 0.962, -0.195) * D + uv);
  C0 += getFromColor(vec2( 0.473, -0.480) * D + uv);
  C1 += getToColor(vec2( 0.473, -0.480) * D + uv);
  C0 += getFromColor(vec2( 0.519,  0.767) * D + uv);
  C1 += getToColor(vec2( 0.519,  0.767) * D + uv);
  C0 += getFromColor(vec2( 0.185, -0.893) * D + uv);
  C1 += getToColor(vec2( 0.185, -0.893) * D + uv);
  C0 += getFromColor(vec2( 0.507,  0.064) * D + uv);
  C1 += getToColor(vec2( 0.507,  0.064) * D + uv);
  C0 += getFromColor(vec2( 0.896,  0.412) * D + uv);
  C1 += getToColor(vec2( 0.896,  0.412) * D + uv);
  C0 += getFromColor(vec2(-0.322, -0.933) * D + uv);
  C1 += getToColor(vec2(-0.322, -0.933) * D + uv);
  C0 += getFromColor(vec2(-0.792, -0.598) * D + uv);
  C1 += getToColor(vec2(-0.792, -0.598) * D + uv);
  C0 /= 13.0;
  C1 /= 13.0;
  return mix(C0, C1, T);
}
"""

    // -------------------------------------------------------------- Motion

    /**
     * Slide & Scale — DirectionalScaled. License: MIT. Author: Thibaut
     * Foussard, based on Directional by Gaëtan Renaudeau. One transition per
     * direction, named for the way the picture travels; only the direction
     * line differs. `pow(sin(x), 1.0)` became `sin(x)`: `pow` of a negative
     * base is undefined, and `sin(PI)` lands a hair below zero on a GPU.
     */
    private fun slideScale(direction: String) = """
#define PI acos(-1.0)

const vec2 direction = $direction;
const float scale = 0.7;

float parabola(float x) {
  return sin(x * PI);
}

vec4 transition(vec2 uv) {
  float easedProgress = pow(sin(progress * PI / 2.0), 3.0);
  vec2 p = uv + easedProgress * sign(direction);
  vec2 f = fract(p);

  float s = 1.0 - (1.0 - (1.0 / scale)) * parabola(progress);
  f = (f - 0.5) * s + 0.5;

  float mixer = step(0.0, p.y) * step(p.y, 1.0) * step(0.0, p.x) * step(p.x, 1.0);
  vec4 col = mix(getToColor(f), getFromColor(f), mixer);

  float border = step(0.0, f.x) * step(0.0, (1.0 - f.x)) * step(0.0, f.y) * step(0.0, 1.0 - f.y);
  col *= border;

  return col;
}
"""

    private const val SPLIT_BOUNDS = """
const bool reverse = false;

const vec2 boundMin = vec2(0.0, 0.0);
const vec2 boundMax = vec2(1.0, 1.0);

bool inBounds(vec2 p) {
  return all(lessThan(boundMin, p)) && all(lessThan(p, boundMax));
}
"""

    /** Split In — splitSlideInHorizontal. License: MIT. Author: OllyOllyOlly. */
    private const val SPLIT_IN = SPLIT_BOUNDS + """
vec4 transition(vec2 uv) {
  float modifier = reverse ? -1.0 : 1.0;
  vec2 toP = (uv.y > 0.5) ?
    vec2((uv.x - (progress * modifier)) + modifier, uv.y) :
    vec2((uv.x + (progress * modifier)) - modifier, uv.y);

  vec2 fromP = uv;

  return inBounds(toP) ? getToColor(toP) : getFromColor(fromP);
}
"""

    /** Split Out — splitSlideOutHorizontal. License: MIT. Author: OllyOllyOlly. */
    private const val SPLIT_OUT = SPLIT_BOUNDS + """
vec4 transition(vec2 uv) {
  float modifier = (uv.y > 0.5 ? 1.0 : -1.0) * (reverse ? -1.0 : 1.0);
  vec2 p = vec2(uv.x + (progress * modifier), uv.y);

  return inBounds(p) ? getFromColor(p) : getToColor(uv);
}
"""

    /**
     * Bounce — Bounce. License: MIT. Author: Adrian Purser. The shadow darkens
     * the picture under it and keeps its coverage, where the original blended
     * toward a translucent black — the same colour on an opaque frame, without
     * punching a hole the background would show through.
     */
    private const val BOUNCE = """
const vec4 shadow_colour = vec4(0.0, 0.0, 0.0, 0.6);
const float shadow_height = 0.075;
const float bounces = 3.0;

const float PI = 3.14159265358;

vec4 transition(vec2 uv) {
  float time = progress;
  float stime = sin(time * PI / 2.0);
  float phase = time * PI * bounces;
  float y = (abs(cos(phase))) * (1.0 - stime);
  float d = uv.y - y;
  vec4 to = getToColor(uv);
  float shade = step(d, shadow_height) * (1.0 - mix(
    ((d / shadow_height) * shadow_colour.a) + (1.0 - shadow_colour.a),
    1.0,
    smoothstep(0.95, 1.0, progress) // fade-out the shadow at the end
  ));
  return mix(
    mix(to, vec4(shadow_colour.rgb * to.a, to.a), shade),
    getFromColor(vec2(uv.x, uv.y + (1.0 - y))),
    step(d, 0.0)
  );
}
"""

    /**
     * Swirl — Swirl. License: MIT. Author: Sergey Kosarevsky
     * (http://www.linderdaum.com), ported by gre from
     * https://gist.github.com/corporateshark/cacfedb8cca0f5ce3f7c.
     */
    private const val SWIRL = """
vec4 transition(vec2 UV) {
  float Radius = 1.0;
  float T = progress;
  UV -= vec2(0.5, 0.5);
  float Dist = length(UV);
  if (Dist < Radius) {
    float Percent = (Radius - Dist) / Radius;
    float A = (T <= 0.5) ? mix(0.0, 1.0, T / 0.5) : mix(1.0, 0.0, (T - 0.5) / 0.5);
    float Theta = Percent * Percent * A * 8.0 * 3.14159;
    float S = sin(Theta);
    float C = cos(Theta);
    UV = vec2(dot(UV, vec2(C, -S)), dot(UV, vec2(S, C)));
  }
  UV += vec2(0.5, 0.5);
  vec4 C0 = getFromColor(UV);
  vec4 C1 = getToColor(UV);
  return mix(C0, C1, T);
}
"""

    /**
     * Spin Away — RotateScaleVanish. License: MIT. Author: Mark Craig
     * (mrmcsoftware), © 2022. The outgoing clip spins and shrinks away.
     */
    private const val SPIN_AWAY = """
const bool FadeInSecond = true;
const bool ReverseEffect = false;
const bool ReverseRotation = false;

#define M_PI 3.14159265358979323846
#define _TWOPI 6.283185307179586476925286766559

vec4 transition(vec2 uv) {
  vec2 iResolution = vec2(ratio, 1.0);
  float t = ReverseEffect ? 1.0 - progress : progress;
  float theta = ReverseRotation ? _TWOPI * t : -_TWOPI * t;
  float c1 = cos(theta);
  float s1 = sin(theta);
  float rad = max(0.00001, 1.0 - t);
  float xc1 = (uv.x - 0.5) * iResolution.x;
  float yc1 = (uv.y - 0.5) * iResolution.y;
  float xc2 = (xc1 * c1 - yc1 * s1) / rad;
  float yc2 = (xc1 * s1 + yc1 * c1) / rad;
  vec2 uv2 = vec2(xc2 + iResolution.x / 2.0, yc2 + iResolution.y / 2.0);
  vec4 col3;
  vec4 ColorTo = ReverseEffect ? getFromColor(uv) : getToColor(uv);
  if ((uv2.x >= 0.0) && (uv2.x <= iResolution.x) && (uv2.y >= 0.0) && (uv2.y <= iResolution.y)) {
    uv2 /= iResolution;
    col3 = ReverseEffect ? getToColor(uv2) : getFromColor(uv2);
  } else {
    col3 = FadeInSecond ? vec4(0.0, 0.0, 0.0, 1.0) : ColorTo;
  }
  return (1.0 - t) * col3 + t * ColorTo;
}
"""

    /** Zoom In-Out — zoomInOut. License: MIT. Author: OllyOllyOlly. */
    private const val ZOOM_IN_OUT = """
vec2 zoom(vec2 uv, float amount) {
  return 0.5 + ((uv - 0.5) * (1.0 - amount));
}

vec4 transition(vec2 uv) {
  float zoomFrom = smoothstep(0.0, 1.0, progress * 2.0);
  float zoomTo = smoothstep(0.0, 1.0, (1.0 - progress) * 2.0);
  float crossfade = smoothstep(0.4, 0.6, progress);
  return mix(
    getFromColor(zoom(uv, zoomFrom)),
    getToColor(zoom(uv, zoomTo)),
    crossfade
  );
}
"""

    /**
     * Whip Pan — ours, CapCut's whip. The outgoing clip is flung left and the
     * incoming one arrives from the right, both smeared along the motion; the
     * smear peaks at the cut and is gone at either end.
     */
    private const val WHIP_PAN = """
const float PI = 3.141592653589793;
const int STEPS = 16;

vec4 whipAt(float x, float y) {
    return x < 1.0 ? getFromColor(vec2(x, y)) : getToColor(vec2(x - 1.0, y));
}

vec4 transition(vec2 uv) {
    float t = progress;
    // Cubic in-out: slow away, very fast through the cut, slow to land.
    float shift = t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0;
    float smear = 0.3 * sin(PI * t);
    vec4 color = vec4(0.0);
    for (int i = 0; i <= STEPS; i++) {
        float f = float(i) / float(STEPS) - 0.5;
        color += whipAt(uv.x + shift + f * smear, uv.y);
    }
    return color / float(STEPS + 1);
}
"""

    /**
     * Shake — ours. Both clips shudder through a quick cross-fade, the shake
     * strongest at the cut. The jitter is a function of `progress`, never
     * random, so the preview and the export shake identically; the picture is
     * pushed in by the shake's own reach so a shaken edge never shows.
     */
    private const val SHAKE = """
const float PI = 3.141592653589793;
const float AMPLITUDE = 0.035;

vec4 transition(vec2 uv) {
    float amp = AMPLITUDE * sin(PI * progress);
    vec2 jitter = vec2(sin(progress * 97.0), cos(progress * 71.0)) * amp;
    vec2 p = (uv - 0.5) * (1.0 - 2.0 * amp) + 0.5 + jitter;
    float t = smoothstep(0.4, 0.6, progress);
    return mix(getFromColor(p), getToColor(p), t);
}
"""

    /**
     * Zoom Bounce — ours, zoom with overshoot. The outgoing clip rushes in; the
     * incoming one lands from close up, overshoots past its frame — the
     * background showing round it for a moment — and settles.
     */
    private const val ZOOM_BOUNCE = """
vec2 zoomAt(vec2 uv, float s) {
    return (uv - 0.5) / s + 0.5;
}

vec4 inFrame(vec4 c, vec2 p) {
    bool inside = all(greaterThanEqual(p, vec2(0.0))) && all(lessThanEqual(p, vec2(1.0)));
    return inside ? c : vec4(0.0);
}

float easeOutBack(float x) {
    float c1 = 1.70158;
    float c3 = c1 + 1.0;
    return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0);
}

vec4 transition(vec2 uv) {
    float t = progress;
    float mixT = smoothstep(0.4, 0.6, t);
    float sFrom = 1.0 + 1.5 * t * t;
    float k = clamp((t - 0.4) / 0.6, 0.0, 1.0);
    float sTo = mix(2.0, 1.0, easeOutBack(k));
    vec2 pTo = zoomAt(uv, sTo);
    return mix(getFromColor(zoomAt(uv, sFrom)), inFrame(getToColor(pTo), pTo), mixT);
}
"""

    // ------------------------------------------------- Light, Glitch, 3D

    /**
     * Asks for `highp` where the GPU has it. The glitch ports draw a fresh
     * random value per block, row and frame; in `mediump` (fp16 on most
     * phones) a hash keeps only a few distinct values and the tearing turns
     * regular. A GPU without high-precision fragments takes [SLIM_HASH] in
     * `mediump`, which stays finite there — coarser, never broken.
     */
    private const val PRECISION_HIGH = """
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#endif
"""

    /**
     * The hash every port here uses in place of `fract(sin(x) * 43758.5)`.
     * Inputs are small — cells, rows, frames — and each is folded into 0..1
     * before they are combined, so nothing grows past a few hundred: no
     * overflow in `mediump`, where `p * 443.9` (Drop_Zone_Flicker's) can.
     */
    private const val SLIM_HASH = """
float slimHash(vec2 p) {
    vec2 q = fract(p * vec2(0.1031, 0.1137) + vec2(0.3719, 0.7123));
    q += dot(q, q.yx + 3.33);
    return fract((q.x + q.y) * q.x);
}
"""

    /**
     * Overexposure — Overexposure. License: MIT. Author: Ben Zhang. Changes:
     * the strength is a constant; the original's `* a` is gone, because a
     * layer is premultiplied already.
     */
    private const val OVEREXPOSURE = """
const float STRENGTH = 0.6;
const float PI = 3.141592653589793;

vec4 transition(vec2 uv) {
    vec4 from = getFromColor(uv);
    vec4 to = getToColor(uv);
    float fromM = 1.0 - progress + sin(PI * progress) * STRENGTH;
    float toM = progress + sin(PI * progress) * STRENGTH;
    return vec4(from.rgb * fromM + to.rgb * toM, mix(from.a, to.a, progress));
}
"""

    /** Blotch `i`'s centre, as the fragment reads it. */
    private val FILM_BURN_SPOTS: List<String> =
        (0 until 12).map { i -> "vBurnSpots${i / 2}.${if (i % 2 == 0) "xy" else "zw"}" } + "vBurnSpotLast"

    /**
     * Film Burn — FilmBurn. License: MIT. Author: Anastasia Dunbar. Changes:
     * the seed is a constant; loops count in `int`; [SLIM_HASH] for each of
     * its sin-fract hashes; the blur's per-tap scatter hashes the tap and the
     * pixel. Its leaks are light, so they are added over the whole frame,
     * background included — a burn on the film, not on the picture.
     *
     * **Its thirteen blotches are placed in the vertex shader**
     * ([FILM_BURN_VERTEX]). Each blotch's centre is two noise lookups of
     * sixteen hashes and fourteen `pow`s — the same answer for every pixel of
     * a frame. Worked out per pixel, that was over two hundred hashes a pixel,
     * which the export, waiting on each frame, absorbed and the preview could
     * not: it dropped frames until the burn barely showed. Worked out at the
     * quad's four corners and handed down as varyings, it costs nothing, and
     * the arithmetic is the one the fragment ran — the picture is the same.
     * The light preview takes 12 blur taps for 50 and keeps every blotch, so
     * switching to it mid-transition changes only the blur's grain.
     */
    private val FILM_BURN: String = """
$PRECISION_HIGH
$SLIM_HASH
const float SEED = 2.31;
const float PI = 3.14159265358979323;
const int STEPS = 50;

$FILM_BURN_VARYINGS
$FILM_BURN_NOISE
float rand(float co) {
    return slimHash(vec2(co * 7.0, SEED));
}

float apow(float a, float b) { return pow(abs(a), b) * sign(b); }
vec3 pow3(vec3 a, vec3 b) { return vec3(apow(a.r, b.r), apow(a.g, b.g), apow(a.b, b.b)); }

vec4 blendedColor(vec2 p) {
    return mix(getFromColor(p), getToColor(p), sigmoid(progress, 10.0));
}

// One blotch: a drifting wave and a glow round its centre.
float leak(vec2 p, vec2 centre, float i) {
    return sin(((p.x * rand(i) * 6.0) + (progress * 8.0)) + rand(i + 1.43))
        * sin(((p.y * rand(i + 4.4) * 6.0) + (progress * 6.0)) + rand(i + 2.4))
        + 1.0 - clamp(length(p - centre) * mix(20.0, 70.0, rand(i)), 0.0, 1.0);
}

vec4 transition(vec2 p) {
    vec3 f = vec3(0.0);
${FILM_BURN_SPOTS.withIndex().joinToString("\n") { (i, at) -> "    f += leak(p, $at, ${i}.0);" }}
    f += 4.0;
    f /= 11.0;
    f = pow3(f * vec3(1.0, 0.7, 0.6), vec3(1.0, 2.0 - sin(progress * PI), 1.3));
    f *= sin(progress * PI);

    p -= 0.5;
    p *= 1.0 + (smoothRandom(vec2(progress * 5.0), 6.3) * sin(progress * PI) * 0.05);
    p += 0.5;

    vec4 blurred = vec4(0.0);
    float blurAmount = sin(progress * PI) * 0.03;
    for (int k = 0; k < STEPS; k++) {
        float i = float(k);
        float angle = degrees((i / float(STEPS)) * 360.0);
        vec2 q = vec2(cos(angle), sin(angle)) * (slimHash(vec2(i, (p.x + p.y) * 517.0)) + blurAmount);
        blurred += blendedColor(p + q * blurAmount);
    }
    blurred /= float(STEPS);
    return blurred + vec4(f, 0.0);
}
"""

    /**
     * Where the thirteen blotch centres travel between the stages: six `vec4`s
     * of two each and one `vec2`. With `vTexCoord` that is seven varying rows,
     * inside the eight every GLES2 device guarantees.
     */
    private const val FILM_BURN_VARYINGS = """
varying vec4 vBurnSpots0;
varying vec4 vBurnSpots1;
varying vec4 vBurnSpots2;
varying vec4 vBurnSpots3;
varying vec4 vBurnSpots4;
varying vec4 vBurnSpots5;
varying vec2 vBurnSpotLast;
"""

    /** FilmBurn's smooth noise, shared by both stages so they cannot drift. */
    private const val FILM_BURN_NOISE = """
float sigmoid(float x, float a) {
    float b = pow(x * 2.0, a) / 2.0;
    if (x > 0.5) {
        b = 1.0 - pow(2.0 - (x * 2.0), a) / 2.0;
    }
    return b;
}

float smoothMix(float a, float b, float c) { return mix(a, b, sigmoid(c, 2.0)); }

float random(vec2 co, float shft) {
    co += 10.0;
    return smoothMix(
        slimHash(co + vec2(floor(shft) * 1.618, SEED * 3.0)),
        slimHash(co + vec2(floor(shft + 1.0) * 1.618, SEED * 3.0)),
        fract(shft)
    );
}

float smoothRandom(vec2 co, float shft) {
    return smoothMix(
        smoothMix(random(floor(co), shft), random(floor(co + vec2(1.0, 0.0)), shft), fract(co.x)),
        smoothMix(random(floor(co + vec2(0.0, 1.0)), shft), random(floor(co + vec2(1.0, 1.0)), shft), fract(co.x)),
        fract(co.y)
    );
}
"""

    /**
     * Film Burn's vertex shader: the shared one, plus the blotch centres —
     * blotch `i` at `(smoothRandom(progress × 1.3, i + 1), smoothRandom(progress
     * × 0.5, i + 6.25))`, as FilmBurn places them. `uProgress` is declared
     * `mediump` because the fragment header declares it so, and a uniform two
     * stages share must agree on precision or the program does not link.
     */
    private val FILM_BURN_VERTEX: String = """
attribute vec4 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
uniform mediump float uProgress;
$FILM_BURN_VARYINGS
$SLIM_HASH
const float SEED = 2.31;
$FILM_BURN_NOISE
vec2 spot(float i) {
    return vec2(
        smoothRandom(vec2(uProgress * 1.3), i + 1.0),
        smoothRandom(vec2(uProgress * 0.5), i + 6.25)
    );
}

void main() {
    gl_Position = aPosition;
    vTexCoord = aTexCoord;
${(0 until 6).joinToString("\n") { k -> "    vBurnSpots$k = vec4(spot(${2 * k}.0), spot(${2 * k + 1}.0));" }}
    vBurnSpotLast = spot(12.0);
}
"""

    /**
     * Flash — ours. The cut hides behind a short white flash: nothing at the
     * ends, full white at the middle, bright for about a fifth of the window.
     * White over the whole frame, bars included, as Fade White is.
     */
    private const val FLASH = """
vec4 transition(vec2 uv) {
    vec4 picture = progress < 0.5 ? getFromColor(uv) : getToColor(uv);
    float flash = pow(1.0 - abs(2.0 * progress - 1.0), 3.0);
    return mix(picture, vec4(1.0), flash);
}
"""

    /**
     * Glitch — GlitchMemories. License: MIT. Author: Gunnar Roth, from
     * natewave's work. Changes: alpha is the green sample's rather than 1.
     * The original's block is `floor(p / 16)`, which for uv in 0..1 is always
     * 0: the whole frame shifts as one, stepping with progress — kept as it is.
     */
    private const val GLITCH_MEMORIES = """
vec4 transition(vec2 p) {
    vec2 uvNoise = floor(vec2(progress) * vec2(1200.0, 3500.0)) / vec2(64.0);
    vec2 dist = progress > 0.0 ? (fract(uvNoise) - 0.5) * 0.3 * (1.0 - progress) : vec2(0.0);
    vec2 red = p + dist * 0.2;
    vec2 green = p + dist * 0.3;
    vec2 blue = p + dist * 0.5;
    vec4 g = mix(getFromColor(green), getToColor(green), progress);
    return vec4(
        mix(getFromColor(red), getToColor(red), progress).r,
        g.g,
        mix(getFromColor(blue), getToColor(blue), progress).b,
        g.a
    );
}
"""

    /**
     * Lost Signal — old_tv_lost_signal. License: MIT. Author: mernking
     * (gitlab.com/Godswork). Changes: [SLIM_HASH], the tracking lines
     * re-drawn on each of thirty steps rather than hashed from a continuous
     * progress; the scanline darkening is on the picture, scaled by its
     * coverage, so the bars stay clean.
     */
    private const val LOST_SIGNAL = """
$PRECISION_HIGH
$SLIM_HASH
const float PI = 3.14159265;

vec4 transition(vec2 uv) {
    float p = progress;
    float strength = sin(p * PI);
    vec4 color = mix(getFromColor(uv), getToColor(uv), p);

    float lineY = floor(uv.y * 120.0);
    float line = step(0.92, slimHash(vec2(lineY, floor(p * 30.0))));
    float drift = sin(uv.y * 30.0 + p * 10.0) * 0.02 * strength;
    vec2 shifted = uv + vec2(drift, 0.0);
    vec4 lineColor = mix(getFromColor(shifted), getToColor(shifted), p);
    color = mix(color, lineColor, line * strength);

    color.rgb -= sin(uv.y * 900.0) * 0.03 * strength * color.a;
    return color;
}
"""

    /**
     * Static — StaticFade. License: MIT. Author: Ben Lucas. Changes: the noise
     * size and brightness are constants; [SLIM_HASH], the snow re-drawn on
     * each of sixty steps. The snow is opaque, so it covers the bars too —
     * a screen of static, not static on the picture.
     */
    private const val TV_STATIC = """
$PRECISION_HIGH
$SLIM_HASH
const float NOISE_PIXELS = 200.0;
const float LUMINOSITY = 0.8;

float staticIntensity(float t) {
    float transitionProgress = abs(2.0 * (t - 0.5));
    float threshold = 1.2 * (1.0 - transitionProgress) - 0.1;
    return min(1.0, threshold);
}

vec4 transition(vec2 uv) {
    vec4 picture = mix(getFromColor(uv), getToColor(uv), step(0.5, progress));
    vec2 cell = floor(uv * NOISE_PIXELS);
    float frame = floor(progress * 60.0);
    vec3 snow = LUMINOSITY * vec3(
        slimHash(cell + vec2(frame * 2.0, frame * 3.0)),
        slimHash(cell + vec2(frame * 3.0 + 401.0, frame * 5.0)),
        slimHash(cell + vec2(frame * 5.0, frame * 7.0 + 809.0))
    );
    float covered = step(slimHash(cell + vec2(57.0, 113.0)), staticIntensity(progress));
    return mix(picture, vec4(snow, 1.0), covered);
}
"""

    /**
     * Datamosh — StripDatamoshGlitch. License: MIT. Author: bread. Changes:
     * the parameters are constants; [SLIM_HASH] for both hashes; alpha is the
     * green sample's rather than 1. Damage to the picture — its noise — is
     * scaled by its coverage; its light — the sparks and the strobe — is laid
     * over the whole frame.
     */
    private const val DATAMOSH = """
$PRECISION_HIGH
$SLIM_HASH
const float STRENGTH = 1.0;
const float HORIZONTAL_BARS = 42.0;
const float VERTICAL_SLITS = 18.0;
const float TEAR = 0.18;
const float CHROMA = 0.032;
const float RESIDUE = 0.62;
const float NOISE_AMOUNT = 0.16;
const float SCAN_AMOUNT = 0.13;
const float FLASH_AMOUNT = 0.20;
const float PI = 3.141592653589793;

float hash1(float n) { return slimHash(vec2(n, 17.0)); }
float sat(float v) { return clamp(v, 0.0, 1.0); }
float burst() { return pow(max(0.0, sin(progress * PI)), 0.42) * STRENGTH; }
vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.0), vec2(1.0)); }

float stripeY(vec2 uv, float density, float seed, float minWidth, float maxWidth) {
    float y = uv.y * density + seed * 0.137;
    float id = floor(y);
    float f = fract(y);
    float c = slimHash(vec2(id, seed));
    float w = mix(minWidth, maxWidth, slimHash(vec2(id + 9.17, seed + 2.31)));
    return 1.0 - smoothstep(w, w + 0.018, abs(f - c));
}

float stripeX(vec2 uv, float density, float seed, float minWidth, float maxWidth) {
    float x = uv.x * density + seed * 0.091;
    float id = floor(x);
    float f = fract(x);
    float c = slimHash(vec2(id, seed + 41.0));
    float w = mix(minWidth, maxWidth, slimHash(vec2(id + 4.7, seed + 8.9)));
    return 1.0 - smoothstep(w, w + 0.012, abs(f - c));
}

float brokenGate(vec2 uv, float row, float rnd, float frame) {
    float segs = mix(1.0, 9.0, slimHash(vec2(row, frame + 44.0)));
    float seg = floor(uv.x * segs);
    return step(0.16, slimHash(vec2(seg, row + frame * 3.0 + rnd)));
}

float horizontalMask(vec2 uv, float frame) {
    float r1 = floor((uv.y + hash1(frame) * 0.031) * HORIZONTAL_BARS * 0.38);
    float r2 = floor((uv.y + hash1(frame + 2.0) * 0.013) * HORIZONTAL_BARS);
    float r3 = floor((uv.y + hash1(frame + 7.0) * 0.006) * HORIZONTAL_BARS * 3.4);

    float thick = stripeY(uv, HORIZONTAL_BARS * 0.38, frame + 1.0, 0.035, 0.22);
    float mid = stripeY(uv, HORIZONTAL_BARS, frame + 4.0, 0.014, 0.11);
    float hair = stripeY(uv, HORIZONTAL_BARS * 3.4, frame + 9.0, 0.004, 0.035);

    thick *= step(0.42, slimHash(vec2(r1, frame + 10.0)));
    mid *= step(0.48, slimHash(vec2(r2, frame + 20.0)));
    hair *= step(0.62, slimHash(vec2(r3, frame + 30.0)));

    thick *= brokenGate(uv, r1, slimHash(vec2(r1, frame)), frame);
    mid *= brokenGate(uv, r2, slimHash(vec2(r2, frame)), frame + 3.0);

    return sat(max(thick, max(mid, hair)));
}

float verticalMask(vec2 uv, float frame) {
    float col = floor((uv.x + hash1(frame + 12.0) * 0.017) * VERTICAL_SLITS);
    float slit = stripeX(uv, VERTICAL_SLITS, frame + 13.0, 0.01, 0.075);
    slit *= step(0.66, slimHash(vec2(col, frame + 19.0)));
    return sat(slit);
}

vec4 chromaFrom(vec2 uv, vec2 s) {
    uv = safeUv(uv);
    vec4 c = getFromColor(uv);
    return vec4(getFromColor(safeUv(uv + s)).r, c.g, getFromColor(safeUv(uv - s)).b, c.a);
}

vec4 chromaTo(vec2 uv, vec2 s) {
    uv = safeUv(uv);
    vec4 c = getToColor(uv);
    return vec4(getToColor(safeUv(uv - s)).r, c.g, getToColor(safeUv(uv + s)).b, c.a);
}

vec2 distortUv(vec2 uv, float dir, float b, float h, float v, float frame) {
    float row = floor(uv.y * HORIZONTAL_BARS);
    float col = floor(uv.x * VERTICAL_SLITS);
    float rowRnd = slimHash(vec2(row, frame));
    float colRnd = slimHash(vec2(col, frame + 27.0));
    float xTear = (rowRnd - 0.5) * 2.0 * TEAR * b * h;
    xTear += sin(uv.y * 120.0 + progress * 95.0) * 0.006 * b;
    float yDrag = (colRnd - 0.5) * 0.13 * b * v;
    float micro = (slimHash(vec2(row, col + frame)) - 0.5) * 0.018 * b * max(h, v);
    return uv + vec2(xTear * dir + micro, yDrag);
}

vec4 transition(vec2 uv) {
    if (progress <= 0.0) return getFromColor(uv);
    if (progress >= 1.0) return getToColor(uv);

    float b = burst();
    float frame = floor(progress * 30.0);

    float h = horizontalMask(uv, frame);
    float v = verticalMask(uv, frame);
    float glitch = sat(max(h, v * 0.75));

    float row = floor(uv.y * HORIZONTAL_BARS);
    float rowRnd = slimHash(vec2(row, frame + 5.0));

    float bandDelay = (rowRnd - 0.5) * 0.30 * h;
    float reveal = smoothstep(0.18, 0.84, progress + bandDelay);

    vec2 split = vec2(CHROMA * b * (1.0 + 1.7 * glitch), CHROMA * 0.22 * b * v);
    vec2 fromUv = distortUv(uv, 1.0, b, h, v, frame);
    vec2 toUv = distortUv(uv, -1.0, b, h, v, frame);
    vec4 color = mix(chromaFrom(fromUv, split), chromaTo(toUv, split), reveal);

    vec2 smearUv = uv;
    smearUv.x += (rowRnd - 0.5) * 0.46 * b * h;
    smearUv.y += (slimHash(vec2(row, frame + 31.0)) - 0.5) * 0.045 * b * h;
    float sliceReveal = smoothstep(0.28, 0.78, progress + (rowRnd - 0.5) * 0.22);
    vec4 sliceColor = mix(
        chromaFrom(smearUv, split * 1.65),
        chromaTo(smearUv - vec2((rowRnd - 0.5) * 0.18 * b, 0.0), split * 1.65),
        sliceReveal
    );
    color = mix(color, sliceColor, h * b * RESIDUE);

    float hairLine = stripeY(uv, 190.0, frame + 55.0, 0.002, 0.012);
    hairLine *= step(0.70, slimHash(vec2(floor(uv.y * 190.0), frame + 56.0)));
    color.rgb += vec3(0.72, 0.90, 1.0) * hairLine * b * 0.28;

    float scan = 0.5 + 0.5 * sin(uv.y * 980.0 + progress * 130.0);
    color.rgb *= 1.0 - SCAN_AMOUNT * b * scan;

    vec2 nCell = floor(uv * vec2(360.0 * ratio, 210.0));
    float n = slimHash(nCell + vec2(frame * 7.0, frame * 13.0));
    color.rgb += (n - 0.5) * NOISE_AMOUNT * b * (0.55 + glitch) * color.a;

    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    color.rgb = mix(color.rgb, vec3(luma), 0.18 * b * glitch);

    float strobe = step(0.78, hash1(frame + 3.14)) * pow(b, 1.65);
    color.rgb += vec3(strobe * FLASH_AMOUNT);

    return vec4(clamp(color.rgb, vec3(0.0), vec3(1.0)), color.a);
}
"""

    /**
     * Displace — GlitchDisplace. License: MIT. Author: Matt DesLauriers.
     * Changes: the voronoi it computed and never used is gone, and its hash
     * with it; the reversed `smoothstep(1.0, 0.5, t)` — undefined in GLSL —
     * is written as `1.0 - smoothstep(0.5, 1.0, t)`, what drivers that take it
     * return; the grey flash keeps the darker sample's alpha rather than 2.
     */
    private const val GLITCH_DISPLACE = """
vec2 displace(vec4 tex, vec2 texCoord, float dotDepth, float textureDepth, float strength) {
    vec4 dis = tex * dotDepth + 1.0 - tex * textureDepth;
    dis.x = dis.x - 1.0 + textureDepth * dotDepth;
    dis.y = dis.y - 1.0 + textureDepth * dotDepth;
    return texCoord + vec2(dis.x, dis.y) * strength;
}

float ease1(float t) {
    if (t == 0.0 || t == 1.0) return t;
    return t < 0.5 ? 0.5 * pow(2.0, 20.0 * t - 10.0) : -0.5 * pow(2.0, 10.0 - t * 20.0) + 1.0;
}

float ease2(float t) {
    return t == 1.0 ? t : 1.0 - pow(2.0, -10.0 * t);
}

vec4 transition(vec2 p) {
    vec4 color1 = getFromColor(p);
    vec4 color2 = getToColor(p);
    vec2 disp = displace(color1, p, 0.33, 0.7, 1.0 - ease1(progress));
    vec2 disp2 = displace(color2, p, 0.33, 0.5, ease2(progress));
    vec4 dColor1 = getToColor(disp);
    vec4 dColor2 = getFromColor(disp2);
    float val = ease1(progress);
    vec4 darker = min(dColor2, dColor1);
    vec3 gray = vec3(dot(darker.rgb, vec3(0.299, 0.587, 0.114)));
    dColor2 = vec4(gray * 2.0, darker.a);
    color1 = mix(color1, dColor2, smoothstep(0.0, 0.5, progress));
    color2 = mix(color2, dColor1, 1.0 - smoothstep(0.5, 1.0, progress));
    return mix(color1, color2, val);
}
"""

    /**
     * Flicker — Drop_Zone_Flicker. License: MIT. Author: bread. Changes: the
     * parameters are constants; [SLIM_HASH] for its hash, whose `p * 443.9`
     * overflows `mediump`; alpha is the green sample's rather than 1; its
     * scanlines and exposure pulses are on the picture, scaled by coverage.
     * It flashes back to the outgoing clip on purpose — the reference does.
     */
    private const val FLICKER = """
$PRECISION_HIGH
$SLIM_HASH
const float FRAME_RATE = 24.0;
const float RGB_OFFSET = 0.014;
const float BLOCK_AMOUNT = 0.72;
const float GHOST_AMOUNT = 0.62;
const float RED_CYAN = 0.58;
const float SCANLINE = 0.075;

float sat(float x) { return clamp(x, 0.0, 1.0); }
vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

float frameReveal(float f) {
    if (f < 0.5) return 0.00;
    if (f < 1.5) return 0.28;
    if (f < 2.5) return 0.43;
    if (f < 3.5) return 0.46;
    if (f < 4.5) return 0.38;
    if (f < 5.5) return 0.48;
    if (f < 6.5) return 0.26;
    if (f < 7.5) return 0.10;
    if (f < 8.5) return 0.00;
    if (f < 9.5) return 0.00;
    if (f < 10.5) return 0.30;
    if (f < 11.5) return 0.58;
    if (f < 12.5) return 1.00;
    if (f < 13.5) return 0.70;
    if (f < 14.5) return 0.42;
    if (f < 15.5) return 0.55;
    if (f < 16.5) return 0.72;
    if (f < 17.5) return 0.88;
    if (f < 18.5) return 0.34;
    if (f < 19.5) return 0.48;
    if (f < 20.5) return 0.56;
    if (f < 21.5) return 0.76;
    if (f < 22.5) return 0.93;
    return 1.00;
}

float frameGlitch(float f) {
    if (f < 0.5) return 0.00;
    if (f < 6.5) return 0.92;
    if (f < 10.5) return 0.38;
    if (f < 11.5) return 0.78;
    if (f < 12.5) return 0.12;
    if (f < 17.5) return 0.74;
    if (f < 22.5) return 0.88;
    if (f < 23.5) return 0.28;
    return 0.00;
}

vec4 chromaFrom(vec2 uv, float amt) {
    vec2 o = vec2(amt, 0.0);
    vec4 c = getFromColor(safeUv(uv));
    return vec4(getFromColor(safeUv(uv + o)).r, c.g, getFromColor(safeUv(uv - o)).b, c.a);
}

vec4 chromaTo(vec2 uv, float amt) {
    vec2 o = vec2(amt, 0.0);
    vec4 c = getToColor(safeUv(uv));
    return vec4(getToColor(safeUv(uv - o)).r, c.g, getToColor(safeUv(uv + o)).b, c.a);
}

float blockMask(vec2 uv, float f) {
    vec2 big = floor(uv * vec2(4.0, 2.0));
    vec2 small = floor(uv * vec2(8.0, 4.0));
    float wide = step(0.48, slimHash(vec2(big.x, f * 1.37)));
    float chunks = step(0.56, slimHash(small + vec2(f * 2.11, f * 0.73)));
    float verticalCut = smoothstep(-0.035, 0.035, uv.x - mix(0.18, 0.78, slimHash(vec2(f, 4.7))));
    return sat(mix(wide, chunks, 0.38) * 0.72 + verticalCut * 0.28);
}

vec4 transition(vec2 uv) {
    if (progress <= 0.0) return getFromColor(uv);
    if (progress >= 1.0) return getToColor(uv);

    float f = floor(progress * FRAME_RATE);
    float reveal = frameReveal(f);
    float glitch = frameGlitch(f);

    float rnd = slimHash(vec2(f, 9.13));
    vec2 jitter = vec2((rnd - 0.5) * 0.042, (slimHash(vec2(f, 2.71)) - 0.5) * 0.010) * glitch;
    vec2 fromUv = safeUv(uv + jitter);
    vec2 toUv = safeUv(uv - jitter * 0.55);

    float block = blockMask(uv, f);
    float localReveal = sat(
        reveal
        + (block - 0.5) * BLOCK_AMOUNT * glitch
        + (slimHash(vec2(f, floor(uv.y * 9.0))) - 0.5) * 0.18 * glitch
    );
    localReveal = smoothstep(0.22, 0.78, localReveal);

    vec4 oldClip = chromaFrom(fromUv, RGB_OFFSET * glitch);
    vec4 newClip = chromaTo(toUv, RGB_OFFSET * glitch);
    vec4 color = mix(oldClip, newClip, localReveal);

    float leftWash = (1.0 - smoothstep(0.10, 0.78, uv.x)) * glitch;
    float cyanWash = smoothstep(0.08, 0.62, uv.x) * (1.0 - smoothstep(0.86, 1.0, uv.x)) * glitch;
    vec3 redGhost = oldClip.rgb * vec3(1.34, 0.42, 0.38);
    vec3 cyanGhost = newClip.rgb * vec3(0.48, 1.12, 1.24);
    color.rgb = mix(color.rgb, redGhost, leftWash * RED_CYAN * 0.42);
    color.rgb = mix(color.rgb, cyanGhost, cyanWash * RED_CYAN * 0.30);

    float oldReturn = glitch * (1.0 - smoothstep(0.94, 1.0, reveal));
    oldReturn *= 0.18 + 0.52 * (1.0 - abs(localReveal - 0.5) * 2.0);
    color.rgb = mix(color.rgb, oldClip.rgb, oldReturn * GHOST_AMOUNT);

    float lines = sin((uv.y + f * 0.017) * 1080.0);
    color.rgb += lines * SCANLINE * glitch * color.a;

    float exposurePulse = (slimHash(vec2(f, 12.4)) - 0.35) * 0.10 * glitch;
    color.rgb += exposurePulse * color.a;

    return vec4(clamp(color.rgb, vec3(0.0), vec3(1.0)), color.a);
}
"""

    /**
     * Revolve — Revolve_Left. License: MIT. Author: bread. Changes: the
     * parameters are constants; the motion-blur loop counts in `int`;
     * `direction` is [direction], -1 for Left as the original ships and +1 for
     * Right, the swirl's centre mirrored with it. 17 samples, each reading
     * both layers; the light preview takes 5.
     */
    private fun revolve(direction: String) = """
const float DIRECTION = $direction;
const vec2 CENTER = vec2(0.5 + 0.04 * DIRECTION, 0.52);
const float MAX_ROTATION = 1.95;
const float PEAK_ZOOM = 2.22;
const float SWIRL = 2.85;
const float BARREL = 0.38;
const float MOTION_BLUR = 1.0;
const float SWITCH_START = 0.30;
const float SWITCH_END = 0.50;
const float SHADOW = 0.16;
const int STEPS = 8;

float sat(float x) { return clamp(x, 0.0, 1.0); }

float ease(float x) {
    x = sat(x);
    return x * x * (3.0 - 2.0 * x);
}

float revolveEnvelope(float t) {
    float rise = ease((t - 0.10) / 0.33);
    float fall = 1.0 - ease((t - 0.43) / 0.29);
    return rise * fall;
}

vec2 rotate2(vec2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec2 warpUv(vec2 uv, float t) {
    float e = revolveEnvelope(t);
    vec2 p = uv - CENTER;
    p.x *= ratio;
    float r = length(p);
    float edgeSpin = MAX_ROTATION * e;
    float coreSpin = SWIRL * e * pow(1.0 - sat(r / 0.96), 1.55);
    p = rotate2(p, -DIRECTION * (edgeSpin + coreSpin));
    p /= 1.0 + (PEAK_ZOOM - 1.0) * pow(e, 0.85);
    float rr = length(p);
    p *= 1.0 + BARREL * e * rr * rr * 2.8;
    p.x /= ratio;
    return clamp(p + CENTER, vec2(0.001), vec2(0.999));
}

vec4 sampleRevolve(vec2 uv, float t) {
    vec2 p = warpUv(uv, t);
    return mix(getFromColor(p), getToColor(p), smoothstep(SWITCH_START, SWITCH_END, t));
}

vec4 transition(vec2 uv) {
    if (progress <= 0.0) return getFromColor(uv);
    if (progress >= 1.0) return getToColor(uv);

    float e = revolveEnvelope(progress);
    float span = 0.060 * MOTION_BLUR * e;
    vec4 color = vec4(0.0);
    float total = 0.0;
    for (int i = -STEPS; i <= STEPS; i++) {
        float x = float(i) / float(STEPS);
        float w = 1.0 - abs(x);
        w = w * w + 0.01;
        color += sampleRevolve(uv, sat(progress + x * span)) * w;
        total += w;
    }
    color /= total;

    vec2 q = uv - vec2(0.5);
    q.x *= ratio;
    color.rgb *= 1.0 - SHADOW * e * smoothstep(0.35, 0.95, length(q));
    return color;
}
"""

    /**
     * Cube — cube. License: MIT. Author: gre. Changes: the parameters are
     * constants; its floor reflects over the background rather than over
     * black. Right is the same cube turned the other way: the geometry is
     * mirrored ([mirror] 1.0) but never the pictures on its faces.
     */
    private fun cube(mirror: String) = """
const float MIRROR = $mirror;
const float PERSP = 0.7;
const float UNZOOM = 0.3;
const float REFLECTION = 0.4;
const float FLOATING = 3.0;

vec2 mirrored(vec2 p) { return vec2(mix(p.x, 1.0 - p.x, MIRROR), p.y); }
vec4 fromAt(vec2 p) { return getFromColor(mirrored(p)); }
vec4 toAt(vec2 p) { return getToColor(mirrored(p)); }

vec2 project(vec2 p) {
    return p * vec2(1.0, -1.2) + vec2(0.0, -FLOATING / 100.0);
}

bool inBounds(vec2 p) {
    return all(lessThan(vec2(0.0), p)) && all(lessThan(p, vec2(1.0)));
}

vec4 floorReflection(vec2 pfr, vec2 pto) {
    vec4 c = vec4(0.0);
    pfr = project(pfr);
    if (inBounds(pfr)) {
        c += fromAt(pfr) * REFLECTION * (1.0 - pfr.y);
    }
    pto = project(pto);
    if (inBounds(pto)) {
        c += toAt(pto) * REFLECTION * (1.0 - pto.y);
    }
    return c;
}

vec2 xskew(vec2 p, float persp, float center) {
    float x = mix(p.x, 1.0 - p.x, center);
    return (
        (
            vec2(x, (p.y - 0.5 * (1.0 - persp) * x) / (1.0 + (persp - 1.0) * x))
            - vec2(0.5 - distance(center, 0.5), 0.0)
        )
        * vec2(0.5 / distance(center, 0.5) * (center < 0.5 ? 1.0 : -1.0), 1.0)
        + vec2(center < 0.5 ? 0.0 : 1.0, 0.0)
    );
}

vec4 transition(vec2 uv) {
    vec2 op = mirrored(uv);
    float uz = UNZOOM * 2.0 * (0.5 - distance(0.5, progress));
    vec2 p = -uz * 0.5 + (1.0 + uz) * op;
    vec2 fromP = xskew((p - vec2(progress, 0.0)) / vec2(1.0 - progress, 1.0), 1.0 - mix(progress, 0.0, PERSP), 0.0);
    vec2 toP = xskew(p / vec2(progress, 1.0), mix(pow(progress, 2.0), 1.0, PERSP), 1.0);
    if (inBounds(fromP)) {
        return fromAt(fromP);
    } else if (inBounds(toP)) {
        return toAt(toP);
    }
    return floorReflection(fromP, toP);
}
"""

    /** Every layered transition, by the name the catalog persists. */
    val bodies: Map<String, Body> = mapOf(
        "zoomBlur" to withSteps(ZOOM_BLUR, full = 40, light = 12),
        "slideScaleLeft" to Body(slideScale("vec2(1.0, 0.0)")),
        "slideScaleRight" to Body(slideScale("vec2(-1.0, 0.0)")),
        // y runs up here: a picture travelling up samples from below.
        "slideScaleUp" to Body(slideScale("vec2(0.0, -1.0)")),
        "slideScaleDown" to Body(slideScale("vec2(0.0, 1.0)")),
        "splitIn" to Body(SPLIT_IN),
        "splitOut" to Body(SPLIT_OUT),
        "bounce" to Body(BOUNCE),
        "swirl" to Body(SWIRL),
        "spinAway" to Body(SPIN_AWAY),
        "zoomInOut" to Body(ZOOM_IN_OUT),
        "whipPan" to withSteps(WHIP_PAN, full = 16, light = 6),
        "shake" to Body(SHAKE),
        "zoomBounce" to Body(ZOOM_BOUNCE),
        "dreamyZoom" to Body(DREAMY_ZOOM),
        "motionBlur" to withSteps(MOTION_BLUR, full = 20, light = 8),
        "defocus" to Body(DEFOCUS),
        "overexposure" to Body(OVEREXPOSURE),
        "filmBurn" to Body(
            full = FILM_BURN,
            light = FILM_BURN.replace("const int STEPS = 50;", "const int STEPS = 12;"),
            vertex = FILM_BURN_VERTEX,
        ),
        "flash" to Body(FLASH),
        "glitchMemories" to Body(GLITCH_MEMORIES),
        "lostSignal" to Body(LOST_SIGNAL),
        "tvStatic" to Body(TV_STATIC),
        "datamosh" to Body(DATAMOSH),
        "glitchDisplace" to Body(GLITCH_DISPLACE),
        "flicker" to Body(FLICKER),
        "revolveLeft" to withSteps(revolve("-1.0"), full = 8, light = 2),
        "revolveRight" to withSteps(revolve("1.0"), full = 8, light = 2),
        "cubeLeft" to Body(cube("0.0")),
        "cubeRight" to Body(cube("1.0")),
    )
}
