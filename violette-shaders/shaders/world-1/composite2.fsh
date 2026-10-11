#version 120

// No light shafts outside the overworld.

uniform sampler2D colortex0;

varying vec2 texcoord;

void main() {
    /* DRAWBUFFERS:0 */
    gl_FragData[0] = vec4(texture2D(colortex0, texcoord).rgb, 1.0);
}
