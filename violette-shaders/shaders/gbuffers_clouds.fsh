#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    vec4 c = texture2D(texture, texcoord) * glcolor;

    /* DRAWBUFFERS:0126 */
    gl_FragData[0] = c;
    gl_FragData[1] = vec4(0.0);
    gl_FragData[2] = vec4(0.0);
    gl_FragData[3] = vec4(0.0);
}
