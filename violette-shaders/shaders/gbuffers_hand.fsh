#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;

void main() {
    vec4 c = texture2D(texture, texcoord) * glcolor;
    c.rgb = mix(c.rgb, entityColor.rgb, entityColor.a);
    c.rgb *= texture2D(lightmap, lmcoord).rgb;

    /* DRAWBUFFERS:0126 */
    gl_FragData[0] = c;
    gl_FragData[1] = vec4(0.0);   // not deferred lit
    gl_FragData[2] = vec4(0.0);
    gl_FragData[3] = vec4(0.0);
}
