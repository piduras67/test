#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Final: FXAA, chromatic fringe, vignette, grain.

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

varying vec2 texcoord;

#define FXAA_REDUCE_MIN (1.0 / 128.0)
#define FXAA_REDUCE_MUL (1.0 / 8.0)
#define FXAA_SPAN_MAX 8.0

vec3 fxaa(vec2 uv, vec2 px) {
    vec3 rgbNW = texture2D(colortex0, uv + vec2(-1.0, -1.0) * px).rgb;
    vec3 rgbNE = texture2D(colortex0, uv + vec2( 1.0, -1.0) * px).rgb;
    vec3 rgbSW = texture2D(colortex0, uv + vec2(-1.0,  1.0) * px).rgb;
    vec3 rgbSE = texture2D(colortex0, uv + vec2( 1.0,  1.0) * px).rgb;
    vec3 rgbM  = texture2D(colortex0, uv).rgb;

    float lNW = luma(rgbNW);
    float lNE = luma(rgbNE);
    float lSW = luma(rgbSW);
    float lSE = luma(rgbSE);
    float lM  = luma(rgbM);
    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));

    vec2 dir;
    dir.x = -((lNW + lNE) - (lSW + lSE));
    dir.y =  ((lNW + lSW) - (lNE + lSE));

    float dirReduce = max((lNW + lNE + lSW + lSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
    float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2(FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX), dir * rcpDirMin)) * px;

    vec3 rgbA = 0.5 * (texture2D(colortex0, uv + dir * (1.0 / 3.0 - 0.5)).rgb
                     + texture2D(colortex0, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (texture2D(colortex0, uv + dir * -0.5).rgb
                                   + texture2D(colortex0, uv + dir *  0.5).rgb);
    float lB = luma(rgbB);
    return (lB < lMin || lB > lMax) ? rgbA : rgbB;
}

void main() {
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);
    vec3 c;
#ifdef FXAA
    c = fxaa(texcoord, px);
#else
    c = texture2D(colortex0, texcoord).rgb;
#endif

    if (CHROMATIC > 0.0) {
        vec2 off = (texcoord - 0.5) * CHROMATIC;
        c.r = texture2D(colortex0, texcoord + off).r;
        c.b = texture2D(colortex0, texcoord - off).b;
    }

    vec2 d = texcoord - 0.5;
    c *= clamp(1.0 - dot(d, d) * VIGNETTE * 1.1, 0.0, 1.0);

    float g = ign(gl_FragCoord.xy + frameTimeCounter * 60.0) - 0.5;
    c += g * FILM_GRAIN;

    gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
