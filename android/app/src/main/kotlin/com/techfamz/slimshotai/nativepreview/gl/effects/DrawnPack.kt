package com.techfamz.slimshotai.nativepreview.gl.effects

import com.techfamz.slimshotai.nativepreview.gl.EffectPass

/**
 * The drawn pack: CapCut-style looks drawn by a shader alone — a thunderstorm,
 * rain, snow, embers, light rays, a lens flare, sparkle and neon edges.
 *
 * Nothing here is footage, nothing is downloaded and nothing is tracked, so the
 * pack costs the app no size and the file matches the canvas by construction:
 * each is one [SingleFramePass] whose picture is a pure function of the pixel,
 * the intensity and the bar's clock.
 *
 * **They keep time in seconds** (`uSeconds`, [TimeControlled]) rather than
 * across the bar's 0..1: rain falls at a real speed, so a ten-second bar must
 * not rain at a third of the speed a three-second one does. Timeline seconds,
 * never wall clock — the export reaches the same value at the same instant.
 *
 * Rules every shader here keeps, each a bug this codebase has already met:
 *
 * * **Intensity 0 is the untouched picture** — every addition is scaled by
 *   `uIntensity`, every grade mixed by it.
 * * **High precision where the GPU has it.** A clock in seconds outgrows
 *   `mediump` within a minute of a bar; on a GPU without `highp` in fragment
 *   shaders a long bar's motion coarsens rather than breaking.
 * * **No sin-fract hash.** `fract(sin(n) * 43758.5)` overflows `mediump` and
 *   bands on some GPUs; [HEADER]'s `packHash` is the sine-free hash (Dave
 *   Hoskins, "Hash without Sine", MIT).
 * * **No reversed `smoothstep` edges** — undefined by the spec, and drivers
 *   differ; `1.0 - smoothstep(a, b, x)` instead.
 * * **Sizes in frame units, not pixels**, so a 400px preview and a 1080p
 *   export draw the same picture.
 *
 * GLSL ES 1.00, compiled at runtime: a mistake is a black frame on a device,
 * never a build error. `DrawnPackShadersTest` writes every source out for
 * `glslangValidator`, which is how they are checked off the device.
 */
internal object DrawnPack {

    /** The pack, in the order the catalog lists it. */
    val IDS = listOf(
        "thunder", "rain", "snow", "embers",
        "light_rays", "lens_flare", "sparkle", "neon_edge",
    )

    /** [id]'s fragment source, or null for an id outside the pack. */
    fun fragmentFor(id: String): String? = when (id) {
        "thunder" -> THUNDER
        "rain" -> RAIN
        "snow" -> SNOW
        "embers" -> EMBERS
        "light_rays" -> LIGHT_RAYS
        "lens_flare" -> LENS_FLARE
        "sparkle" -> SPARKLE
        "neon_edge" -> NEON_EDGE
        else -> null
    }

    /** [id]'s one pass, linked now. GL thread only. */
    fun passFor(id: String): EffectPass? =
        fragmentFor(id)?.let { SingleFramePass(id, FullFrameProgram(it)) }

    private val HEADER = """
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec2 vTexCoord;
uniform sampler2D uTexture;
uniform float uIntensity;
uniform float uSeconds;
uniform float uAspect;

// A hash with no sine in it: inputs folded to 0..1 before they are combined,
// so it cannot overflow mediump the way fract(sin(n) * big) does.
float packHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// The frame, black off its own edge rather than a smear of the edge texel.
vec4 packSample(vec2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    return texture2D(uTexture, uv);
}

// A position in units of the frame's height, so a flake is round on 9:16.
vec2 packScreen(vec2 uv) {
    return vec2(uv.x * max(uAspect, 0.0001), uv.y);
}

// Light added the way a lens adds it: brightens without clipping a bright
// picture flat, and adds nothing where the light is zero.
vec3 packScreenBlend(vec3 base, vec3 light) {
    return 1.0 - (1.0 - base) * (1.0 - clamp(light, 0.0, 1.0));
}
"""

