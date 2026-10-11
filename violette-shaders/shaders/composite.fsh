#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

// Pass 0: screen-space ambient occlusion into colortex4.

uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex1;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

varying vec2 texcoord;

vec3 viewPos(vec2 uv, float d) {
    vec4 v = gbufferProjectionInverse * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
    return v.xyz / v.w;
}

void main() {
    float ao = 1.0;

#ifdef SSAO
    float d = texture2D(depthtex1, texcoord).r;
    if (d < 1.0 && texture2D(colortex2, texcoord).a > 0.5) {
        vec3 pos = viewPos(texcoord, d);
        vec3 N = normalize(texture2D(colortex1, texcoord).xyz * 2.0 - 1.0);
        vec3 t = (abs(N.y) < 0.99) ? normalize(cross(N, vec3(0.0, 1.0, 0.0))) : normalize(cross(N, vec3(1.0, 0.0, 0.0)));
        vec3 b = cross(N, t);

        float rot = ign(gl_FragCoord.xy) * 6.28318;
        float rad = SSAO_RADIUS * 0.9;
        float occ = 0.0;

        for (int i = 0; i < SSAO_SAMPLES; i++) {
            float fi = (float(i) + 0.5) / float(SSAO_SAMPLES);
            float a = float(i) * 2.39996 + rot;
            float r = sqrt(fi);
            vec3 dir = t * cos(a) * r + b * sin(a) * r + N * sqrt(max(1.0 - fi, 0.0));
            vec3 sp = pos + dir * rad * (0.15 + 0.85 * fi * fi);

            vec4 c = gbufferProjection * vec4(sp, 1.0);
            if (c.w > 0.0) {
                vec2 uv = c.xy / c.w * 0.5 + 0.5;
                if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
                    float sd = texture2D(depthtex1, uv).r;
                    float sz = viewPos(uv, sd).z;
                    float diff = sz - sp.z;               // positive: a surface sits in front of the sample
                    float range = smoothstep(0.0, 1.0, rad / max(abs(pos.z - sz), 0.001));
                    occ += step(0.03, diff) * range;
                }
            }
        }
        ao = 1.0 - occ / float(SSAO_SAMPLES);
        ao = pow(clamp(ao, 0.0, 1.0), SSAO_STRENGTH * 1.5);
    }
#endif

    /* DRAWBUFFERS:4 */
    gl_FragData[0] = vec4(ao, ao, ao, 1.0);
}
