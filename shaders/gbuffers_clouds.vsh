#version 330 compatibility

// ============================================================
// Spectrisma Shaders v1.1 - 原版云层
// 丐版与高配（体积云接管）直接丢弃，其余档位保留原版云
// ============================================================
#include "/include/ss_settings.glsl"

out vec2 texcoord;
out vec4 tint;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    tint = gl_Color;
}
