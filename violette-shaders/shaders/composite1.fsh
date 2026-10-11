#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 1: deferred lighting, shadows, materials, sky, water shading. Output is linear HDR.

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
uniform sampler2D colortex4;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;
uniform vec3 cameraPosition;
uniform float rainStrength;
uniform float wetness;
uniform float far;
uniform float near;
uniform float viewWidth;
uniform float viewHeight;
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

float linearDepth(float d) {
    return (2.0 * near * far) / (far + near - (d * 2.0 - 1.0) * (far - near));
}

// depth-aware blur of the occlusion buffer
float readAO(vec2 uv, float d) {
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    float ld = linearDepth(d);
    float sum = 0.0;
    float ws = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 o = uv + vec2(float(x), float(y)) * px * 1.5;
            float w = exp(-abs(linearDepth(texture2D(depthtex1, o).r) - ld) * 4.0);
            sum += texture2D(colortex4, o).r * w;
            ws += w;
        }
    }
    return sum / max(ws, 0.0001);
}

void main() {
    vec2 uv = texcoord;
    initSky();

    float d0 = texture2D(depthtex0, uv).r;   // includes water and glass
    float d1 = texture2D(depthtex1, uv).r;   // opaque only
    vec3 posW = viewPos(uv, d0);
    vec3 posO = viewPos(uv, d1);

    vec3 colG = texture2D(colortex0, uv).rgb;
    vec3 col = toLinear(colG);

    float rain = rainStrength;
    float skyVisEye = float(eyeBrightnessSmooth.y) / 240.0;

    vec3 lightCol = mix(moonLightColor(), sunLightColor(), g_day) * (1.0 - 0.75 * rain);
    vec3 ambDay = mix(vec3(0.38, 0.50, 0.85), vec3(0.62, 0.42, 0.72), g_dusk);
    vec3 amb = mix(vec3(0.06, 0.07, 0.20), ambDay, g_day) * 0.9;
    amb = mix(amb, vec3(luma(amb)), rain * 0.6);

    vec3 L = normalize(shadowLightPosition);

    vec4 wd = texture2D(colortex3, uv);
    bool underWater = (wd.a > 0.5 && d0 < d1);

    if (d1 >= 1.0) {
        // ---------- sky ----------
        col = skyFull(normalize(posO), rain);
    } else if (texture2D(colortex2, uv).a > 0.5) {
        // ---------- deferred lighting for terrain ----------
        vec3 albedo = col;
        vec3 N = normalize(texture2D(colortex1, uv).xyz * 2.0 - 1.0);
        vec3 data = texture2D(colortex2, uv).rgb;
        vec4 sp = texture2D(colortex6, uv);
        vec2 lm = data.xy;
        bool foliage = data.z > 0.25;

        vec3 feetO = (gbufferModelViewInverse * vec4(posO, 1.0)).xyz;
        vec3 wp = feetO + cameraPosition;
        vec3 Nw = mat3(gbufferModelViewInverse) * N;

        // wet ground: darker, with puddles under open sky
        float expo = smoothstep(0.8, 1.0, lm.y);
        float wetMask = wetness * WET_WORLD * expo;
        float puddle = puddleNoise(wp.xz) * wetMask * smoothstep(0.8, 1.0, Nw.y);
        albedo *= 1.0 - 0.35 * wetMask - 0.15 * puddle;

        bool metal = sp.g > 0.9;
        if (metal) albedo *= 0.15;

        float ndlRaw = dot(N, L);
        float ndl = max(ndlRaw, 0.0);
        float ndlSpec = ndl;
        if (foliage) ndl = mix(ndl, 0.7, 0.5);

        // sun shadows, tinted by stained glass
        vec3 shadowRGB = vec3(1.0);
        if (ndl > 0.001) {
            float slope = 1.0 - clamp(ndlRaw, 0.0, 1.0);
            vec3 spos = feetO + Nw * (0.08 + 0.10 * slope);
            vec4 sc = shadowProjection * (shadowModelView * vec4(spos, 1.0));
            sc.xyz /= sc.w;
            float edge = max(abs(sc.x), abs(sc.y));
            if (edge < 1.0) {
                vec3 s3 = vec3(shadowDistort(sc.xy), sc.z) * 0.5 + 0.5;
                float bias = 0.0004 + 0.0006 * slope;
                float rad = SHADOW_SOFTNESS * 2.0 / float(shadowMapResolution);
                float rot = ign(gl_FragCoord.xy) * 6.28318;
                vec3 sum = vec3(0.0);
                for (int i = 0; i < SHADOW_SAMPLES; i++) {
                    float fi = float(i);
                    float a = fi * 2.39996 + rot;
                    float rr = sqrt((fi + 0.5) / float(SHADOW_SAMPLES));
                    vec2 suv = s3.xy + vec2(cos(a), sin(a)) * rr * rad;
                    float z = s3.z - bias;
                    float lit1 = step(z, texture2D(shadowtex1, suv).r);
#ifdef COLORED_SHADOWS
                    float lit0 = step(z, texture2D(shadowtex0, suv).r);
                    vec3 tint = vec3(0.0);
                    if (lit1 - lit0 > 0.5) tint = texture2D(shadowcolor0, suv).rgb;
                    sum += vec3(lit0) + (lit1 - lit0) * tint;
#else
                    sum += vec3(lit1);
#endif
                }
                shadowRGB = sum / float(SHADOW_SAMPLES);
                shadowRGB = mix(shadowRGB, vec3(1.0), smoothstep(0.85, 1.0, edge));
            }
        }

        float skyVis = smoothstep(0.35, 0.95, lm.y);
        vec3 sunTerm = lightCol * ndl * shadowRGB * skyVis * SUN_STRENGTH;

        // light on the sea floor: tinted by the water above and broken up by caustics
        if (underWater) {
            float wdist = max(length(posO) - length(posW), 0.0);
            float cau = causticPattern(wp.xz, frameTimeCounter) * CAUSTICS;
            sunTerm *= exp(-wdist * vec3(0.30, 0.10, 0.04)) * (0.35 + cau * 2.2);
        }

        float ao = 1.0;
#ifdef SSAO
        ao = readAO(uv, d1);
#endif

        float hemi = 0.5 + 0.5 * dot(N, g_up);
        vec3 ambient = amb * (0.25 + 0.75 * lm.y * lm.y) * mix(0.65, 1.15, hemi) * AMBIENT_STRENGTH * ao;
        vec3 blockC = vec3(1.0, 0.60, 0.30) * pow(lm.x, 2.6) * 1.8 * BLOCKLIGHT_STRENGTH * mix(1.0, ao, 0.5);
        vec3 minAmb = vec3(0.025, 0.022, 0.040);

        vec3 shaded = albedo * (ambient + sunTerm + blockC + minAmb);

        // light shining through leaves and grass
        if (foliage) {
            float vdl = max(dot(normalize(posO), L), 0.0);
            float trans = pow(vdl, 2.5);
            shaded += albedo * lightCol * shadowRGB * skyVis * (trans * 1.6 + 0.12) * FOLIAGE_GLOW;
        }

        // sun highlights from LabPBR specular data (zero without a PBR resource pack)
        float smoothness = sp.r;
        if (smoothness > 0.02 && ndlSpec > 0.0) {
            vec3 V = -normalize(posO);
            vec3 H = normalize(L + V);
            float rough = pow(1.0 - smoothness, 2.0);
            float a = max(rough * rough, 0.003);
            float NH = max(dot(N, H), 0.0);
            float dd = NH * NH * (a * a - 1.0) + 1.0;
            float D = min(a * a / (3.14159 * dd * dd), 60.0);
            float f0 = metal ? 0.9 : max(sp.g * 1.1, 0.04);
            float F = f0 + (1.0 - f0) * pow(1.0 - max(dot(H, V), 0.0), 5.0);
            vec3 specCol = metal ? col : vec3(1.0);
            shaded += lightCol * shadowRGB * skyVis * ndlSpec * D * F * 0.25 * specCol;
        }

        // emissive pixels from the PBR specular map
        shaded += col * sp.b * 3.0;

        col = shaded;
    }

    // ---------- water ----------
    if (underWater && isEyeInWater == 0) {
        float dist = (d1 < 1.0) ? max(length(posO) - length(posW), 0.0) : 400.0;
        vec3 absorb = exp(-dist * vec3(0.50, 0.18, 0.07));
        vec3 shallow = vec3(0.05, 0.36, 0.40);
        vec3 deepC = vec3(0.03, 0.12, 0.30);
        vec3 scatter = mix(shallow, deepC, 1.0 - exp(-dist * 0.25)) * (0.25 + 0.75 * g_day) * (0.4 + 0.6 * skyVisEye);
        col = col * absorb + scatter * (1.0 - absorb);

        // foam where the water gets shallow
        vec3 wposW = (gbufferModelViewInverse * vec4(posW, 1.0)).xyz + cameraPosition;
        float t = frameTimeCounter;
        float shore = 1.0 - smoothstep(0.05, 0.9, dist);
        float pat = vnoise(wposW.xz * 4.0 + vec2(t * 0.6, -t * 0.4)) * 0.65 + vnoise(wposW.xz * 9.0 - vec2(t * 0.5)) * 0.35;
        float foam = smoothstep(0.35, 0.7, pat + shore * 0.55 - 0.45) * shore * FOAM;
        vec3 foamLight = amb * 1.2 + lightCol * 0.6 * skyVisEye;
        col = mix(col, vec3(0.9, 0.95, 1.0) * foamLight, clamp(foam, 0.0, 1.0) * 0.8);

#ifndef SSR
        vec3 Nw = normalize(wd.xyz * 2.0 - 1.0);
        vec3 V = normalize(posW);
        vec3 R = reflect(V, Nw);
        float fres = 0.04 + 0.96 * pow(1.0 - max(dot(Nw, -V), 0.0), 5.0);
        col = mix(col, skyFull(R, rain) * (0.4 + 0.6 * skyVisEye), clamp(fres * WATER_REFLECTIONS, 0.0, 1.0));
#endif
    }

    // ---------- underwater and lava fog ----------
    float dist = (d0 < 1.0) ? length(posW) : far * 2.0;
    if (isEyeInWater == 1) {
        float f = 1.0 - exp(-dist * 0.07);
        vec3 uwCol = vec3(0.04, 0.20, 0.36) * (0.35 + 0.65 * g_day);
        col = mix(col * vec3(0.6, 0.85, 1.0), uwCol, f);
    } else if (isEyeInWater == 2) {
        float f = 1.0 - exp(-dist * 0.5);
        col = mix(col, vec3(0.9, 0.35, 0.05), f);
    }
#ifndef VOLUMETRIC_FOG
    else if (d0 < 1.0) {
        float f = 1.0 - exp(-pow(dist / (far * 0.95), 2.5) * 3.0 * FOG_DENSITY);
        f += rain * (1.0 - exp(-dist * 0.012));
        f = clamp(f, 0.0, 1.0);
        vec3 fogCol = skyAtmosphere(normalize(posW), rain);
        col = mix(col, fogCol * (0.45 + 0.55 * mix(0.4, 1.0, skyVisEye)), f);
    }
#endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col, 1.0);
}
