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

    /** A layered transition's body, and a cheaper one where it has many steps. */
    class Body(val full: String, val light: String? = null)

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
    )
}
