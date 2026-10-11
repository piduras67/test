#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 3: light shafts. Marches toward the sun or moon through screen-space sky.

uniform sampler2D colortex0;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjection;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform float rainStrength;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

void main() {
    vec3 col = texture2D(colortex0, texcoord).rgb;

#ifdef GODRAYS
    vec3 upV = normalize(upPosition);
    float sunH = dot(normalize(sunPosition), upV);
    float day = smoothstep(-0.10, 0.12, sunH);
    float dusk = exp(-sunH * sunH * 14.0);

    vec3 lp = (sunH > -0.05) ? sunPosition : moonPosition;
    vec4 clip = gbufferProjection * vec4(lp, 1.0);

    if (clip.w > 0.0) {
        vec2 sUV = clip.xy / clip.w * 0.5 + 0.5;
        vec2 delta = (sUV - texcoord) * (1.0 / 20.0) * 0.9;
        vec2 p = texcoord + delta * ign(gl_FragCoord.xy);
        float acc = 0.0;
        float w = 1.0;
        for (int i = 0; i < 20; i++) {
            p += delta;
            if (p.x > 0.0 && p.x < 1.0 && p.y > 0.0 && p.y < 1.0) {
                acc += (texture2D(depthtex1, p).r >= 1.0 ? 1.0 : 0.0) * w;
            }
            w *= 0.93;
        }
        acc /= 9.0;

        float aspect = viewWidth / viewHeight;
        float prox = exp(-length((texcoord - sUV) * vec2(aspect, 1.0)) * 1.8);
        vec3 rc = mix(vec3(0.45, 0.50, 1.00) * 0.4, mix(vec3(1.0, 0.90, 0.75), vec3(1.0, 0.45, 0.60), dusk), day);
        col += rc * acc * prox * GODRAY_STRENGTH * 0.35 * (1.0 - rainStrength * 0.8);
    }
#endif

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col, 1.0);
}
