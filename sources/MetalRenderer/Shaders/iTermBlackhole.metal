#include <metal_stdlib>
#include <simd/simd.h>
#include "iTermShaderTypes.h"

using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

constexpr sampler textureSampler (mag_filter::linear, min_filter::linear);

// blackhole.glsl — a geodesic-traced black hole for Ghostty
//
// After Eric Bruneton's "Real-time High-Quality Rendering of Non-Rotating
// Black Holes" (https://ebruneton.github.io/black_hole_shader/). Bruneton
// precomputes Schwarzschild geodesics into lookup textures; a Ghostty custom
// shader is a single fragment pass with no custom textures, so here each
// pixel's null geodesic is integrated numerically instead — the Binet-form
// photon acceleration  a = -(3/2) h² x / r⁵  reproduces the exact
// Schwarzschild bending. Everything the camera sees falls out of that
// integration rather than being painted on:
//
//   * the shadow            — rays with impact parameter under
//                             b_crit = (3√3/2) r_s spiral into the horizon
//                             (your text really is gone, not faded)
//   * gravitational lensing — escaped rays are projected back onto the
//                             terminal "sky" plane: text bends, magnifies,
//                             and mirrors inside the Einstein ring
//   * photon ring           — rays winding near the r = 1.5 r_s photon sphere
//   * accretion disk        — a thin Keplerian disk the ray may cross several
//                             times (the far side arcs over and under the
//                             shadow); blackbody color from a Shakura–Sunyaev
//                             temperature profile, shifted and beamed by the
//                             relativistic factor g = √(1 − 1.5 r_s/r)/(1 − β·k̂)
//   * starfield             — a faint lensed sky so the bending reads even
//                             over empty terminal background
//
// Units: r_s (Schwarzschild radius) = 1. The screen mapping ties the shadow
// radius b_crit to HOLE_RADIUS * sz, so the size modes below keep working.
//
// Ghostty setup (~/.config/ghostty/config):
//   custom-shader = /path/to/blackhole_ghostty/blackhole.glsl
//   custom-shader-animation = true

// ---------------------------------------------------------------- tunables --
// hole & lensing
// HOLE_RADIUS is uniform
// LENS_DEPTH is uniform
constant float STAR_GAIN     = 0.0000; // lensed starfield brightness around the hole (0 = off)
// accretion disk geometry (radii in Schwarzschild radii)
constant float DISK_INNER    = 1.8000; // inner edge; 3 r_s is the ISCO — the innermost stable orbit
constant float DISK_OUTER    = 8.0000; // outer edge
constant float DISK_INCL     = 1.5000; // inclination, rad: 0 = face-on, 1.57 = edge-on
constant float DISK_ROLL     = 0.3500; // rotation of the whole system in the screen plane, rad
// accretion disk matter & light
constant float DISK_GAIN     = 2.2000; // disk emission brightness
constant float DISK_OPACITY  = 0.9000; // how much the near disk hides what is behind it (0..1)
constant float DISK_TEMP     = 5500.0000; // temperature of the hottest annulus, Kelvin (blackbody color)
constant float DOPPLER_MIX   = 0.6000; // 0 = no relativistic color/brightness asymmetry, 1 = full effect
constant float DISK_BEAM     = 2.5000; // beaming exponent: observed intensity scales as g^N
constant float DISK_SPEED    = 5.0000; // streak pattern speed; negative reverses the orbit direction
constant float DISK_WIND     = 7.0000; // spiral winding tightness of the streaks
constant float DISK_CONTRAST = 1.6000; // streak contrast: 0 = smooth haze, higher = sharp filaments
// light & screen
constant float EXPOSURE      = 1.4000; // tonemap exposure for the disk light (terminal text is untouched)
constant float DRIFT_SPEED   = 1.0000; // how fast the hole floats around
// bottom screen fraction kept undistorted (uniforms.workArea)
constant float DILATION_MIN  = 0.2000; // disk pattern time rate at full size (gravitational time dilation theme)
// token mode
// TOKEN_AREA_MIN is uniform
// TOKEN_AREA_MAX is uniform
constant float TOKEN_HOME_X  = 0.9600; // MODE_TOKENS: corner-home x in uv (1.0 = right edge)
constant float TOKEN_HOME_Y  = 0.0400; // MODE_TOKENS: corner-home y in uv (0.0 = screen top — Ghostty y runs top-down)
constant float TOKEN_EASE    = 1.0000; // MODE_TOKENS: growth curve exponent; 1 = proportional, <1 front-loads growth, >1 back-loads it
constant float TOKEN_REACH   = 1.0000; // MODE_TOKENS: fraction of the playable screen the roam box covers at 100% context
constant float TOKEN_CALM    = 0.0400; // MODE_TOKENS: drift speed at 0% context (near-still seed)
constant float TOKEN_RUSH    = 1.1000; // MODE_TOKENS: drift speed at 100% context (noticeably quicker, never frantic)

