#version 330 compatibility

// 阴影通道片元：只做 alpha 裁剪，不输出颜色
// 不做裁剪的话，树叶/草/栅栏会按整块四边形投出一方块硬阴影，
// 树影会变成一堆方块，看起来就是"阴影很脏"

uniform sampler2D gtexture;

in vec2 texcoord;

void main() {
    if (texture(gtexture, texcoord).a < 0.1) discard;
    gl_FragColor = vec4(1.0);
}