    /**
     * A storm: the picture darkened and cooled, and once every 1.6s a jagged
     * bolt with one branch, a white flash that flickers as real lightning
     * restrikes, and a small jolt of the frame. Each window strikes early in
     * itself, so even a short bar sees one.
     */
    private val THUNDER = HEADER + """
const float STRIKE_PERIOD = 1.6;

float boltNoise(float y, float seed) {
    float i = floor(y);
    float f = fract(y);
    return mix(packHash(vec2(i, seed)), packHash(vec2(i + 1.0, seed)), f) - 0.5;
}

// The bolt's x at height y: straight segments between random points, three
// octaves of them — lightning is jagged, never a smooth curve.
float boltX(float y, float x0, float seed) {
    return x0
        + boltNoise(y * 5.0, seed) * 0.16
        + boltNoise(y * 11.0, seed + 7.0) * 0.07
        + boltNoise(y * 27.0, seed + 19.0) * 0.03;
}

void main() {
    vec2 uv = vTexCoord;
    float window = floor(uSeconds / STRIKE_PERIOD);
    float seed = window * 3.17 + 1.0;
    float strikeAt = window * STRIKE_PERIOD + 0.15 + packHash(vec2(seed, 1.0)) * 0.45;
    float age = uSeconds - strikeAt;
    float lit = step(0.0, age) * (1.0 - step(0.7, age));
    float flicker = 0.55 + 0.45 * step(0.5, fract(age * 13.0));
    float flash = lit * exp(-max(age, 0.0) * 7.0) * flicker;
    float boltOn = lit * (1.0 - step(0.22, age)) * flicker;

    float shakeStep = floor(max(age, 0.0) * 30.0);
    vec2 jolt = vec2(packHash(vec2(seed, shakeStep)), packHash(vec2(shakeStep, seed))) - 0.5;
    vec4 src = packSample(uv + jolt * 0.008 * flash * uIntensity);

    float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 storm = mix(src.rgb, vec3(luma), 0.3) * vec3(0.72, 0.8, 0.95);
    vec3 col = mix(src.rgb, storm, 0.65 * uIntensity);

    float x0 = 0.2 + 0.6 * packHash(vec2(seed, 2.0));
    float yEnd = 0.2 + 0.35 * packHash(vec2(seed, 3.0));
    float dx = abs(uv.x - boltX(uv.y, x0, seed)) * uAspect;
    float along = smoothstep(yEnd, yEnd + 0.06, uv.y);
    float core = exp(-dx * 700.0);
    float halo = exp(-dx * 45.0) * 0.5;

    float yBranch = mix(yEnd, 1.0, 0.55);
    float branchDir = packHash(vec2(seed, 4.0)) < 0.5 ? -1.0 : 1.0;
    float branchX = boltX(yBranch, x0, seed) + (yBranch - uv.y) * branchDir * 0.5
        + boltNoise(uv.y * 19.0, seed + 31.0) * 0.04;
    float dxb = abs(uv.x - branchX) * uAspect;
    float branchSpan = step(uv.y, yBranch) * smoothstep(yBranch - 0.25, yBranch - 0.12, uv.y);
    float branch = (exp(-dxb * 900.0) + exp(-dxb * 60.0) * 0.3) * branchSpan;

    vec3 bolt = vec3(0.85, 0.9, 1.0) * ((core * 1.6 + halo) * along + branch) * boltOn;
    vec3 light = bolt * 1.2 + vec3(0.75, 0.8, 0.95) * flash * 0.55;
    gl_FragColor = vec4(packScreenBlend(col, light * uIntensity), src.a);
}
"""

