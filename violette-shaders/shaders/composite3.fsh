#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 3: ray-marched fog. Sun shafts come from sampling the shadow map along each view ray.


uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;

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
uniform float far;
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

void main() {
    vec3 col = texture2D(colortex0, texcoord).rgb;

#ifdef VOLUMETRIC_FOG
    if (isEyeInWater == 0) {
        initSky();
        float rain = rainStrength;
        float d0 = texture2D(depthtex0, texcoord).r;
        vec3 posW = viewPos(texcoord, d0);
        vec3 viewDir = normalize(posW);
        vec3 dirW = normalize(mat3(gbufferModelViewInverse) * viewDir);

        float maxD = (d0 < 1.0) ? length(posW) : far;
        maxD = min(maxD, far);
        float stepLen = maxD / float(VF_STEPS);
        float jitter = ign(gl_FragCoord.xy);

        vec3 L = normalize(shadowLightPosition);
        vec3 Lw = mat3(gbufferModelViewInverse) * L;
        float cosT = dot(dirW, Lw);
        float g = 0.55;
        float phase = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * cosT, 1.5);

        vec3 lightCol = mix(moonLightColor(), sunLightColor(), g_day) * (1.0 - 0.6 * rain);
        float skyVisEye = 0.3 + 0.7 * float(eyeBrightnessSmooth.y) / 240.0;
        vec3 ambFog = skyAtmosphere(viewDir, rain) * 0.5 * skyVisEye;

        float base = 0.0012 * FOG_DENSITY;
        float mist = 1.0 + 2.0 * g_dusk;            // thicker at dawn and dusk

        float T = 1.0;
        vec3 scat = vec3(0.0);

        for (int i = 0; i < VF_STEPS; i++) {
            float t = (float(i) + jitter) * stepLen;
            vec3 p = dirW * t;
            vec3 wp = p + cameraPosition;

            // thicker near sea level, patchy, heavier in rain
            float dens = base * (1.0 + 3.0 * exp(-max(wp.y - 62.0, 0.0) * 0.05));
            dens *= mist * (1.0 + rain * 3.0) * (0.75 + 0.5 * vnoise(wp.xz * 0.05 + vec2(frameTimeCounter * 0.02)));
            dens *= skyVisEye;

            // is this point in sunlight?
            float vis = 1.0;
            vec4 sc = shadowProjection * (shadowModelView * vec4(p, 1.0));
            sc.xyz /= sc.w;
            if (max(abs(sc.x), abs(sc.y)) < 1.0) {
                vec3 s3 = vec3(shadowDistort(sc.xy), sc.z) * 0.5 + 0.5;
                vis = step(s3.z - 0.0008, texture2D(shadowtex1, s3.xy).r);
            }

            float seg = dens * stepLen;
            scat += T * seg * (vis * lightCol * phase * VF_STRENGTH * 0.35 + ambFog);
            T *= exp(-seg);
        }
        col = col * T + scat;
    }
#endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col, 1.0);
}
