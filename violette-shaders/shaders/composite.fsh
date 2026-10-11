#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 1: deferred lighting, sun shadows, sky, water shading, fog. Output is linear HDR.

/*
const int colortex0Format = RGBA16F;
*/
const int shadowMapResolution = 2048; // [1024 2048 3072 4096]
const float shadowDistance = 128.0;   // [64.0 96.0 128.0 192.0 256.0]
const float sunPathRotation = -25.0;  // [-40.0 -25.0 -10.0 0.0 10.0 25.0 40.0]

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;
uniform float rainStrength;
uniform float far;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;

varying vec2 texcoord;

vec3 viewPos(vec2 uv, float d) {
    vec4 v = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}

vec3 skyGradient(vec3 dir, vec3 upV, vec3 sunDirV, float day, float dusk, float rain) {
    float up = dot(dir, upV);
    vec3 zenith  = mix(vec3(0.02, 0.03, 0.12), mix(vec3(0.16, 0.30, 0.78), vec3(0.26, 0.18, 0.52), dusk), day);
    vec3 horizon = mix(vec3(0.05, 0.05, 0.16), mix(vec3(0.60, 0.76, 1.00), vec3(1.00, 0.44, 0.62), dusk), day);
    vec3 g = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.5));
    float sd = max(dot(dir, sunDirV), 0.0);
    g += vec3(1.0, 0.45, 0.50) * pow(sd, 5.0) * dusk * 0.55;
    g = mix(g, horizon * 0.7, 1.0 - smoothstep(-0.35, 0.0, up));
    g = mix(g, vec3(luma(g)) * 0.85, rain * 0.7);
    return g;
}