    /**
     * Rain: three layers of slanted streaks falling at different speeds, the
     * picture a little darker and cooler under them.
     */
    private val RAIN = HEADER + """
float rainLayer(vec2 q, float scale, float speed, float seed, float t) {
    vec2 p = vec2(q.x + q.y * 0.18, q.y + t * speed);
    vec2 grid = p * vec2(scale, scale * 0.22);
    vec2 cell = floor(grid);
    vec2 f = fract(grid);
    float present = step(0.62, packHash(cell + seed));
    float cx = 0.15 + 0.7 * packHash(vec2(cell.x, cell.y + seed * 1.7));
    float across = 1.0 - smoothstep(0.0, 0.08, abs(f.x - cx));
    float start = 0.1 + 0.4 * packHash(cell + seed + 5.3);
    float len = 0.35 + 0.3 * packHash(cell + seed + 9.1);
    float v = (f.y - start) / len;
    // Brightest at the head, the drop's lowest point, fading up its tail.
    float alongDrop = step(0.0, v) * step(v, 1.0) * (1.0 - v);
    return across * alongDrop * present;
}

void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec3 col = mix(src.rgb, src.rgb * vec3(0.8, 0.86, 0.95), 0.6 * uIntensity);
    vec2 q = packScreen(uv);
    float t = uSeconds;
    float rain = rainLayer(q, 70.0, 2.2, 1.0, t) * 0.9
        + rainLayer(q, 45.0, 1.6, 7.0, t) * 0.6
        + rainLayer(q, 28.0, 1.1, 13.0, t) * 0.35;
    gl_FragColor = vec4(packScreenBlend(col, vec3(0.78, 0.82, 0.9) * rain * 0.6 * uIntensity), src.a);
}
"""

    /**
     * Snow: three layers of soft round flakes, near ones large and slow, far
     * ones small, each swaying on its own rhythm.
     */
    private val SNOW = HEADER + """
float snowLayer(vec2 q, float scale, float speed, float seed, float t) {
    vec2 p = vec2(q.x + sin(t * 0.6 + q.y * 2.0 + seed) * 0.03, q.y + t * speed);
    vec2 grid = p * scale;
    vec2 cell = floor(grid);
    vec2 f = fract(grid);
    float rnd = packHash(cell + seed);
    float present = step(0.45, rnd);
    vec2 centre = vec2(0.3 + 0.4 * packHash(cell + seed + 1.7), 0.3 + 0.4 * packHash(cell + seed + 3.1));
    centre.x += sin(t * 1.3 + rnd * 6.2831) * 0.12;
    float radius = 0.08 + 0.1 * packHash(cell + seed + 5.9);
    float flake = 1.0 - smoothstep(radius * 0.35, radius, length(f - centre));
    return flake * present;
}

void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec3 col = mix(src.rgb, src.rgb * vec3(0.95, 0.98, 1.05) + vec3(0.02, 0.03, 0.05), 0.5 * uIntensity);
    vec2 q = packScreen(uv);
    float t = uSeconds;
    float snow = snowLayer(q, 6.0, 0.10, 2.0, t)
        + snowLayer(q, 11.0, 0.07, 11.0, t) * 0.75
        + snowLayer(q, 19.0, 0.045, 23.0, t) * 0.5;
    gl_FragColor = vec4(packScreenBlend(col, vec3(snow) * 0.95 * uIntensity), src.a);
}
"""

    /**
     * Embers: glowing sparks rising and drifting as heat does, flickering,
     * thickest near the bottom and thinning as they cool; a warm grade under.
     */
    private val EMBERS = HEADER + """
vec3 emberLayer(vec2 q, float scale, float speed, float seed, float t) {
    vec2 p = vec2(q.x + sin(t * 0.8 + q.y * 3.0 + seed) * 0.04, q.y - t * speed);
    vec2 grid = p * scale;
    vec2 cell = floor(grid);
    vec2 f = fract(grid);
    float rnd = packHash(cell + seed);
    float present = step(0.7, rnd);
    vec2 centre = vec2(0.25 + 0.5 * packHash(cell + seed + 2.3), 0.25 + 0.5 * packHash(cell + seed + 4.7));
    vec2 d = f - centre;
    float r2 = dot(d, d);
    float flick = 0.55 + 0.45 * sin(t * 9.0 + rnd * 40.0);
    float core = exp(-r2 * 900.0);
    float glow = exp(-r2 * 120.0) * 0.35;
    vec3 colour = mix(vec3(1.0, 0.38, 0.06), vec3(1.0, 0.78, 0.3), packHash(cell + seed + 8.8));
    return colour * (core + glow) * flick * present;
}

void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec3 col = mix(src.rgb, src.rgb * vec3(1.08, 0.94, 0.82), 0.55 * uIntensity);
    vec2 q = packScreen(uv);
    float t = uSeconds;
    float rise = 1.0 - smoothstep(0.15, 1.0, uv.y) * 0.7;
    vec3 embers = (emberLayer(q, 9.0, 0.16, 3.0, t) + emberLayer(q, 16.0, 0.11, 17.0, t) * 0.7) * rise;
    gl_FragColor = vec4(packScreenBlend(col, embers * uIntensity), src.a);
}
"""

