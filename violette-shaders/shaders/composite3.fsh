#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 4: exposure, filmic tonemap, violet/pink split toning. Output is display-ready gamma.

uniform sampler2D colortex0;

varying vec2 texcoord;

vec3 aces(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
    vec3 c = texture2D(colortex0, texcoord).rgb * EXPOSURE;
    c = aces(c);

    float l = luma(c);
    vec3 shadowTint = vec3(0.42, 0.20, 0.95) * 1.6;
    vec3 highTint   = vec3(1.00, 0.45, 0.75) * 1.1;
    c = mix(c, c * mix(shadowTint, highTint, smoothstep(0.0, 0.9, l)), TINT_STRENGTH);

    c = mix(vec3(luma(c)), c, SATURATION);
    c = (c - 0.5) * CONTRAST + 0.5;
    c = toGamma(clamp(c, 0.0, 1.0));

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(c, 1.0);
}
