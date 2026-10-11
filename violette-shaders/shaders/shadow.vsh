#version 120
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

attribute vec4 mc_Entity;
attribute vec2 mc_midTexCoord;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;

varying vec2 texcoord;
varying vec4 glcolor;

#include "/lib/waving.glsl"

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;

    vec4 pos = gl_ModelViewMatrix * gl_Vertex;
    vec3 feet = (shadowModelViewInverse * pos).xyz;

#ifdef WAVING_FOLIAGE
    feet += waveOffset(feet + cameraPosition, int(mc_Entity.x + 0.5), texcoord.y < mc_midTexCoord.y);
#endif

    gl_Position = gl_ProjectionMatrix * (shadowModelView * vec4(feet, 1.0));
    gl_Position.xy = shadowDistort(gl_Position.xy);
}
