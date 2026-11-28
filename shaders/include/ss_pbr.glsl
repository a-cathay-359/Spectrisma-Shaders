// ============================================================
// Spectrisma Shaders v1.1 - PBR 函数库（高配使用）
// GGX 分布 / Smith 遮蔽 / 菲涅尔
// ============================================================
#ifndef SS_PBR_GLSL
#define SS_PBR_GLSL

#include "/include/ss_settings.glsl"

vec3 ssFresnelSchlick(float cosTheta, vec3 f0) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float ssDistributionGGX(vec3 n, vec3 h, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float nh = max(dot(n, h), 0.0);
    float d = nh * nh * (a2 - 1.0) + 1.0;
    return a2 / (3.14159265 * d * d);
}

float ssGeometrySmith(vec3 n, vec3 v, vec3 l, float roughness) {
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float nv = max(dot(n, v), 0.0);
    float nl = max(dot(n, l), 0.0);
    float gv = nv / (nv * (1.0 - k) + k);
    float gl = nl / (nl * (1.0 - k) + k);
    return gv * gl;
}

// 单光源 PBR 曝光项；金属度/粗糙度由材质入口给出
vec3 ssPBRSpecular(vec3 albedo, vec3 n, vec3 v, vec3 l, float metallic, float roughness, vec3 lightColor) {
    vec3 h = normalize(v + l);
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    float ndf = ssDistributionGGX(n, h, roughness);
    float g = ssGeometrySmith(n, v, l, roughness);
    vec3 f = ssFresnelSchlick(max(dot(h, v), 0.0), f0);
    float nv = max(dot(n, v), 0.0);
    float nl = max(dot(n, l), 0.0);
    vec3 spec = (ndf * g * f) / max(4.0 * nv * nl, 0.001);
    return spec * lightColor * nl;
}

#endif
