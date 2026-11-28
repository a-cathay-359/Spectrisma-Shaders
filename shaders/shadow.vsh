#version 330 compatibility

// ============================================================
// 阴影通道：仅写深度，不改动任何实体渲染开关
//
// 【关键】这里必须对顶点位置做"阴影畸变"，把贴图中心的采样密度放大。
// 采样端（include/ss_shadow.glsl 的 ssShadowDistort）用的是同一套公式，
// 两边不一致就会出现整体错位的阴影。
// ============================================================

#include "/include/ss_settings.glsl"

const float ssShadowMapBias = 1.0 - 25.6 / shadowDistance;

vec3 ssShadowDistort(vec3 pos) {
    float factor = length(pos.xy) * ssShadowMapBias + (1.0 - ssShadowMapBias);
    return vec3(pos.xy / factor, pos.z * 0.2);
}

out vec2 texcoord;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    gl_Position = ftransform();
    // 阴影投影是正交投影（w = 1），裁剪空间坐标可以直接当 NDC 用
    gl_Position.xyz = ssShadowDistort(gl_Position.xyz);
}