void main() {
    vec2 uv = texcoord;
    float d0 = texture2D(depthtex0, uv).r;   // includes water and glass
    float d1 = texture2D(depthtex1, uv).r;   // opaque only
    vec3 posW = viewPos(uv, d0);
    vec3 posO = viewPos(uv, d1);

    vec3 colG = texture2D(colortex0, uv).rgb;
    vec3 col = toLinear(colG);

    // ---------- time of day ----------
    vec3 upV = normalize(upPosition);
    vec3 sunDirV = normalize(sunPosition);
    float sunH = dot(sunDirV, upV);
    float day = smoothstep(-0.10, 0.12, sunH);
    float dusk = exp(-sunH * sunH * 14.0);
    float rain = rainStrength;
    float skyVisEye = float(eyeBrightnessSmooth.y) / 240.0;

    vec3 sunCol  = mix(vec3(1.00, 0.93, 0.82) * 1.5, vec3(1.00, 0.40, 0.52) * 1.2, dusk);
    vec3 moonCol = vec3(0.30, 0.38, 0.85) * 0.45;
    vec3 lightCol = mix(moonCol, sunCol, day) * (1.0 - 0.75 * rain);

    vec3 ambDay = mix(vec3(0.38, 0.50, 0.85), vec3(0.62, 0.42, 0.72), dusk);
    vec3 amb = mix(vec3(0.06, 0.07, 0.20), ambDay, day) * 0.9;
    amb = mix(amb, vec3(luma(amb)), rain * 0.6);

    vec3 L = normalize(shadowLightPosition);

    if (d1 >= 1.0) {
        // ---------- sky ----------
        vec3 dir = normalize(posO);
        vec3 grad = skyGradient(dir, upV, sunDirV, day, dusk, rain);
        float m = smoothstep(0.65, 0.95, luma(colG));      // keeps sun, moon and stars
        col = mix(col, grad, SKY_TINT * (1.0 - m));
        col *= 1.0 + m * 3.0;
    } else if (texture2D(colortex2, uv).a > 0.5) {
        // ---------- deferred lighting for terrain ----------
        vec3 N = normalize(texture2D(colortex1, uv).xyz * 2.0 - 1.0);
        vec3 data = texture2D(colortex2, uv).rgb;
        vec2 lm = data.xy;
        bool foliage = data.z > 0.25;

        float ndlRaw = dot(N, L);
        float ndl = max(ndlRaw, 0.0);
        if (foliage) ndl = mix(ndl, 0.7, 0.5);

        // sun shadows
        float shadow = 1.0;
        if (ndl > 0.001) {
            vec3 feet = (gbufferModelViewInverse * vec4(posO, 1.0)).xyz;
            vec3 Nw = mat3(gbufferModelViewInverse) * N;
            float slope = 1.0 - clamp(ndlRaw, 0.0, 1.0);
            vec3 sp = feet + Nw * (0.08 + 0.10 * slope);
            vec4 sc = shadowProjection * (shadowModelView * vec4(sp, 1.0));
            sc.xyz /= sc.w;
            float edge = max(abs(sc.x), abs(sc.y));
            if (edge < 1.0) {
                vec3 s3 = vec3(shadowDistort(sc.xy), sc.z) * 0.5 + 0.5;
                float bias = 0.0004 + 0.0006 * slope;
                float rad = SHADOW_SOFTNESS * 2.0 / float(shadowMapResolution);
                float rot = ign(gl_FragCoord.xy) * 6.28318;
                float sum = 0.0;
                for (int i = 0; i < SHADOW_SAMPLES; i++) {
                    float fi = float(i);
                    float a = fi * 2.39996 + rot;
                    float rr = sqrt((fi + 0.5) / float(SHADOW_SAMPLES));
                    vec2 o = vec2(cos(a), sin(a)) * rr * rad;
                    float sd = texture2D(shadowtex1, s3.xy + o).r;
                    sum += step(s3.z - bias, sd);
                }
                shadow = sum / float(SHADOW_SAMPLES);
                shadow = mix(shadow, 1.0, smoothstep(0.85, 1.0, edge));
            }
        }

        float skyVis = smoothstep(0.35, 0.95, lm.y);
        vec3 sunTerm = lightCol * ndl * shadow * skyVis * SUN_STRENGTH;

        float hemi = 0.5 + 0.5 * dot(N, upV);
        vec3 ambient = amb * (0.25 + 0.75 * lm.y * lm.y) * mix(0.65, 1.15, hemi) * AMBIENT_STRENGTH;

        vec3 blockC = vec3(1.0, 0.60, 0.30) * pow(lm.x, 2.6) * 1.8 * BLOCKLIGHT_STRENGTH;
        vec3 minAmb = vec3(0.025, 0.022, 0.040);

        col *= ambient + sunTerm + blockC + minAmb;
    }

    // ---------- water ----------
    vec4 wd = texture2D(colortex3, uv);
    if (wd.a > 0.5 && d0 < d1 && isEyeInWater == 0) {
        vec3 Nw = normalize(wd.xyz * 2.0 - 1.0);
        vec3 V = normalize(posW);

        float dist = max(length(posO) - length(posW), 0.0);
        vec3 absorb = exp(-dist * vec3(0.50, 0.18, 0.07));
        vec3 scatter = vec3(0.03, 0.16, 0.30) * (0.25 + 0.75 * day) * (0.4 + 0.6 * skyVisEye);
        col = col * absorb + scatter * (1.0 - absorb);

        vec3 R = reflect(V, Nw);
        vec3 refl = skyGradient(R, upV, sunDirV, day, dusk, rain) * (0.4 + 0.6 * skyVisEye);
        float fres = 0.04 + 0.96 * pow(1.0 - max(dot(Nw, -V), 0.0), 5.0);
        col = mix(col, refl, clamp(fres * WATER_REFLECTIONS, 0.0, 1.0));

        float spec = pow(max(dot(R, L), 0.0), 250.0);
        col += lightCol * spec * 4.0 * WATER_REFLECTIONS * (1.0 - rain) * skyVisEye;
    }

    // ---------- fog ----------
    float dist = (d0 < 1.0) ? length(posW) : far * 2.0;
    if (isEyeInWater == 1) {
        float f = 1.0 - exp(-dist * 0.07);
        vec3 uwCol = vec3(0.04, 0.20, 0.36) * (0.35 + 0.65 * day);
        col = mix(col * vec3(0.6, 0.85, 1.0), uwCol, f);
    } else if (isEyeInWater == 2) {
        float f = 1.0 - exp(-dist * 0.5);
        col = mix(col, vec3(0.9, 0.35, 0.05), f);
    } else if (d0 < 1.0) {
        float f = 1.0 - exp(-pow(dist / (far * 0.95), 2.5) * 3.0 * FOG_DENSITY);
        f += rain * (1.0 - exp(-dist * 0.012));
        f = clamp(f, 0.0, 1.0);
        vec3 fogCol = skyGradient(normalize(posW), upV, sunDirV, day, dusk, rain);
        fogCol = mix(fogCol, vec3(luma(fogCol)), 0.1);
        col = mix(col, fogCol * (0.45 + 0.55 * mix(0.4, 1.0, skyVisEye)), f);
    }

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col, 1.0);
}
