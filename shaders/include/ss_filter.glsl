// ============================================================
// Spectrisma Shaders v1.1 - 色彩滤镜系统（全档位通用）
// 顺序：色调映射 -> 滤镜 -> 玩家滑块
// ============================================================
#ifndef SS_FILTER_GLSL
#define SS_FILTER_GLSL

#include "/include/ss_utils.glsl"

#ifndef EXPOSURE
    #define EXPOSURE 1.0
#endif
#ifndef SATURATION
    #define SATURATION 1.0
#endif
#ifndef CONTRAST
    #define CONTRAST 1.0
#endif

vec3 filterNone(vec3 c) {
    return c;
}

vec3 filterVivid(vec3 c) {
    c = ssSaturation(c, 1.32);
    c *= 1.06;
    float greenBias = smoothstep(0.0, 0.30, c.g - max(c.r, c.b));
    c.g *= mix(1.0, 1.12, greenBias);
    float blueBias = smoothstep(0.0, 0.30, c.b - max(c.r, c.g));
    c.b *= mix(1.0, 1.10, blueBias);
    return c;
}

vec3 filterRealistic(vec3 c) {
    c *= vec3(1.00, 0.97, 1.06);
    c = ssSCurve(c, 0.38);
    c = ssSaturation(c, 0.90);
    return c;
}

vec3 filterCold(vec3 c) {
    c *= vec3(0.92, 0.99, 1.12);
    c = ssSCurve(c, 0.15);
    c = ssSaturation(c, 0.95);
    return c;
}

vec3 filterWarm(vec3 c) {
    c *= vec3(1.12, 1.00, 0.88);
    c = ssSCurve(c, 0.15);
    c = ssSaturation(c, 0.97);
    return c;
}

vec3 filterAnime(vec3 c) {
    c = ssSaturation(c, 1.55);
    c = ssSCurve(c, 0.55);
    float l = ssLuma(c);
    vec3 shadowTint = vec3(0.46, 0.40, 0.72);
    c = mix(shadowTint, c, smoothstep(0.05, 0.55, l));
    c = mix(c, vec3(1.0), 0.04);
    return c;
}

vec3 ssApplyFilter(vec3 c) {
#if FILTER == 1
    return filterVivid(c);
#elif FILTER == 2
    return filterRealistic(c);
#elif FILTER == 3
    return filterCold(c);
#elif FILTER == 4
    return filterWarm(c);
#elif FILTER == 5
    return filterAnime(c);
#else
    return filterNone(c);
#endif
}

vec3 ssUserAdjust(vec3 c) {
    c *= EXPOSURE;
    c = ssSaturation(c, SATURATION);
    c = ssSCurve(c, clamp(CONTRAST - 1.0, 0.0, 1.0));
    return c;
}

// 轻量软高光压缩：只对 0.75 以上的高光段做软肩过渡，
// 暗部和中间调原样保留。中配/低配没有 ACES，裸线性输出一旦超 1
// 就被 clamp 成一片死白，浅色方块的 albedo 和环境色全被洗掉；
// 这道软肩把超亮部分压回渐变区间，高光还能看出层次和颜色。
vec3 ssSoftHighlight(vec3 c) {
    vec3 hi = max(c - 0.75, 0.0);
    hi = hi * hi / (hi + 0.30);
    return c - hi;
}

vec3 ssToneMap(vec3 c) {
#ifdef SS_ENABLE_ACES
    return ssACES(c * 1.02);
#else
    return ssSoftHighlight(c);
#endif
}

#endif
