#version 330 compatibility

// ============================================================
// Spectrisma Shaders v1.1 - 地形顶点（含植物随风摇摆）
// 摇摆只改变顶点位置，纯视觉，不影响任何游戏逻辑
// ============================================================
#include "/include/ss_settings.glsl"
#include "/include/ss_utils.glsl"

in vec4 mc_Entity;
in vec2 mc_midTexCoord;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform float frameTimeCounter;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 tint;
out vec3 viewPos;
out vec4 shadowPos;
out float blockId;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint     = gl_Color;
    blockId  = mc_Entity.x;

    vec4 vPos = gl_Vertex;

#ifndef SS_NO_PLANT_WIND
    if (ssIsPlant(blockId)) {
        // 只有上半截顶点参与摇摆，根部固定
        float upper = (gl_MultiTexCoord0.y < mc_midTexCoord.y) ? 1.0 : 0.0;
        float wave = sin(frameTimeCounter * 1.7 + vPos.x * 0.7 + vPos.z * 0.9)
                   + sin(frameTimeCounter * 2.9 + vPos.z * 1.3) * 0.35;
        vPos.x += wave * 0.045 * upper;
        vPos.z += wave * 0.020 * upper;
    }
#endif

    gl_Position = gl_ModelViewProjectionMatrix * vPos;

    vec3 v = (gl_ModelViewMatrix * vPos).xyz;
    viewPos = v;
    shadowPos = shadowProjection * shadowModelView * gbufferModelViewInverse * vec4(v, 1.0);
}
