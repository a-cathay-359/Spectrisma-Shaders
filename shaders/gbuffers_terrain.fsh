#version 330 compatibility
/* RENDERTARGETS: 0,4 */

// ============================================================
// Spectrisma Shaders v1.2 - 地形片元
// 光照 = 方块光 + 天空光 × 阴影（原版等效）+ 距离雾 + 指数雾
// 丐版：岩浆强制纯色、无阴影
// ============================================================
#include "/include/ss_settings.glsl"
#include "/include/ss_utils.glsl"

#ifdef SS_ENABLE_SHADOW
    #include "/include/ss_shadow.glsl"
#endif

#ifdef SS_ENABLE_PBR
    #include "/include/ss_pbr.glsl"
#endif

uniform sampler2D gtexture;
uniform vec3 sunPosition;
uniform sampler2D lightmap;
uniform vec3 fogColor;
uniform float fogDensity;
uniform float far;
uniform int worldTime;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 tint;
in vec3 viewPos;
in vec4 shadowPos;
in float blockId;

void main() {
    // 地形像素一律不是水面：显式清零掩码，杜绝上一帧残留
    gl_FragData[1] = vec4(0.5, 0.5, 0.5, 0.0);

    vec4 albedo = texture2D(gtexture, texcoord) * tint;

#ifdef SS_SOLID_LAVA
    // 丐版：岩浆换纯色橙混凝土，取消动态
    if (blockId > SS_ID_FLOW_LAVA - 0.6 && blockId < SS_ID_STILL_LAVA + 0.6) {
        gl_FragColor = vec4(0.878, 0.443, 0.078, 1.0);
        return;
    }
#endif

    if (albedo.a < 0.1) {
        discard;
    }

    // 光照贴图拆分：blockL（自发光/火光） + skyL × 阴影
    vec3 blockL = texture2D(lightmap, vec2(lmcoord.x, 0.03125)).rgb;
    vec3 skyL   = texture2D(lightmap, vec2(0.03125, lmcoord.y)).rgb;

    // 昼夜强度（与 final.fsh 同一套：0 = 午夜，1 = 正午）
    float sunY = sin(float(worldTime) / 24000.0 * 6.2831853);
    float dayLight = smoothstep(-0.10, 0.25, sunY);

    float shadow = 1.0;
#ifdef SS_ENABLE_SHADOW
    // 法线偏移、投影、畸变、采样全部在新版 ssShadow 内部完成，
    // 这里只需要把视线空间位置交给它
    shadow = ssShadow(viewPos);
#endif

    // 镜面高光单独累加，不混进 light（混进去会被 albedo 再乘一遍）
    vec3 specAdd = vec3(0.0);

#ifdef SS_ENABLE_DIFFUSE
    // ---------------- 漫反射 ----------------
    // 原来不管面朝哪都是 blockL + skyL×shadow，等于所有面一样亮，方块没有体积感。
    // 这里拆成两束：
    //   天光  —— 朝上的面吃满，朝下的面只剩散射（半球积分的最简近似）
    //   直射  —— 按 N·L 加权，并且只有没被遮住时才给
    vec3 vnRaw = cross(dFdx(viewPos), dFdy(viewPos));
    float vnLen = length(vnRaw);
    vec3 viewN = vnLen > 1.0e-5 ? vnRaw / vnLen : normalize(-viewPos);
    vec3 worldN = normalize(mat3(gbufferModelViewInverse) * viewN);

    // 屏幕导数重建的法线在两个面相交的那一像素上是"混的"（2×2 像素块里
    // 两个面各占一半），会沿方块棱边压出一圈一像素的错角色带。
    // 地形基本都是轴对齐的，把法线吸附到最近的主轴就能彻底消掉这条带。
    vec3 an = abs(worldN);
    vec3 snapN = (an.y >= an.x && an.y >= an.z)
                 ? vec3(0.0, worldN.y >= 0.0 ? 1.0 : -1.0, 0.0)
                 : (an.x >= an.z
                    ? vec3(worldN.x >= 0.0 ? 1.0 : -1.0, 0.0, 0.0)
                    : vec3(0.0, 0.0, worldN.z >= 0.0 ? 1.0 : -1.0));

    // 光照方向：有阴影时用真正的光源方向（白天太阳 / 夜里月亮）
    vec3 lw = mat3(gbufferModelViewInverse) * shadowLightPosition;
    if (dot(lw, lw) < 1.0e-6) lw = mat3(gbufferModelViewInverse) * sunPosition;
    vec3 lightDirW = normalize(lw);

    float ndotl = max(dot(snapN, lightDirW), 0.0);
    float upness = 0.5 + 0.5 * snapN.y;               // 0 = 朝下，1 = 朝上
    // 环境光要压住：太阳低的时候直射本来就弱，
    // 环境光一旦给高，阴影就只剩三成差异，看上去等于没有阴影。
    // 但顶面/侧面的差距也不能大 —— 大了每个方块都会显得"切"出来一块。
    // 夜晚环境光额外压一档：光照贴图本身已经带了夜色，再叠中性白系数
    // 会把浅色方块抬成死白、洗掉蓝紫环境色。
    float skyTerm = mix(0.22 + 0.06 * upness, 0.32 + 0.10 * upness, dayLight);

    // 光源色调：太阳低时偏暖，深夜换成月光的冷蓝
    vec3 sunDirW = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float elev = clamp(lightDirW.y, 0.0, 1.0);
    vec3 warm = mix(vec3(1.00, 0.72, 0.42), vec3(1.00, 0.95, 0.84), smoothstep(0.0, 0.30, elev));
    vec3 lightTint = sunDirW.y > -0.05 ? warm : vec3(0.62, 0.74, 1.00);

    // 直射强度：白天太阳 0.80，夜里月光偏弱 0.55 —— 月光本就比太阳柔，
    // 给足了浅色受光面会直接顶到纯白。
    float directK = mix(0.55, 0.80, dayLight);
    float sunTerm = ndotl * shadow * directK;

    vec3 light = blockL + skyL * (skyTerm + sunTerm * lightTint);

#ifdef SS_ENABLE_PBR
    // 高配：加一层 GGX 镜面。方块没有金属度/粗糙度贴图，
    // 统一按"粗糙电介质"处理（f0 = 0.04，roughness 0.78）。
    // 注意是加到最终颜色上、不是加到 light 里 —— 加进 light 会被
    // albedo 再乘一遍，深色方块的高光会直接消失。
    vec3 vW = normalize(mat3(gbufferModelViewInverse) * normalize(-viewPos));
    vec3 spec = ssPBRSpecular(albedo.rgb, snapN, vW, lightDirW, 0.0, 0.78,
                              lightTint * (shadow * 0.85));
    specAdd = min(spec, vec3(6.0)) * 0.55;
#endif
#else
    vec3 light = blockL + skyL * shadow;
#endif

    vec3 color = albedo.rgb * light + specAdd;

    // 雾：水下/岩浆/细雪用指数雾；空气中用视距雾，避免远处地形硬切
    float dist = length(viewPos);
    float expFog = 1.0 - exp(-fogDensity * fogDensity * dist * dist * 1.6);
    float airFog = 0.0;
    if (far > 16.0) {
        airFog = smoothstep(far * 0.55, far * 0.98, dist) * 0.7;
    }
    float fogFactor = clamp(max(expFog, airFog), 0.0, 1.0);
    color = mix(color, fogColor, fogFactor);

    gl_FragColor = vec4(color, 1.0);
}
