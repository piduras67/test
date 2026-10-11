// Procedural sky. Include after declaring these uniforms:
//   sunPosition, moonPosition, upPosition, gbufferModelViewInverse, worldTime, frameTimeCounter
// and after settings.glsl. Call initSky() once at the top of main().

vec3 g_up;
vec3 g_sunDir;
vec3 g_moonDir;
float g_sunH;
float g_day;
float g_dusk;
float g_night;

void initSky() {
    g_up = normalize(upPosition);
    g_sunDir = normalize(sunPosition);
    g_moonDir = normalize(moonPosition);
    g_sunH = dot(g_sunDir, g_up);
    g_day = smoothstep(-0.10, 0.12, g_sunH);
    g_dusk = exp(-g_sunH * g_sunH * 14.0);
    g_night = 1.0 - g_day;
}

vec3 sunLightColor()  { return mix(vec3(1.00, 0.93, 0.82) * 1.5, vec3(1.00, 0.40, 0.52) * 1.2, g_dusk); }
vec3 moonLightColor() { return vec3(0.30, 0.38, 0.85) * 0.45; }

// Gradient, horizon band, sun and moon glow. No discs or stars, so it also works as fog color.
vec3 skyAtmosphere(vec3 dir, float rain) {
    float up = dot(dir, g_up);

    vec3 zenith  = mix(vec3(0.02, 0.03, 0.12), mix(vec3(0.09, 0.23, 0.74), vec3(0.26, 0.18, 0.52), g_dusk), g_day);
    vec3 horizon = mix(vec3(0.05, 0.05, 0.16), mix(vec3(0.50, 0.70, 0.98), vec3(1.00, 0.44, 0.62), g_dusk), g_day);

    vec3 g = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.5));

    float sd = max(dot(dir, g_sunDir), 0.0);
    float sunGlow = (pow(sd, 24.0) * 0.5 + pow(sd, 4.0) * 0.25 * g_dusk) * smoothstep(-0.2, 0.1, g_sunH);
    g += mix(vec3(1.00, 0.88, 0.70), vec3(1.00, 0.42, 0.55), g_dusk) * sunGlow;

    float md = max(dot(dir, g_moonDir), 0.0);
    g += vec3(0.35, 0.40, 0.90) * pow(md, 40.0) * 0.25 * g_night;

    g = mix(g, horizon * 0.6, 1.0 - smoothstep(-0.35, 0.0, up));
    g = mix(g, g * vec3(1.10, 0.85, 1.20), SKY_TINT * 0.6);
    g = mix(g, vec3(luma(g)) * 0.85, rain * 0.7);
    return g;
}

// Full sky: atmosphere plus sun disc, moon disc and stars.
vec3 skyFull(vec3 dir, float rain) {
    vec3 g = skyAtmosphere(dir, rain);

    float sd = dot(dir, g_sunDir);
    float sunDisc = smoothstep(0.9990, 0.9996, sd);
    g += sunLightColor() * sunDisc * 18.0 * smoothstep(-0.05, 0.05, g_sunH) * (1.0 - rain * 0.9);

    float md = dot(dir, g_moonDir);
    float moonDisc = smoothstep(0.9992, 0.9997, md);
    g = mix(g, vec3(0.75, 0.80, 1.00) * 3.0, moonDisc * g_night * (1.0 - rain));

    // stars turn with the sky
    vec3 wd = mat3(gbufferModelViewInverse) * dir;
    float ang = float(worldTime) * 0.000261799;
    float cs = cos(ang);
    float sn = sin(ang);
    wd = vec3(wd.x * cs - wd.y * sn, wd.x * sn + wd.y * cs, wd.z);
    vec3 cell = floor(wd * 150.0);
    float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    vec3 f = fract(wd * 150.0) - 0.5;
    float star = step(0.9975, h) * (1.0 - smoothstep(0.0, 0.3, length(f)));
    float tw = 0.7 + 0.3 * sin(frameTimeCounter * 3.0 + h * 40.0);
    float vis = g_night * (1.0 - rain) * smoothstep(0.0, 0.15, dot(dir, g_up)) * (1.0 - moonDisc);
    vec3 starCol = mix(vec3(1.0, 0.80, 0.90), vec3(0.80, 0.90, 1.00), fract(h * 91.0));
    g += starCol * star * tw * 2.5 * vis;
    return g;
}
