#version 120

// Violette: tonemap, violet/pink split tone, vignette.

#define TINT_STRENGTH 0.28 // [0.0 0.14 0.28 0.4 0.55]
#define SATURATION 1.18    // [0.9 1.0 1.18 1.3 1.5]
#define VIGNETTE 1.1       // [0.0 0.6 1.1 1.6]

uniform sampler2D colortex0;

varying vec2 texcoord;

vec3 aces(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
    vec3 c = texture2D(colortex0, texcoord).rgb;
    c = aces(c * 1.1);

    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));

    // shadows lean violet, highlights lean pink
    vec3 shadowTint = vec3(0.42, 0.20, 0.95) * 1.6;
    vec3 highTint   = vec3(1.00, 0.45, 0.75) * 1.1;
    c = mix(c, c * mix(shadowTint, highTint, smoothstep(0.0, 0.9, l)), TINT_STRENGTH);

    c = mix(vec3(l), c, SATURATION);
    c = (c - 0.5) * 1.06 + 0.5;

    vec2 d = texcoord - 0.5;
    c *= clamp(1.0 - dot(d, d) * VIGNETTE, 0.0, 1.0);

    gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
