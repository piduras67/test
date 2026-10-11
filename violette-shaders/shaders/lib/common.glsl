// Shared helpers. Include after settings.glsl.

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
vec3 toGamma(vec3 c)  { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }

// interleaved gradient noise, good for shadow sample rotation
float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Pulls shadow map resolution toward the player.
vec2 shadowDistort(vec2 p) {
    float f = length(p) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT);
    return p / f;
}

// Patches of standing water on exposed, upward-facing ground when it rains.
float puddleNoise(vec2 p) {
    return smoothstep(0.52, 0.72, vnoise(p * 0.35) * 0.65 + vnoise(p * 1.1) * 0.35);
}

// Moving light patterns on the sea floor.
float causticPattern(vec2 p, float t) {
    float a = vnoise(p * 1.7 + vec2(t * 0.35, t * 0.20));
    float b = vnoise(p * 2.9 - vec2(t * 0.25, -t * 0.30) + 7.3);
    float c = 1.0 - abs(a + b - 1.0);
    return pow(clamp(c, 0.0, 1.0), 6.0);
}
