#version 330 compatibility
/* RENDERTARGETS: 0,4 */

// ============================================================
// Spectrisma Shaders v1.6.1 - 水面 / 半透明面
//
// 中 / 高配：
//   - 波纹用世界坐标算，跨方块连续，不再一格一格断开
//   - 完全丢掉原版水体贴图，避免每格重复的 UV 图案
//   - 菲涅尔混合：掠射角映天空，俯视角透出底下
//   - 太阳 GGX 高光
//   - 水面法线写进 colortex4，供 final 做真·折射（rgb=法线, a=掩码）
// 丐版：纯色半透蓝
// ============================================================
#include "/include/ss_settings.glsl"
#include "/include/ss_utils.glsl"
#include "/include/ss_water.glsl"

#ifdef SS_ENABLE_SHADOW
    #include "/include/ss_shadow.glsl"
#endif

#ifdef SS_ENABLE_WATER_REFLECT
    #include "/include/ss_atmosphere.glsl"
    #include "/include/ss_pbr.glsl"
#endif

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform vec3 fogColor;
uniform float fogDensity;
uniform float far;
uniform vec3 sunPosition;
uniform float frameTimeCounter;
uniform int worldTime;
uniform int isEyeInWater;
uniform vec3 cameraPosition;

in vec2 texcoord;
in vec2 lmcoord;
in vec4 tint;
in vec3 viewPos;
in vec4 shadowPos;
in float blockId;
in vec3 worldPos;

void main() {
#ifdef SS_SOLID_WATER
    // 丐版：水强制纯色半透蓝（跳过纹理与光照采样）
    if (blockId > SS_ID_WATER - 0.6 && blockId < SS_ID_WATER + 1.6) {
        gl_FragData[0] = vec4(0.2, 0.4, 0.8, 0.6);
        gl_FragData[1] = vec4(0.0, 1.0, 0.0, 0.0);
        return;
    }
#endif

    vec3 blockL = texture2D(lightmap, vec2(lmcoord.x, 0.03125)).rgb;
    vec3 skyL   = texture2D(lightmap, vec2(0.03125, lmcoord.y)).rgb;

    float shadow = 1.0;
#ifdef SS_ENABLE_SHADOW
    // 法线偏移、投影、畸变、采样都在 ssShadow 内部完成
    shadow = ssShadow(viewPos);
#endif

    bool isWater = (blockId > 7.4 && blockId < 9.6);

#ifdef SS_ENABLE_WATER_REFLECT
    if (isWater) {
        // worldPos 是相机相对坐标，加上相机水平位置才是真正钉在世界里的点。
        // 不加这一步，水面波纹会黏在镜头上跟着人一起平移。
        vec3 wp = worldPos + vec3(cameraPosition.x, 0.0, cameraPosition.z);

        float sunY = sin(float(worldTime) / 24000.0 * 6.2831853);
        float dayLight = smoothstep(-0.10, 0.25, sunY);

        // 世界空间法线：吃的是世界 XZ，所以整片水面是连续的一张波面
        vec3 nW = ssWaterWaveNormal(wp.xz, frameTimeCounter, 0.075);
        vec3 vW = normalize(-worldPos);                              // 指向相机
        vec3 lW = normalize(mat3(gbufferModelViewInverse) * sunPosition);

        float fres = ssFresnel(dot(nW, vW));
        // 从水下看水面不会那么镜面
        if (isEyeInWater == 1) fres = min(fres, 0.30);

        // 反射方向取天空梯度；把向下的分量翻上来，避免反射到"天空底面"
        vec3 refl = reflect(-vW, nW);
        refl.y = abs(refl.y);

        vec3 sunCol = vec3(1.0, 0.95, 0.82) * dayLight;
        vec3 skyRefl = ssSkyGradient(normalize(refl), fogColor, fogColor * 0.55, lW, sunCol);
        skyRefl *= 0.35 + 0.65 * skyL;

        // 太阳在水面的高光条
        float spec = ssWaterSpecular(nW, lW, vW, 0.05) * shadow * dayLight;

        // 水体本色：偏青蓝，按可见光强度着色
        vec3 body = vec3(0.055, 0.170, 0.235) * (0.35 + 0.65 * skyL) + blockL * 0.9;

        vec3 color = mix(body, skyRefl, fres);
        color += sunCol * spec * 0.55;

        // 俯视透出水下地形，掠射角接近镜面
        float alpha = mix(0.60, 0.96, fres);

        // 雾
        float dist = length(viewPos);
        float expFog = 1.0 - exp(-fogDensity * fogDensity * dist * dist * 1.6);
        float airFog = 0.0;
        if (far > 16.0) {
            airFog = smoothstep(far * 0.55, far * 0.98, dist) * 0.7;
        }
        color = mix(color, fogColor, clamp(max(expFog, airFog), 0.0, 1.0));

        gl_FragData[0] = vec4(color, alpha);
        // 法线 + 水面掩码，final 拿到之后做折射
        // 法线编码到 0..1 再存，这样不依赖缓冲的浮点精度
        gl_FragData[1] = vec4(nW * 0.5 + 0.5, 1.0);
        return;
    }
#endif

    // ---------- 玻璃 / 冰等其它半透明方块：保持简单 ----------
    vec4 albedo = texture2D(gtexture, texcoord) * tint;
    vec3 light = blockL + skyL * shadow;
    vec3 color = albedo.rgb * light;

    float dist = length(viewPos);
    float expFog = 1.0 - exp(-fogDensity * fogDensity * dist * dist * 1.6);
    float airFog = 0.0;
    if (far > 16.0) {
        airFog = smoothstep(far * 0.55, far * 0.98, dist) * 0.7;
    }
    color = mix(color, fogColor, clamp(max(expFog, airFog), 0.0, 1.0));

    gl_FragData[0] = vec4(color, albedo.a);
    gl_FragData[1] = vec4(0.0, 1.0, 0.0, 0.0);
}
