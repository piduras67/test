#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 4: bloom. Only genuinely bright HDR pixels glow.

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec3 glowPart(vec3 c) {
    return c * smoothstep(1.2, 3.0, luma(c));
}

void main() {
    vec3 col = texture2D(colortex0, texcoord).rgb;
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);

    vec3 bloom = vec3(0.0);
    float total = 0.0;
    for (int x = -3; x <= 3; x++) {
        for (int y = -3; y <= 3; y++) {
            vec2 o = vec2(float(x), float(y));
            float w = exp(-dot(o, o) / 7.0);
            bloom += glowPart(texture2D(colortex0, texcoord + o * px * 4.0).rgb) * w;
            total += w;
        }
    }
    bloom /= total;

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col + bloom * BLOOM_STRENGTH * 1.2, 1.0);
}
