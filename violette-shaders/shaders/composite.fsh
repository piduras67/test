#version 120

// Violette: bloom pass. Bright areas bleed a soft glow into their surroundings.

#define BLOOM_STRENGTH 1.4 // [0.0 0.5 1.0 1.4 2.0 3.0]

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec3 brightPart(vec3 c) {
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    return c * smoothstep(0.65, 1.0, l);
}

void main() {
    vec3 col = texture2D(colortex0, texcoord).rgb;
    vec2 px = 1.0 / vec2(viewWidth, viewHeight);

    vec3 bloom = vec3(0.0);
    float total = 0.0;
    for (int x = -4; x <= 4; x++) {
        for (int y = -4; y <= 4; y++) {
            vec2 o = vec2(float(x), float(y));
            float w = exp(-dot(o, o) / 12.0);
            bloom += brightPart(texture2D(colortex0, texcoord + o * px * 3.0).rgb) * w;
            total += w;
        }
    }
    bloom /= total;

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col + bloom * BLOOM_STRENGTH, 1.0);
}
