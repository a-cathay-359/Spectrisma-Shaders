// ============================================================
// Spectrisma Shaders v1.1 - 通用数学 / 随机 / 曲线
// ============================================================
#ifndef SS_UTILS_GLSL
#define SS_UTILS_GLSL

#include "/include/ss_settings.glsl"

// 光照方向与太阳方向（视线空间）。多个库都要用，放这里统一声明
uniform vec3 shadowLightPosition;

float ssLuma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 ssSCurve(vec3 c, float amount) {
    c = clamp(c, 0.0, 1.0);
    vec3 s = c * c * (3.0 - 2.0 * c);
    return mix(c, s, clamp(amount, 0.0, 1.0));
}

vec3 ssSaturation(vec3 c, float s) {
    return mix(vec3(ssLuma(c)), c, s);
}

vec3 ssACES(vec3 c) {
    const float a = 2.51;
    const float b = 0.03;
    const float d = 2.43;
    const float e = 0.59;
    const float f = 0.14;
    return clamp((c * (a * c + b)) / (c * (d * c + e) + f), 0.0, 1.0);
}

float ssHash1(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float ssHash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float ssHash3(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float ssNoise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ssHash2(i);
    float b = ssHash2(i + vec2(1.0, 0.0));
    float c = ssHash2(i + vec2(0.0, 1.0));
    float d = ssHash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float ssNoise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = ssHash3(i);
    float n100 = ssHash3(i + vec3(1.0, 0.0, 0.0));
    float n010 = ssHash3(i + vec3(0.0, 1.0, 0.0));
    float n110 = ssHash3(i + vec3(1.0, 1.0, 0.0));
    float n001 = ssHash3(i + vec3(0.0, 0.0, 1.0));
    float n101 = ssHash3(i + vec3(1.0, 0.0, 1.0));
    float n011 = ssHash3(i + vec3(0.0, 1.0, 1.0));
    float n111 = ssHash3(i + vec3(1.0, 1.0, 1.0));
    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z);
}

float ssFbm2(vec2 p) {
    return ssNoise2(p) * 0.60 + ssNoise2(p * 2.03 + 7.1) * 0.28 + ssNoise2(p * 4.11 + 13.7) * 0.12;
}

float ssFbm3(vec3 p) {
    return ssNoise3(p) * 0.62 + ssNoise3(p * 2.04 + 5.3) * 0.26 + ssNoise3(p * 4.07 + 11.9) * 0.12;
}

float ssGameDay(float worldTime) {
    return floor(worldTime / 24000.0);
}

float ssDither(vec2 fragCoord, float t) {
    return (ssHash2(fragCoord + fract(t) * 137.0) - 0.5) / 255.0;
}

// 植物判定（供随风摇摆使用，纯视觉）
bool ssIsPlant(float id) {
    return (id == 6.0 || id == 31.0 || id == 32.0 || id == 37.0 || id == 38.0 ||
            id == 39.0 || id == 40.0 || id == 59.0 || id == 83.0 || id == 106.0 ||
            id == 111.0 || id == 115.0 || id == 141.0 || id == 142.0 || id == 175.0);
}

#endif
