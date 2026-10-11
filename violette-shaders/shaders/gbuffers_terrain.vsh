#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

varying vec2 texcoord;
varying vec2 lmcoord;
varying vec4 glcolor;
varying vec3 normal;
varying float material;

#include "/lib/waving.glsl"

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor  = gl_Color;

    int id = int(mc_Entity.x + 0.5);

    vec4 pos = gl_ModelViewMatrix * gl_Vertex;
    vec3 feet = (gbufferModelViewInverse * pos).xyz;

#ifdef WAVING_FOLIAGE
    feet += waveOffset(feet + cameraPosition, id, texcoord.y < mc_midTexCoord.y);
#endif

    gl_Position = gl_ProjectionMatrix * (gbufferModelView * vec4(feet, 1.0));

    normal = normalize(gl_NormalMatrix * gl_Normal);
    vec3 upN = normalize(mat3(gbufferModelView) * vec3(0.0, 1.0, 0.0));

    material = 0.0;
    if (id >= 10001 && id <= 10003) {
        // plants are lit as if facing the sky so they never go flat black
        normal = upN;
        material = 0.5;
    } else if (id == 10004) {
        normal = normalize(mix(normal, upN, 0.4));
        material = 0.5;
    }
}
