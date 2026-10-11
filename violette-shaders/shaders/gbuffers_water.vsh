#version 120
#include "/lib/settings.glsl"

attribute vec4 mc_Entity;

uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 normal;
varying vec3 wpos;
varying float water;
varying float wup;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;

    vec4 pos = gl_ModelViewMatrix * gl_Vertex;
    wpos = (gbufferModelViewInverse * pos).xyz + cameraPosition;
    gl_Position = gl_ProjectionMatrix * pos;

    normal = normalize(gl_NormalMatrix * gl_Normal);
    wup = (gbufferModelViewInverse * vec4(normal, 0.0)).y;
    water = (int(mc_Entity.x + 0.5) == 10010) ? 1.0 : 0.0;
}
