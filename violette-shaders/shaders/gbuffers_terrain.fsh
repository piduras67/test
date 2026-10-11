#version 120
#include "/lib/settings.glsl"

uniform sampler2D texture;
uniform sampler2D normals;
uniform sampler2D specular;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normal;
varying vec3 tangent;
varying vec3 bitangent;
varying float material;

void main() {
    vec4 c = texture2D(texture, texcoord);
    if (c.a < 0.1) discard;
    vec3 albedo = c.rgb * glcolor.rgb;

    vec3 N = normalize(normal);
    vec4 spec = vec4(0.0);   // smoothness, f0, emissive, unused

#ifdef PBR_SUPPORT
    // LabPBR resource packs: normal map in rg, AO in b, specular in a separate texture.
    // Resource packs without these textures leave the values at their defaults.
    vec4 nt = texture2D(normals, texcoord);
    if (material < 0.25 && dot(nt.rg, nt.rg) > 0.0001) {
        vec2 xy = nt.rg * 2.0 - 1.0;
        float z = sqrt(max(1.0 - dot(xy, xy), 0.0));
        N = normalize(mat3(tangent, bitangent, normalize(normal)) * vec3(xy, z));
        albedo *= mix(1.0, nt.b, 0.9);

        vec4 sp = texture2D(specular, texcoord);
        float emis = (sp.a * 255.0 < 254.5) ? sp.a * 255.0 / 254.0 : 0.0;
        spec = vec4(sp.r, sp.g, emis, 1.0);
    }
#endif

    vec2 lm = clamp((lmcoord - 0.03125) * 1.0667, 0.0, 1.0);

    /* DRAWBUFFERS:0126 */
    gl_FragData[0] = vec4(albedo, 1.0);
    gl_FragData[1] = vec4(N * 0.5 + 0.5, 1.0);
    gl_FragData[2] = vec4(lm, material, 1.0);   // alpha 1 marks "deferred lit"
    gl_FragData[3] = spec;
}