    /**
     * Light rays: warm shafts from a light above the frame's top right, two
     * sets of angular bands drifting against each other so they shimmer like
     * light through moving leaves rather than spinning.
     */
    private val LIGHT_RAYS = HEADER + """
void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec2 q = packScreen(uv);
    vec2 d = q - vec2(0.82 * uAspect, 1.12);
    float dist = length(d);
    float angle = atan(d.y, d.x);
    float t = uSeconds;
    float a = 0.5 + 0.5 * sin(angle * 26.0 + t * 0.35);
    float b = 0.5 + 0.5 * sin(angle * 41.0 - t * 0.55 + 1.3);
    float c = 0.5 + 0.5 * sin(angle * 9.0 + t * 0.2 + 2.1);
    float shafts = smoothstep(0.45, 1.0, a * 0.55 + b * 0.3 + c * 0.35);
    float reach = exp(-dist * 1.25);
    float bloom = exp(-dist * 3.2) * 0.5;
    vec3 light = vec3(1.0, 0.92, 0.75) * (shafts * reach * 0.75 + bloom);
    gl_FragColor = vec4(packScreenBlend(src.rgb, light * uIntensity), src.a);
}
"""

    /**
     * Lens flare: a hot light drifting slowly across the top, star spikes and
     * an anamorphic streak through it, and coloured ghosts strung along the
     * line from the light through the frame's centre, as a lens throws them.
     */
    private val LENS_FLARE = HEADER + """
float disc(vec2 q, vec2 centre, float radius, float softness) {
    return 1.0 - smoothstep(radius * (1.0 - softness), radius, length(q - centre));
}

void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec2 q = packScreen(uv);
    float t = uSeconds;
    vec2 light = vec2((0.26 + 0.12 * sin(t * 0.27)) * uAspect, 0.8 + 0.04 * cos(t * 0.21));
    vec2 centre = vec2(0.5 * uAspect, 0.5);
    vec2 toLight = q - light;
    float d = length(toLight);
    float glare = exp(-d * 6.0) * 0.9 + exp(-d * 30.0) * 1.4;
    float angle = atan(toLight.y, toLight.x);
    float spikes = pow(abs(cos(angle * 3.0)), 30.0) * exp(-d * 3.5) * 0.5;
    float streak = exp(-abs(toLight.y) * 90.0) * exp(-abs(toLight.x) * 1.2) * 0.55;
    vec2 axis = centre - light;
    vec3 ghosts = vec3(0.35, 0.9, 0.55) * disc(q, light + axis * 0.55, 0.035, 0.5) * 0.35
        + vec3(0.95, 0.55, 0.9) * disc(q, light + axis * 1.35, 0.075, 0.8) * 0.25
        + vec3(0.5, 0.7, 1.0) * disc(q, light + axis * 1.75, 0.045, 0.4) * 0.3
        + vec3(1.0, 0.7, 0.35) * disc(q, light + axis * 2.2, 0.11, 0.9) * 0.18;
    vec3 flare = vec3(1.0, 0.95, 0.85) * (glare + spikes) + vec3(0.55, 0.7, 1.0) * streak + ghosts;
    gl_FragColor = vec4(packScreenBlend(src.rgb, flare * uIntensity), src.a);
}
"""

