#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 2: screen-space reflections on water, puddles, wet ground and shiny PBR surfaces.

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 cameraPosition;
uniform float rainStrength;
uniform float wetness;
uniform float frameTimeCounter;
uniform int worldTime;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;

varying vec2 texcoord;

#include "/lib/sky.glsl"

vec3 viewPos(vec2 uv, float d) {
    vec4 v = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}

// Marches the reflected ray through the depth buffer. xyz = color found, w = confidence.
vec4 traceSSR(vec3 pos, vec3 R, float jitter) {
    float stepLen = 0.3;
    vec3 p = pos + R * stepLen * jitter;
    vec3 prev = p;
    for (int i = 0; i < SSR_STEPS; i++) {
        prev = p;
        p += R * stepLen;
        stepLen *= 1.2;

        vec4 c = gbufferProjection * vec4(p, 1.0);
        if (c.w <= 0.0) break;
        vec2 uv = c.xy / c.w * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;

        float sz = viewPos(uv, texture2D(depthtex1, uv).r).z;
        float diff = sz - p.z;                       // positive: scene is in front of the ray
        if (diff > 0.0 && diff < stepLen * 1.5 + 0.2) {
            vec3 lo = prev;
            vec3 hi = p;
            for (int k = 0; k < 4; k++) {
                vec3 mid = 0.5 * (lo + hi);
                vec4 cm = gbufferProjection * vec4(mid, 1.0);
                vec2 um = cm.xy / cm.w * 0.5 + 0.5;
                float sm = viewPos(um, texture2D(depthtex1, um).r).z;
                if (sm - mid.z > 0.0) hi = mid; else lo = mid;
            }
            vec4 ch = gbufferProjection * vec4(hi, 1.0);
            vec2 uh = ch.xy / ch.w * 0.5 + 0.5;
            float edge = min(min(uh.x, 1.0 - uh.x), min(uh.y, 1.0 - uh.y));
            float conf = smoothstep(0.0, 0.08, edge) * (1.0 - smoothstep(0.2, 0.7, R.z));
            return vec4(texture2D(colortex0, uh).rgb, conf);
        }
    }
    return vec4(0.0);
}

void main() {
    vec3 col = texture2D(colortex0, texcoord).rgb;

#ifdef SSR
    initSky();
    float d0 = texture2D(depthtex0, texcoord).r;
    float d1 = texture2D(depthtex1, texcoord).r;
    float rain = rainStrength;

    vec4 wd = texture2D(colortex3, texcoord);
    bool water = (wd.a > 0.5 && d0 < d1 && isEyeInWater == 0);
    bool surface = (!water && d1 < 1.0 && texture2D(colortex2, texcoord).a > 0.5);

    vec3 pos = vec3(0.0);
    vec3 N = vec3(0.0, 1.0, 0.0);
    float refl = 0.0;
    float skyVis = 1.0;
    vec3 tint = vec3(1.0);

    if (water) {
        pos = viewPos(texcoord, d0);
        N = normalize(wd.xyz * 2.0 - 1.0);
        float ndv = max(dot(N, -normalize(pos)), 0.0);
        refl = clamp((0.02 + 0.98 * pow(1.0 - ndv, 5.0)) * WATER_REFLECTIONS, 0.0, 1.0);
        skyVis = 0.4 + 0.6 * float(eyeBrightnessSmooth.y) / 240.0;
    } else if (surface) {
        pos = viewPos(texcoord, d1);
        N = normalize(texture2D(colortex1, texcoord).xyz * 2.0 - 1.0);
        vec2 lm = texture2D(colortex2, texcoord).xy;
        vec4 sp = texture2D(colortex6, texcoord);

        vec3 feet = (gbufferModelViewInverse * vec4(pos, 1.0)).xyz;
        vec3 wp = feet + cameraPosition;
        vec3 Nw = mat3(gbufferModelViewInverse) * N;

        float expo = smoothstep(0.8, 1.0, lm.y);
        float wetMask = wetness * WET_WORLD * expo;
        float puddle = puddleNoise(wp.xz) * wetMask * smoothstep(0.8, 1.0, Nw.y);

        bool metal = sp.g > 0.9;
        float smoothness = clamp(max(sp.r, wetMask * 0.35 + puddle), 0.0, 1.0);
        float f0 = metal ? 0.9 : max(sp.g * 1.1, 0.04);
        N = normalize(mix(N, g_up, puddle));

        float ndv = max(dot(N, -normalize(pos)), 0.0);
        float fres = f0 + (1.0 - f0) * pow(1.0 - ndv, 5.0);
        refl = fres * smoothness * smoothness;
        if (metal) tint = clamp(col / max(luma(col), 0.05), 0.0, 1.5);
        skyVis = smoothstep(0.3, 0.95, lm.y);
    }

    if (refl > 0.01) {
        vec3 V = normalize(pos);
        vec3 R = reflect(V, N);
        vec4 hit = traceSSR(pos, R, ign(gl_FragCoord.xy));
        vec3 skyC = skyFull(R, rain) * skyVis;
        vec3 rc = mix(skyC, hit.rgb, hit.a);
        col = mix(col, rc * tint, clamp(refl, 0.0, 1.0));
    }
#endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col, 1.0);
}
