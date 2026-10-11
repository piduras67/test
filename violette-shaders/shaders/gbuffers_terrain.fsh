#version 120

uniform sampler2D texture;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normal;
varying float material;

void main() {
    vec4 c = texture2D(texture, texcoord);
    if (c.a < 0.1) discard;
    vec3 albedo = c.rgb * glcolor.rgb;

    vec2 lm = clamp((lmcoord - 0.03125) * 1.0667, 0.0, 1.0);

    /* DRAWBUFFERS:012 */
    gl_FragData[0] = vec4(albedo, 1.0);
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(lm, material, 1.0);   // alpha 1 marks "deferred lit"
}
