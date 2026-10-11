#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 5: automatic exposure, filmic tonemap, violet/pink split toning. Output is display-ready gamma.

/*
const int colortex5Format = R16F;
const bool colortex5Clear = false;
*/

uniform sampler2D colortex0;
uniform sampler2D colortex5;
uniform float frameTime;

varying vec2 texcoord;

vec3 aces(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
    float prevExp = texture2D(colortex5, vec2(0.5)).r;
    float expo = 1.0;

#ifdef AUTO_EXPOSURE
    // weighted average brightness of the screen, center counts most
    float sum = 0.0;
    float wsum = 0.0;
    for (int x = 0; x < 5; x++) {
        for (int y = 0; y < 5; y++) {
            vec2 p = vec2(0.1 + 0.2 * float(x), 0.1 + 0.2 * float(y));
            vec2 q = p - 0.5;
            float w = exp(-dot(q, q) * 6.0);
            sum += log(max(luma(texture2D(colortex0, p).rgb), 0.001)) * w;
            wsum += w;
        }
    }
    float avg = exp(sum / wsum);
    float targetExp = clamp(pow(0.22 / max(avg, 0.02), 0.6), 0.55, 2.2);

    // eyes adapt faster to bright light than to darkness
    float rate = (targetExp < prevExp) ? 2.0 : 0.8;
    expo = (prevExp < 0.01) ? targetExp : mix(prevExp, targetExp, 1.0 - exp(-frameTime * rate));
#endif

    vec3 c = texture2D(colortex0, texcoord).rgb * EXPOSURE * expo;
    c = aces(c);

    float l = luma(c);
    vec3 shadowTint = vec3(0.42, 0.20, 0.95) * 1.6;
    vec3 highTint   = vec3(1.00, 0.45, 0.75) * 1.1;
    c = mix(c, c * mix(shadowTint, highTint, smoothstep(0.0, 0.9, l)), TINT_STRENGTH);

    c = mix(vec3(luma(c)), c, SATURATION);
    c = (c - 0.5) * CONTRAST + 0.5;
    c = toGamma(clamp(c, 0.0, 1.0));

    /* DRAWBUFFERS:05 */
    gl_FragData[0] = vec4(c, 1.0);
    gl_FragData[1] = vec4(expo, 0.0, 0.0, 1.0);
}