    /**
     * Sparkle: large four-pointed glints with shorter diagonal rays and a soft
     * glow, twinkling on their own rhythms, a little stronger on the bright
     * parts of the picture as glitter catches the light.
     *
     * **Sized to be seen** (the user's call — the first version was all but
     * invisible: a glint's core was under a pixel in a tile and its twinkle
     * was dark most of the time). Two layers of cells, 4.5 and 8.5 to the
     * frame's height; each glint stays inside its own cell, its rays faded to
     * nothing at the cell's edge, so no cell boundary ever cuts one off.
     */
    private val SPARKLE = HEADER + """
float sparkleLayer(vec2 q, float scale, float seed, float t) {
    vec2 grid = q * scale;
    vec2 cell = floor(grid);
    vec2 f = fract(grid);
    float rnd = packHash(cell + seed);
    float present = step(0.5, rnd);
    vec2 d = f - vec2(0.38 + 0.24 * packHash(cell + seed + 1.1), 0.38 + 0.24 * packHash(cell + seed + 2.9));
    float rate = 1.2 + 2.0 * packHash(cell + seed + 6.4);
    float twinkle = pow(0.5 + 0.5 * sin(t * rate + rnd * 6.2831), 2.5);
    float r2 = dot(d, d);
    float cross = exp(-abs(d.x) * 22.0) * exp(-abs(d.y) * 6.5)
        + exp(-abs(d.y) * 22.0) * exp(-abs(d.x) * 6.5);
    vec2 r = vec2(d.x + d.y, d.x - d.y) * 0.7071;
    float diag = (exp(-abs(r.x) * 30.0) * exp(-abs(r.y) * 11.0)
        + exp(-abs(r.y) * 30.0) * exp(-abs(r.x) * 11.0)) * 0.5;
    float core = exp(-r2 * 140.0) * 1.3;
    float halo = exp(-r2 * 28.0) * 0.4;
    vec2 inside = smoothstep(vec2(0.0), vec2(0.25), f) * smoothstep(vec2(0.0), vec2(0.25), 1.0 - f);
    return (cross * 0.95 + diag + core + halo) * twinkle * present * inside.x * inside.y;
}

void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec2 q = packScreen(uv);
    float t = uSeconds;
    float luma = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
    float catchLight = 0.6 + 0.4 * smoothstep(0.3, 0.8, luma);
    float stars = sparkleLayer(q, 4.5, 4.0, t) + sparkleLayer(q, 8.5, 29.0, t) * 0.7;
    vec3 glint = vec3(1.0, 0.97, 0.9) * stars * catchLight * 1.4;
    gl_FragColor = vec4(packScreenBlend(src.rgb, glint * uIntensity), src.a);
}
"""

    /**
     * Neon: the picture's edges traced in glowing colour that slowly cycles,
     * over the picture dimmed beneath them. The edge step is in frame units,
     * so the line is as thick in a preview as in an export; samples clamp to
     * the frame so its border does not trace as an edge of its own.
     */
    private val NEON_EDGE = HEADER + """
float lumaAt(vec2 uv) {
    return dot(texture2D(uTexture, clamp(uv, 0.0, 1.0)).rgb, vec3(0.2126, 0.7152, 0.0722));
}

vec3 hueColour(float h) {
    return clamp(abs(fract(h + vec3(0.0, 0.6667, 0.3333)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void main() {
    vec2 uv = vTexCoord;
    vec4 src = packSample(uv);
    vec2 s = vec2(0.0028 / max(uAspect, 0.0001), 0.0028);
    float tl = lumaAt(uv + vec2(-s.x, s.y));
    float tc = lumaAt(uv + vec2(0.0, s.y));
    float tr = lumaAt(uv + vec2(s.x, s.y));
    float ml = lumaAt(uv + vec2(-s.x, 0.0));
    float mr = lumaAt(uv + vec2(s.x, 0.0));
    float bl = lumaAt(uv + vec2(-s.x, -s.y));
    float bc = lumaAt(uv + vec2(0.0, -s.y));
    float br = lumaAt(uv + vec2(s.x, -s.y));
    float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
    float gy = (tl + 2.0 * tc + tr) - (bl + 2.0 * bc + br);
    float edge = smoothstep(0.1, 0.45, length(vec2(gx, gy)));
    vec3 neon = hueColour(uSeconds * 0.12 + uv.y * 0.35 + uv.x * 0.15);
    vec3 styled = src.rgb * 0.22 + neon * edge * 1.4;
    gl_FragColor = vec4(mix(src.rgb, styled, uIntensity), src.a);
}
"""
}