// geodesic integration steps per pixel (only pixels near the hole pay this).
// The dominant GPU cost: at high token fill the near field covers most of the
// screen, and on a base-M GPU at 5K that's ~15M pixels x N_STEPS per frame.
#define N_STEPS 96

// ---------------------------------------------------------------- size mode --
// What drives the hole's growth — the master intensity I that every visual
// (size, lensing, disk, dilation) feeds off. More modes to come.
#define MODE_POMODORO 0   // wall-clock 55/5 work/break cycle + typing detector
#define MODE_TOKENS   1   // Claude Code context-window fill (live; see README)
#define MODE_DEMO     2   // self-running 42 s showcase loop for recording (see below)
// SIZE_MODE is uniform

// Live state for MODE_TOKENS rides in on the *cursor color*: claude-token.py
// encodes the context fill into an OSC 12 cursor color and the shader decodes
// it from iCurrentCursorColor every frame — no file rewrite, no reload, no
// recompile hitch, and each Ghostty surface gets its own hole. Encoding (keep
// in sync with the script's CURSOR_BASE): high nibbles are the fixed amber
// base #F_B_0_, low nibbles carry a 4-bit checksum and the fill byte — 16
// bits must line up before a color is trusted, so a theme's own cursor color
// can't accidentally drive the hole.
//   no signal in the color -> no Claude session -> hole is hidden entirely
//   fill byte 0            -> fresh session -> tiny seed hole in the corner
//   fill byte 1..250       -> context fill /250 -> grows, speeds up, roams
// TOKEN_LEVEL is a manual fallback used only when the cursor carries no
// signal — handy for hand-testing a size (edit + reload); the committed -1
// keeps it inert. (#define, not const float, so the tuner leaves it alone.)
#define TOKEN_LEVEL -1 // token-level

constant int3 TOKEN_BASE_HI = int3(0xF, 0xB, 0x0); // cursor-channel base, high nibbles

float tokenFromBytes(int3 v) {
    int3 lo = v & 0xF;
    if (any((v >> 4) != TOKEN_BASE_HI) || lo.r != (lo.g ^ lo.b ^ 0x5)) return -1.0;
    int fill = (lo.g << 4) | lo.b;
    return fill > 250 ? -1.0 : float(fill) / 250.0;
}

// Context fill decoded from one cursor color, or -1 when no signal.
// Ghostty hands the color over as plain sRGB bytes / 255 — no linearization,
// no premultiply (src/renderer/generic.zig) — so the raw decode is exact; the
// second attempt un-linearizes first in case a future renderer changes that.
float tokenDecode(float3 cc) {
    float3 c = clamp(cc, 0.0, 1.0);
    float lvl = tokenFromBytes(int3(floor(c * 255.0 + 0.5)));
    if (lvl >= 0.0) return lvl;
    float3 s = mix(c * 12.92, 1.055 * pow(max(c, 1e-6), float3(1.0 / 2.4)) - 0.055,
                 step(0.0031308, c));
    return tokenFromBytes(int3(floor(clamp(s, 0.0, 1.0) * 255.0 + 0.5)));
}

// Level updates arrive as discrete steps (1% statusline ticks), and a step in
// the level steps the whole warp field — size, lensing, roam box — in a
// single frame, which reads as a jerk. The shader is stateless, but Ghostty
// bumps iTimeCursorChange on ANY cursor change *including color* and
// snapshots the prior color into iPreviousCursorColor at that moment
// (src/renderer/generic.zig), so we can glide from the previous encoded
// level to the current one. A plain cursor *move* copies current into
// previous (same level twice), which merely ends a glide early — worst case
// is the old instant step.
//
// The glide duration scales with the jump. Small ticks must stay at the
// cadence floor: the snapshot is the previous *emitted* level, not the
// mid-glide display value, so during a rapid stream of 1% ticks (~300 ms
// apart) a longer glide would restart from too far back and stutter. Big
// isolated jumps (a heavy turn, the post-/compact snap-back) have no next
// tick breathing down their neck and can take their time.
constant float TOKEN_GLIDE_MIN  = 0.3000; // glide floor, seconds — keep at the statusline refresh cadence
constant float TOKEN_GLIDE_MAX  = 1.5000; // glide cap for huge jumps, seconds
constant float TOKEN_GLIDE_RATE = 10.0000; // glide seconds per unit of level jump (10 -> a 10% jump glides for 1 s)

float tokenLevel(float iTime, float iTimeCursorChange, float4 iCurrentCursorColor, float4 iPreviousCursorColor) {
    float cur = tokenDecode(iCurrentCursorColor.rgb);
    if (cur < 0.0) return -1.0;
    float prev = tokenDecode(iPreviousCursorColor.rgb);
    if (prev < 0.0) return cur;
    float T = clamp(abs(cur - prev) * TOKEN_GLIDE_RATE, TOKEN_GLIDE_MIN, TOKEN_GLIDE_MAX);
    return mix(prev, cur, smoothstep(0.0, T, iTime - iTimeCursorChange));
}

