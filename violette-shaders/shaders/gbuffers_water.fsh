#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D texture;
uniform mat4 gbufferModelView;
uniform float frameTimeCounter;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 normal;
varying vec3 wpos;
varying float water;
varying float wup;

// layered travelling waves plus a little noise
float waveH(vec2 p) {
    float t = frameTimeCounter * 0.9;
    float h = 0.0;
    h += sin(p.x * 1.25 + t * 1.1 + sin(p.y * 0.7 + t * 0.6)) * 0.50;
    h += sin(p.y * 1.70 - t * 1.3 + p.x * 0.4) * 0.35;
    h += sin((p.x + p.y) * 2.6 + t * 1.9) * 0.15;
    h += (vnoise(p * 2.3 + vec2(t * 0.4, -t * 0.3)) - 0.5) * 0.5;
    return h * 0.05 * WATER_WAVE_HEIGHT;
}

void main() {
    vec4 t = texture2D(texture, texcoord) * glcolor;
    vec3 N = normal;
    vec4 outColor;
    float isWater = 0.0;

    if (water > 0.5) {
        isWater = 1.0;
        if (wup > 0.9 && WATER_WAVE_HEIGHT > 0.0) {
            vec2 p = wpos.xz;
            float e = 0.07;
            float h0 = waveH(p);
            float hx = waveH(p + vec2(e, 0.0));
            float hz = waveH(p + vec2(0.0, e));
            vec3 wn = normalize(vec3(-(hx - h0) / e, 1.0, -(hz - h0) / e));
            N = normalize(mat3(gbufferModelView) * wn);
        }
        vec3 deep = vec3(0.10, 0.24, 0.62);
        vec3 col = mix(t.rgb, deep, 0.55);
        outColor = vec4(col, WATER_OPACITY);
    } else {
        outColor = t;   // stained glass, ice and friends
    }

    /* DRAWBUFFERS:03 */
    gl_FragData[0] = outColor;
    gl_FragData[1] = vec4(N * 0.5 + 0.5, isWater);   // alpha 0 leaves earlier data alone
}
