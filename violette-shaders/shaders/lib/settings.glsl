// Violette settings. Every option here shows up in the in-game Shader Options screen.

// ---------------- Lighting ----------------
#define SHADOW_SAMPLES 8          // [4 6 8 12 16]
#define SHADOW_SOFTNESS 1.5       // [0.5 1.0 1.5 2.0 3.0]
#define SHADOW_DISTORT 0.85       // [0.7 0.8 0.85 0.9 0.95]
#define SUN_STRENGTH 1.0          // [0.5 0.75 1.0 1.25 1.5]
#define AMBIENT_STRENGTH 1.0      // [0.5 0.75 1.0 1.25 1.5 2.0]
#define BLOCKLIGHT_STRENGTH 1.0   // [0.5 0.75 1.0 1.25 1.5 2.0]

// ---------------- Foliage ----------------
#define WAVING_FOLIAGE
#define WAVE_SPEED 1.0            // [0.5 0.75 1.0 1.5 2.0]
#define WAVE_AMOUNT 1.0           // [0.5 0.75 1.0 1.5 2.0]

// ---------------- Water ----------------
#define WATER_WAVE_HEIGHT 1.0     // [0.0 0.5 1.0 1.5 2.0]
#define WATER_OPACITY 0.6         // [0.3 0.45 0.6 0.75 0.9]
#define WATER_REFLECTIONS 1.0     // [0.0 0.5 1.0 1.5]

// ---------------- Atmosphere ----------------
#define FOG_DENSITY 1.0           // [0.0 0.5 1.0 1.5 2.0]
#define SKY_TINT 0.55             // [0.0 0.25 0.55 0.75 1.0]
#define GODRAYS
#define GODRAY_STRENGTH 0.6       // [0.2 0.4 0.6 0.8 1.2]

// ---------------- Post processing ----------------
#define BLOOM_STRENGTH 0.9        // [0.0 0.4 0.9 1.4 2.0]
#define EXPOSURE 1.0              // [0.7 0.85 1.0 1.15 1.3]
#define TINT_STRENGTH 0.22        // [0.0 0.11 0.22 0.33 0.45]
#define SATURATION 1.12           // [0.9 1.0 1.12 1.25 1.4]
#define CONTRAST 1.06             // [0.95 1.0 1.06 1.12 1.2]
#define VIGNETTE 1.0              // [0.0 0.5 1.0 1.5]
#define FILM_GRAIN 0.03           // [0.0 0.02 0.03 0.05]
#define CHROMATIC 0.0015          // [0.0 0.0008 0.0015 0.003]
#define FXAA