// ------------------------------------------------------------- demo mode --
// MODE_DEMO is a self-running 42 s showcase loop for recording: the hole
// grows from the corner seed to 100% exactly as MODE_TOKENS would (the level
// ramps over DEMO_GROW_SEC, then holds full size for the rest of the loop),
// while the disk look tours the tuner presets, crossfading near each slot
// boundary. Everything runs off iTime inside one compiled shader — no file
// rewrites, no reloads, no recompile hitches mid-recording. The tour starts
// and ends on Inferno (the defaults), so the only visible loop seam is the
// hole snapping back to the corner seed. ./demo-mode.sh on|off flips
// SIZE_MODE and reloads Ghostty.
constant float DEMO_SEC      = 42.0000; // full loop length, seconds
constant float DEMO_GROW_SEC = 40.0000; // 0 -> 100% over this; holds full after
constant float DEMO_XFADE    = 0.1800; // preset crossfade, fraction of a slot

// The disk's whole look in one bundle, so the demo can blend presets; in the
// other modes it just carries the tunables above and the compiler folds it
// back to the same constants.
struct DiskLook {
    float temp, incl, roll, inner, outer, opac, dopp, beam,
          gain, contr, wind, speed, expo, star;
};
constant DiskLook LOOK_DEFAULT = DiskLook{
    DISK_TEMP, DISK_INCL, DISK_ROLL, DISK_INNER, DISK_OUTER, DISK_OPACITY,
    DOPPLER_MIX, DISK_BEAM, DISK_GAIN, DISK_CONTRAST, DISK_WIND, DISK_SPEED,
    EXPOSURE, STAR_GAIN};
#define DEMO_N 8
// the tuner's presets (ParamSpec.swift), ~5.25 s each; Zen is skipped (too
// subtle to read in a quick demo) and Inferno bookends the loop
constant DiskLook DEMO_TOUR[DEMO_N] = {
    //        temp    incl  roll   inner outer opac  dopp  beam gain contr wind speed expo  star
    DiskLook{ 5500.0, 1.50,  0.35, 1.8,  8.0, 0.90, 0.60, 2.5, 2.2, 1.6, 7.0, 5.0, 1.40, 0.0},  // inferno
    DiskLook{ 4500.0, 1.52,  0.10, 2.2,  7.0, 0.85, 0.35, 2.0, 1.4, 0.5, 7.0, 5.0, 1.20, 0.0},  // gargantua
    DiskLook{ 3800.0, 0.55, -0.30, 2.2,  6.0, 0.45, 0.90, 3.5, 1.6, 0.4, 3.0, 2.5, 1.10, 0.0},  // m87* donut
    DiskLook{ 6500.0, 0.30,  0.00, 3.0, 10.0, 0.50, 0.80, 2.5, 1.0, 1.1, 7.0, 5.0, 1.00, 0.0},  // face-on ember
    DiskLook{15000.0, 1.30,  0.35, 3.0, 14.0, 0.35, 1.00, 4.0, 1.2, 1.3, 8.0, 5.0, 0.80, 0.0},  // quasar
    DiskLook{18000.0, 1.05,  0.55, 3.0, 16.0, 0.30, 1.00, 5.0, 1.0, 1.5, 9.0, 6.0, 0.75, 0.0},  // blazar
    DiskLook{ 5500.0, 1.50,  0.35, 1.8,  8.0, 0.00, 1.00, 2.5, 0.0, 1.6, 7.0, 5.0, 1.00, 0.6},  // pure lens
    DiskLook{ 5500.0, 1.50,  0.35, 1.8,  8.0, 0.90, 0.60, 2.5, 2.2, 1.6, 7.0, 5.0, 1.40, 0.0}}; // inferno

DiskLook mixLook(DiskLook a, DiskLook b, float f) {
    return DiskLook{
        mix(a.temp,  b.temp,  f), mix(a.incl,  b.incl,  f),
        mix(a.roll,  b.roll,  f), mix(a.inner, b.inner, f),
        mix(a.outer, b.outer, f), mix(a.opac,  b.opac,  f),
        mix(a.dopp,  b.dopp,  f), mix(a.beam,  b.beam,  f),
        mix(a.gain,  b.gain,  f), mix(a.contr, b.contr, f),
        mix(a.wind,  b.wind,  f), mix(a.speed, b.speed, f),
        mix(a.expo,  b.expo,  f), mix(a.star,  b.star,  f)};
}

DiskLook demoLook(float iTime) {
    float u = fmod(iTime, DEMO_SEC) / DEMO_SEC * float(DEMO_N); // 0..N slot clock
    int   i = int(min(u, float(DEMO_N) - 0.001));
    float f = smoothstep(1.0 - DEMO_XFADE, 1.0, fract(u));     // blend at slot end
    return mixLook(DEMO_TOUR[i], DEMO_TOUR[(i + 1) % DEMO_N], f);
}

