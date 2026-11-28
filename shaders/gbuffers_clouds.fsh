#version 330 compatibility

#include "/include/ss_settings.glsl"

uniform sampler2D gtexture;

in vec2 texcoord;
in vec4 tint;

void main() {
#if defined(SS_NO_VANILLA_CLOUDS) || defined(SS_PRESET_HIGH)
    // 丐版不要云；中/高配由 final 的体积云接管，这里必须彻底丢弃原版方块云
    discard;
    return;
#endif
    gl_FragColor = texture2D(gtexture, texcoord) * tint;
}
