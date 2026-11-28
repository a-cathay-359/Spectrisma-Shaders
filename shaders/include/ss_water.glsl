// ============================================================
// Spectrisma Shaders v1.1 - 水面：波形法线 / 菲涅尔 / 高光
// 全部为程序化计算，不采样额外贴图
// ============================================================
#ifndef SS_WATER_GLSL
#define SS_WATER_GLSL

#include "/include/ss_utils.glsl"

// 世界坐标下的水面波纹法线（y 朝上）。
// 关键点：这里吃的是世界 XZ，不是方块自己的 0..1 UV。
// 原来用 texcoord 导致每一格都从 0 重来一遍波浪，格子边界必然断开，
// 看上去就是一格一格分开的水。换成世界坐标后表面是连续的。
vec3 ssWaterWaveNormal(vec2 p, float t, float amp) {
    // 多组不同方向/波长的波叠加，频率互不成整数比，避免出现重复图案
    float dx = 0.0;
    float dz = 0.0;

    dx += cos(p.x * 1.70 + p.y * 1.10 + t * 1.30) * 0.30 * 1.70;
    dz += cos(p.x * 1.70 + p.y * 1.10 + t * 1.30) * 0.30 * 1.10;

    dx += cos(p.x * 1.10 - p.y * 2.30 - t * 1.05) * 0.30 * 1.10;
    dz -= cos(p.x * 1.10 - p.y * 2.30 - t * 1.05) * 0.30 * 2.30;

    dx += cos(p.x * 3.90 - p.y * 2.80 + t * 1.95) * 0.20 * 3.90;
    dz -= cos(p.x * 3.90 - p.y * 2.80 + t * 1.95) * 0.20 * 2.80;

    dx += cos(p.x * 2.60 + p.y * 4.20 + t * 1.60) * 0.20 * 2.60;
    dz += cos(p.x * 2.60 + p.y * 4.20 + t * 1.60) * 0.20 * 4.20;

    dx += cos(p.x * 8.10 + p.y * 6.40 + t * 2.60) * 0.10 * 8.10;
    dz += cos(p.x * 8.10 + p.y * 6.40 + t * 2.60) * 0.10 * 6.40;

    return normalize(vec3(-dx * amp, 1.0, -dz * amp));
}

float ssFresnel(float cosTheta) {
    return 0.02 + 0.98 * pow(1.0 - clamp(cosTheta, 0.0, 1.0), 5.0);
}

// 单光源 GGX 高光（太阳/月亮在水面形成的高光条）
float ssWaterSpecular(vec3 n, vec3 l, vec3 v, float roughness) {
    vec3 h = normalize(l + v);
    float nh = max(dot(n, h), 0.0);
    float a = roughness * roughness;
    float a2 = a * a;
    float d = nh * nh * (a2 - 1.0) + 1.0;
    float ndf = a2 / (3.14159265 * d * d);
    float nv = max(dot(n, v), 0.0);
    float nl = max(dot(n, l), 0.0);
    float spec = ndf * nl / max(4.0 * nv * nl + 0.001, 0.001);
    return clamp(spec, 0.0, 8.0);
}

#endif