// ------------------------------------------------------ pomodoro, self-contained --
// Shaders have no memory between frames, so the schedule is anchored to the
// wall clock (iDate.w): the hole grows over each WORK_PERIOD_MIN, collapses
// as break time arrives, and stays gone for BREAK_MIN. With 55+5 the break
// is the last five minutes of every hour. Independently, iTimeCursorChange
// acts as a live typing detector: stop using the terminal and the hole
// shrinks away; it never shows while you are not actually working.
constant float WORK_PERIOD_MIN = 55.0000; // work minutes per cycle (growth phase)
constant float BREAK_MIN       = 5.0000; // break minutes per cycle (hole gone)
constant float IDLE_FADE_SEC   = 90.0000; // typing pause at which fading starts
constant float TIME_SCALE      = 1.0000; // TESTING: 1 = real wall-clock schedule; >1 fast-forwards growth via iTime (100 -> a full cycle in ~36 s). Set back to 1 for normal use.

// critical impact parameter of a Schwarzschild hole, in r_s: rays under this
// fall in; it is the apparent (shadow) radius seen from far away. Physics,
// not taste — a #define so the tuner can't drift it (when it was
// a const float, a stray slider drag in the tuner's "Other" group silently
// shrank every size mode by ~4.6x).
#define B_CRIT 2.5980762

// ------------------------------------------------------------------- noise --
float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// value noise whose y lattice wraps every perY cells — used for the disk's
// angular dimension so the streaks tile seamlessly across the atan branch cut
// (perY must be an integer; y must advance by exactly perY per full turn)
float vnoiseWrapY(float2 p, float perY) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float y0 = fmod(i.y, perY), y1 = fmod(i.y + 1.0, perY);
    return mix(mix(hash21(float2(i.x, y0)),       hash21(float2(i.x + 1.0, y0)), f.x),
               mix(hash21(float2(i.x, y1)),       hash21(float2(i.x + 1.0, y1)), f.x),
               f.y);
}

// mirrored repeat keeps lensed samples on-screen without edge smearing
float2 mirrorUV(float2 u) { return 1.0 - abs(1.0 - fmod(u, 2.0)); }

