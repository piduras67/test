// Foliage wind. Needs: uniform float frameTimeCounter. Include after settings.glsl.
// Block ids come from block.properties:
//   10001 short plants   10002 tall plant (lower half)   10003 tall plant (upper half)   10004 leaves
vec3 waveOffset(vec3 wp, int id, bool top) {
    float amp = 0.0;
    if (id == 10001)      amp = top ? 1.0 : 0.0;
    else if (id == 10002) amp = top ? 1.0 : 0.0;
    else if (id == 10003) amp = top ? 2.0 : 1.0;
    else if (id == 10004) amp = 0.55;
    if (amp <= 0.0) return vec3(0.0);

    float t = frameTimeCounter * WAVE_SPEED;
    float ph = wp.x * 0.7 + wp.z * 0.9;
    float gx = sin(t * 1.3 + ph) + 0.5 * sin(t * 2.7 + ph * 1.9 + 1.7);
    float gz = cos(t * 1.1 + wp.z * 0.8 - wp.x * 0.5) + 0.4 * sin(t * 3.1 + ph * 2.3);
    float s = 0.045 * WAVE_AMOUNT * amp;
    float lift = (id == 10004) ? 0.25 * sin(t * 1.9 + ph * 1.3) : 0.0;
    return vec3(gx * s, lift * s, gz * s * 0.7);
}
