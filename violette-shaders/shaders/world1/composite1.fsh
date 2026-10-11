#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Nether / End: flat ambient plus warm block light. Output is linear HDR like the overworld pass.

/*
const int colortex0Format = RGBA16F;
*/

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
uniform sampler2D depthtex1;

varying vec2 texcoord;

void main() {
    vec3 col = toLinear(texture2D(colortex0, texcoord).rgb);
    float d1 = texture2D(depthtex1, texcoord).r;

    if (d1 < 1.0 && texture2D(colortex2, texcoord).a > 0.5) {
        vec3 N = normalize(texture2D(colortex1, texcoord).xyz * 2.0 - 1.0);
        vec2 lm = texture2D(colortex2, texcoord).xy;
        float ao = texture2D(colortex4, texcoord).r;
        float side = 0.75 + 0.25 * N.y;
        vec3 ambient = vec3(0.55, 0.50, 0.62) * side * AMBIENT_STRENGTH * ao;
        vec3 blockC = vec3(1.0, 0.60, 0.30) * pow(lm.x, 2.6) * 1.8 * BLOCKLIGHT_STRENGTH;
        col *= ambient + blockC;
    }

    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(col, 1.0);
}
