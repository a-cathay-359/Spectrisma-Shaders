#version 330 compatibility

// ============================================================
// Spectrisma Shaders v1.1 - 半透明面顶点（水 / 玻璃 / 冰）
// ============================================================
#include "/include/ss_settings.glsl"

in vec4 mc_Entity;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 tint;
out vec3 viewPos;
out vec3 worldPos;
out vec4 shadowPos;
out float blockId;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord  = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint     = gl_Color;
    blockId  = mc_Entity.x;

    gl_Position = ftransform();

    vec3 v = (gl_ModelViewMatrix * gl_Vertex).xyz;
    viewPos = v;
    // 相机相对的世界坐标：水面波纹用它算，才能跨方块连续
    worldPos = mat3(gbufferModelViewInverse) * v;
    shadowPos = shadowProjection * shadowModelView * gbufferModelViewInverse * vec4(v, 1.0);
}