float2 rot(float2 v, float a) {
    float c = cos(a), s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// unit Lissajous wander: 2+2 incommensurate sines per axis, so the orbit
// never visibly repeats; scale the argument for speed, the result for reach
float2 lissa(float t) {
    return float2(0.75 * sin(t * 0.37) + 0.25 * sin(t * 0.83 + 1.0),
                0.70 * sin(t * 0.54 + 2.1) + 0.30 * sin(t * 1.07));
}

// blackbody color from temperature in Kelvin (Tanner Helland fit, normalized)
float3 blackbody(float T) {
    float t = clamp(T, 1500.0, 40000.0) / 100.0;
    float r = t <= 66.0 ? 1.0
                        : clamp(1.292936 * pow(t - 60.0, -0.1332047), 0.0, 1.0);
    float g = t <= 66.0 ? clamp(0.3900816 * log(t) - 0.6318414, 0.0, 1.0)
                        : clamp(1.1298909 * pow(t - 60.0, -0.0755148), 0.0, 1.0);
    float b = t >= 66.0 ? 1.0
                        : (t <= 19.0 ? 0.0
                                     : clamp(0.5432068 * log(t - 10.0) - 1.1962540, 0.0, 1.0));
    return float3(r, g, b);
}

// sparse procedural starfield indexed by ray direction — because it is
// sampled with the *bent* ray, stars smear into arcs around the hole for free
float3 stars(float3 d, float iTime) {
    float2 sph = float2(atan2(d.x, -d.z), asin(clamp(d.y, -1.0, 1.0)));
    float2 g   = sph * 40.0;
    float2 id  = floor(g);
    float h  = hash21(id);
    if (h < 0.92) return float3(0.0);
    float2 f   = fract(g) - 0.5;
    float2 off = (float2(hash21(id + 17.3), hash21(id + 31.7)) - 0.5) * 0.7;
    float spark = smoothstep(0.10, 0.0, length(f - off));
    float tw    = 0.7 + 0.3 * sin(iTime * (0.5 + 2.0 * hash21(id + 5.1)) + 40.0 * h);
    float3 tint   = mix(float3(1.0, 0.82, 0.60), float3(0.75, 0.85, 1.0), hash21(id + 2.9));
    return tint * spark * tw * ((h - 0.92) / 0.08);
}

// ------------------------------------------------------------------- image --
fragment float4 iTermBlackholeFragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> iChannel0 [[texture(0)]],
    constant iTermBlackholeUniforms &uniforms [[buffer(0)]]
) {
    float2 fragCoord = in.uv * uniforms.resolution;
    float4 fragColor = float4(0.0);

    // Replace uniforms
    float2 iResolution = uniforms.resolution;
    float iTime = uniforms.time;
    float iTimeDelta = uniforms.timeDelta;
    float4 iCurrentCursorColor = uniforms.currentCursorColor;
    float4 iPreviousCursorColor = uniforms.previousCursorColor;
    float iTimeCursorChange = uniforms.timeCursorChange;
    float4 iDate = float4(0,0,0, iTime); // fallback for iDate

    int SIZE_MODE = uniforms.sizeMode;
    float HOLE_RADIUS = uniforms.holeRadius;
    float LENS_DEPTH = uniforms.lensDepth;
    float TOKEN_AREA_MIN = uniforms.tokenAreaMin;
    float TOKEN_AREA_MAX = uniforms.tokenAreaMax;

    float2  res    = iResolution.xy;
    float2  uv     = fragCoord / res;
    float aspect = res.x / res.y;

    // Ghostty's fragCoord y runs top-down; work in height-from-bottom
    float yUp = 1.0 - uv.y;

    // smooth animation runs off iTime (advances every frame); per-mode envelopes
    // (wall clock / token fill) only set how big, how fast and how far it moves
    float t = iTime * DRIFT_SPEED;

    // disk look: the tunables verbatim, or the demo tour's current blend
    DiskLook L = LOOK_DEFAULT;
    if (SIZE_MODE == MODE_DEMO) L = demoLook(iTime);

    // disk extent in r_s, sanitized: the inner edge stays outside the photon
    // sphere (1.5 r_s) where circular orbits stop making sense
    float rin  = max(L.inner, 1.6);
    float rout = max(L.outer, rin + 0.5);

    // ---- per-mode state: master intensity I, size sz, and drift center ----
    // I drives lensing/disk/dilation; sz scales the shadow; center is the
    // hole's screen position. SIZE_MODE picks how the three are computed; both
    // branches compile and the dead one folds away at compile time.
    float I, sz;
    float2  center;
    if (SIZE_MODE == MODE_POMODORO) {
        // wall-clock cycle: grow through the work phase, collapse fast in the
        // last minute, stay gone through the break phase
        float workSec  = WORK_PERIOD_MIN * 60.0;
        float cycleSec = workSec + BREAK_MIN * 60.0;
        // schedule rides the wall clock; for testing, TIME_SCALE adds extra
        // progress via iTime (which always advances per frame), so e.g. 100 runs
        // a full cycle in seconds without depending on how Ghostty steps iDate.w
        float wall     = iDate.w + iTime * (TIME_SCALE - 1.0);
        float phase    = fmod(wall, cycleSec);
        float collapse = min(60.0, workSec * 0.15);  // scales down for short debug cycles
        float grow = clamp(phase / workSec, 0.0, 1.0)
                   * (1.0 - smoothstep(workSec - collapse, workSec, phase));
        // always-present floor: never gone while you work — small and slow at
        // cycle start, back to small when the break window arrives
        I = mix(0.12, 1.0, grow);
        // typing detector: cursor quiet -> you're pausing; the hole shrinks live
        // and is gone by the time the pause becomes a real break
        float idle = max(0.0, iTime - iTimeCursorChange);
        I *= 1.0 - smoothstep(IDLE_FADE_SEC, max(BREAK_MIN * 60.0, IDLE_FADE_SEC + 1.0), idle);
        sz = mix(0.22, 1.0, I);              // starts small, grows toward break time
        // lazy Lissajous drift, vertically confined so the hole and its disk
        // stay above the work area at the bottom; bounds adapt to size (the
        // disk's projected half-extent is rout/B_CRIT shadow radii), drift
        // follows size: a small calm hole hovers, a big one roams wide
        // (amplitude, not frequency — FM would jerk the phase as I evolves)
        float ext = (rout / B_CRIT) * HOLE_RADIUS * sz;
        float yLo = uniforms.workArea + 0.12 + ext;  // clears shield band + wobble
        float yHi = max(yLo, 0.90 - ext);    // clears the screen top
        float spd = mix(0.35, 1.0, I);
        center = float2(
            0.5 + (0.24 * sin(t * 0.21) + 0.05 * sin(t * 0.083)) * spd,
            1.0 - mix(yLo, yHi, 0.5 + (0.42 * sin(t * 0.157 + 2.0) + 0.08 * sin(t * 0.117)) * spd));
        center += I * float2(0.040 * sin(t * 0.83) + 0.020 * sin(t * 1.31),
                           0.030 * sin(t * 1.03 + 1.0));
    } else {
        // ---- token mode: Claude Code context-window fill ----
        // (also MODE_DEMO, which substitutes its own looping level)
        // A negative level means "no session" — show nothing, just the terminal.
        float live = tokenLevel(iTime, iTimeCursorChange, iCurrentCursorColor, iPreviousCursorColor);
        float demoT = fmod(iTime, DEMO_SEC);
        float demoLvl = (demoT < DEMO_GROW_SEC)
                      ? (demoT / DEMO_GROW_SEC)
                      : smoothstep(0.0, 1.0, 1.0 - (demoT - DEMO_GROW_SEC) / (DEMO_SEC - DEMO_GROW_SEC));

        float lvl = (SIZE_MODE == MODE_DEMO)
                  ? demoLvl
                  : (live >= 0.0 ? live : TOKEN_LEVEL);
        if (lvl < 0.0) { fragColor = iChannel0.sample(textureSampler, uv); return fragColor; }
        // TOKEN_EASE shapes the growth curve; g is the master 0..1 fill
        float g = pow(clamp(lvl, 0.0, 1.0), TOKEN_EASE);
        I = mix(0.10, 1.0, g);               // disk dilation / glow follow fill
        // Size is anchored to the *terminal area*: the shadow disk covers
        // TOKEN_AREA_MIN of the screen at 0% context and TOKEN_AREA_MAX at
        // 100%, whatever the window shape (area = pi*rh²/aspect, rh in units
        // of screen height). The radius interpolates linearly between the two
        // endpoints — interpolating the area instead would front-load the
        // felt size badly, since rh goes as sqrt(area).
        float rhMin = sqrt(TOKEN_AREA_MIN * aspect / 3.1415927);
        float rhMax = sqrt(TOKEN_AREA_MAX * aspect / 3.1415927);
        // HOLE_RADIUS doubles as a plain size dial here: at its 0.08 default
        // the AREA_MIN/MAX calibration is exact, and dragging it scales every
        // token-mode size proportionally around that.
        float rhT = mix(rhMin, rhMax, g) * (HOLE_RADIUS / 0.08);
        sz = rhT / max(HOLE_RADIUS, 1e-4);
        // ---- movement: a roam box growing out of the home corner ----
        // The allowed area starts collapsed onto the top-right corner and
        // expands left and down as the context fills, up to TOKEN_REACH of
        // the playable screen (everything above the work area); the hole
        // wanders pseudo-randomly through all of it (Lissajous — never
        // visibly repeats), faster as the fill grows. Margins keep the
        // shadow and bright inner disk on-screen while the hole is small,
        // then give up gracefully once it outgrows the band — a half-screen
        // hole has nowhere clean to be.
        float marg = min(rhT * mix(1.45, 0.90, g), 0.5 * (1.0 - uniforms.workArea - 0.03));
        float xPad = marg / aspect;
        float2  fullLo = float2(min(xPad, 0.5), marg);
        float2  fullHi = float2(max(0.5, 1.0 - xPad),
                            max(marg, 1.0 - (uniforms.workArea + 0.03 + marg)));
        float2  corner = clamp(float2(TOKEN_HOME_X, TOKEN_HOME_Y), fullLo, fullHi);
        float reach  = mix(0.06, max(TOKEN_REACH, 0.06), g); // a sliver of room even at 0%
        float2  lo = float2(mix(corner.x, fullLo.x, reach), fullLo.y);
        float2  hi = float2(fullHi.x, mix(corner.y, fullHi.y, reach));
        // Confinement must never *clip* the position: clipping saturates and
        // parks the hole dead against the wall for seconds — it reads as a
        // freeze. The wander is scaled to the available room instead, and a
        // small fast circular wobble rides on top so the hole stays visibly
        // alive even when one axis runs out of room entirely. Speed comes
        // from blending a calm and a rushed fixed-frequency orbit — NOT from
        // scaling t: iTime persists across reloads, so a g-dependent
        // t-multiplier would jump the phase on every token update (a visible
        // teleport once iTime is large).
        float2  room   = max((hi - lo) * 0.5, float2(0.0));
        float2  wobAmp = min(float2(0.010 + 0.030 * g), max(room * 0.35, float2(0.006)));
        float2  ampEff = max(room - wobAmp, float2(0.0));
        float2  wander = mix(lissa(t * TOKEN_CALM), lissa(t * TOKEN_RUSH), g);
        center = (lo + hi) * 0.5 + wander * ampEff
               + wobAmp * float2(cos(t * 0.8), sin(t * 1.0));
    }
    float vis = smoothstep(0.0, 0.10, I);  // hole vanishes entirely when rested
    if (vis <= 0.0) {
        fragColor = iChannel0.sample(textureSampler, uv);
        return fragColor;
    }
    float rh = HOLE_RADIUS * sz;           // shadow radius in screen units

    // ---- gravitational time dilation (theme feature) ----
    // A heavier hole slows the clock locally: the accretion disk visibly winds
    // down as the hole grows. dil multiplies the disk's pattern rate, falling
    // from 1 toward DILATION_MIN as the hole reaches full mass.
    float dil = mix(1.0, DILATION_MIN, I);

    // shield: warp/disk/stars all fade to nothing over the work area — the
    // displacement (not the color) is faded, so there is no visible seam
    float shield = vis * smoothstep(uniforms.workArea, uniforms.workArea + 0.18, yUp);

    // aspect-corrected frame centered on the hole (y in units of screen height)
    float2  p    = (uv - center) * float2(aspect, 1.0);
    float plen = length(p);

    // screen <-> world mapping: the shadow's true angular size is B_CRIT r_s,
    // and we want it rh screen units wide, so 1 screen unit = W Schwarzschild
    // radii. pr is the pixel in world units, y-up, with the system roll applied.
    float W  = B_CRIT / max(rh, 1e-4);
    float2  pr = rot(float2(p.x, -p.y), L.roll) * W;
    float b  = length(pr);              // the ray's impact parameter, in r_s

    // distance-window: real lensing falls off as 1/b and would shimmer text
    // across the whole screen as the hole drifts; fade it out a few disk
    // diameters away (deliberately unphysical, like the work-area shield)
    float window = exp(-pow(plen / (7.0 * rh), 2.0));

    float bmax = rout + 3.0;            // rays beyond this can't touch the disk
    float Z0   = max(14.0, rout + 5.0); // camera distance (shared with the tracer)

    // ================= far field: analytic weak deflection ==================
    // The geodesic region's rays start at the finite camera z = Z0 and get
    // projected back onto the sky plane, so they bend *less* than the
    // textbook alpha = 2 r_s/b from infinity — using that raw leaves a ~20%
    // displacement jump at the handoff radius, a visible circular seam.
    // This is the same finite-camera mapping, fitted against the integrator
    // (sub-1% at the boundary): disp = (2/b)(1.29u + 0.07)(L - 2.14u + 0.75)
    // in world units, with u = Z0/sqrt(Z0^2 + b^2).
    if (b >= bmax) {
        float u    = Z0 * rsqrt(Z0 * Z0 + b * b);
        float defl = (2.0 / (W * W)) / max(plen, 1e-4)
                   * (1.29 * u + 0.07) * max(LENS_DEPTH - 2.14 * u + 0.75, 0.0)
                   * window * shield;
        float2  dir  = p / max(plen, 1e-5);
        float3  term;
        // mild chromatic aberration: blue bends a touch more than red; faded
        // in away from the handoff circle (the geodesic side has none)
        float ab = 0.035 * smoothstep(1.0, 2.0, b / bmax);
        for (int i = 0; i < 3; i++) {
            float k   = 1.0 + (float(i) - 1.0) * ab;
            float2  sp  = p - dir * defl * k;
            float2  suv = mirrorUV(center + sp / float2(aspect, 1.0));
            term[i]   = iChannel0.sample(textureSampler, suv)[i];
        }
        // same starfield as the geodesic region, lit through the weak-field
        // bend so stars don't pop at the boundary circle
        float3 d = normalize(float3(-(pr / b) * (2.0 / b), -1.0));
        fragColor = float4(term + stars(d, iTime) * L.star * window * shield, 1.0);
        return fragColor;
    }

    // ====================== near field: trace the geodesic ==================
    // Parallel rays from a distant camera at +z. The hole is at the origin,
    // r_s = 1. Integrate  x'' = -(3/2) h² x / r⁵  (exact Schwarzschild photon
    // bending; h = |x×v| is conserved, so it's computed once).
    float3  x  = float3(pr, Z0);
    float3  v  = float3(0.0, 0.0, -1.0);
    float h2 = dot(pr, pr);

    // disk plane: normal tilted DISK_INCL about the screen x-axis
    float ci = cos(L.incl), si = sin(L.incl);
    float3  n  = float3(0.0, si, ci);
    float3  e2 = float3(0.0, ci, -si);      // in-plane axis completing (x̂, e2, n)
    float sdir = L.speed < 0.0 ? -1.0 : 1.0;
    float spd  = abs(L.speed);

    float3  emitc = float3(0.0);            // accumulated disk light (HDR)
    float trans = 1.0;                  // transmittance toward the background
    bool  captured = false;
    float sPrev = dot(x, n);
    float3  xPrev = x;

    for (int i = 0; i < N_STEPS; i++) {
        float r2 = dot(x, x);
        if (r2 < 1.0) { captured = true; break; }        // through the horizon
        if (x.z < -Z0 && v.z < 0.0) break;               // escaped out the back
        if (r2 > 4.0 * Z0 * Z0) break;                   // flung far sideways
        float r  = sqrt(r2);
        // step scales with radius: fine near the photon sphere, coarse far
        // out (the far cap is loose — bending falls off as 1/r^4, and longer
        // approach/exit strides leave more of the N_STEPS budget for the
        // strongly curved region)
        float dt = clamp(0.16 * r, 0.03, 1.5);
        // leapfrog (kick-drift-kick) keeps the near-critical orbits stable
        float3 a = -1.5 * h2 * x / (r2 * r2 * r);
        v += a * (0.5 * dt);
        x += v * dt;
        r2 = dot(x, x);
        r  = sqrt(r2);
        a  = -1.5 * h2 * x / (r2 * r2 * r);
        v += a * (0.5 * dt);

        // ---- thin-disk crossing: the ray pierced the disk plane ----
        float s = dot(x, n);
        if (s * sPrev < 0.0 && trans > 0.02) {
            float tc = sPrev / (sPrev - s);
            float3  xc = mix(xPrev, x, tc);
            float rc = length(xc);
            if (rc > rin && rc < rout) {
                float band = smoothstep(rin, rin * 1.25, rc)
                           * (1.0 - smoothstep(rout * 0.70, rout, rc));

                // disk-plane polar coords for the streak iChannel0.sample
                float phi   = atan2(dot(xc, e2), xc.x);
                float turns = phi / 6.2831853;
                float kep   = pow(rin / rc, 1.5);
                // √(1 − 1.5/r): time runs slower for the inner orbits — the
                // pattern visibly freezes toward the inner edge; dil winds the
                // whole disk down as the hole grows
                float gloc  = sqrt(max(1.0 - 1.5 / rc, 0.02));
                float swirl = rc * L.wind * 0.12 - t * kep * spd * gloc * dil * sdir;
                float streaks = vnoiseWrapY(float2(rc * 2.8, turns * 19.0 + swirl * 3.0), 19.0) * 0.65 +
                                vnoiseWrapY(float2(rc * 1.0, turns * 9.0  + swirl * 1.5 + 7.0), 9.0) * 0.35;
                streaks = 0.35 + L.contr * streaks * streaks;

                // relativistic Doppler + gravitational shift for gas on a
                // circular geodesic: g = √(1 − 1.5/r) / (1 − β·k̂), with the
                // photon direction at the crossing taken from the ray itself
                float3  gasdir = normalize(cross(n, xc)) * sdir;
                float beta   = clamp(rsqrt(max(2.0 * (rc - 1.0), 0.2)), 0.0, 0.99);
                float g      = gloc / max(1.0 + beta * dot(gasdir, normalize(v)), 0.05);
                g = mix(1.0, g, L.dopp);

                // Shakura–Sunyaev temperature profile, peak normalized to 1
                float xpr   = max(1.0 - sqrt(rin / rc), 0.0);
                float tprof = pow(rin / rc, 0.75) * pow(xpr, 0.25) / 0.488;
                float3  cbb   = blackbody(L.temp * tprof * g);      // doppler-shifted color
                float boost = pow(g, L.beam);                     // relativistic beaming

                float density = band * streaks;
                emitc += trans * cbb * (L.gain * 2.2 * density * tprof * tprof * boost);
                trans *= 1.0 - clamp(L.opac * density, 0.0, 1.0);
            }
        }
        sPrev = s;
        xPrev = x;
    }
    // rays still wound up near the photon sphere when the budget ran out are
    // as good as captured
    if (!captured && dot(x, x) < 4.0) captured = true;

    // ---- background: where did the escaped ray come from? ----
    float3 bg = float3(0.0);
    if (!captured) {
        float3 d = normalize(v);
        bg += stars(d, iTime) * L.star * window * shield;
        if (d.z < -0.05) {
            // project the straight exit ray onto the terminal sky plane at
            // z = -LENS_DEPTH and map back to screen space
            float tpl = (-LENS_DEPTH - x.z) / d.z;
            float3  hp  = x + d * tpl;
            float2  q   = rot(hp.xy, -L.roll) / W;
            float2  sp  = float2(q.x, -q.y);
            // the *displacement* is faded by window/shield, never the color —
            // a continuous warp leaves no seam at the work area or far field
            float2  suv = mirrorUV(center + (p + (sp - p) * window * shield) / float2(aspect, 1.0));
            // rays bent past ~90° never reach the sky plane behind the hole;
            // they fade to the starfield instead of sampling garbage
            float toward = smoothstep(0.05, 0.35, -d.z);
            bg += iChannel0.sample(textureSampler, suv).rgb * toward;
        }
    }

    // disk light is HDR; tonemap it on top of the (untouched) terminal sample
    float3 col = bg * trans + (float3(1.0) - exp(-emitc * L.expo));
    fragColor = float4(col, 1.0);
    return fragColor;
}

vertex VertexOut iTermBlackholeVertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    // full screen quad using 3 vertices (a big triangle)
    float2 position = float2((vertexID << 1) & 2, vertexID & 2);
    // iTerm2's custom viewport maps clip space [0, 1] to the screen width and height.
    out.position = float4(position, 0.0, 1.0);
    // uv.y should be 0 at the top and 1 at the bottom to match Ghostty's coordinate system
    out.uv = float2(position.x, 1.0 - position.y);
    return out;
}
