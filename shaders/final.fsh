#version 330 compatibility

// ============================================================
// Spectrisma Shaders v1.2 - 最终后处理（全包唯一屏幕输出口）
// 顺序：水下折射 -> 场景采样 -> FXAA -> 正圆日月 -> 去星点
//       -> SSAO -> GodRays -> 体积云 -> 流星雨 -> 焦散
//       -> ACES -> 滤镜 -> 曝光/饱和/对比度 -> 抖动
// 注：屏幕空间反射（SSR）已移除——自定义掩码在部分移动版 Iris 上不可靠，
// 误判到草地后会把远处地形颜色沿反射射线拷回来，形成放射条纹扇面。
// ============================================================

#include "/include/ss_settings.glsl"
#include "/include/ss_filter.glsl"
#include "/include/ss_post.glsl"
#include "/include/ss_atmosphere.glsl"

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;  // 不含半透明面的不透明深度：用来判定当前像素是不是水面/玻璃
uniform sampler2D colortex4;   // gbuffers_water 写入：rgb=世界法线, a=水面掩码
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform int worldTime;
uniform int isEyeInWater;
uniform vec3 fogColor;

in vec2 texcoord;

void main() {
    vec2 res = vec2(textureSize(colortex0, 0));
    vec2 texel = 1.0 / res;
    float aspect = res.x / res.y;

    // 太阳高度（0 = 日出，6000 = 正午，18000 = 午夜）
    float sunY = sin(float(worldTime) / 24000.0 * 6.2831853);
    float dayLight = smoothstep(-0.10, 0.25, sunY);

    // 只在真正在水下时才做折射；否则整屏偏移会让深度与颜色错位，
    // 引发 SSAO 的光晕和边缘噪点
    vec2 uv = texcoord;
    if (isEyeInWater == 1) {
        uv = ssRefractUV(texcoord, frameTimeCounter);
    }
    vec3 color = texture2D(colortex0, uv).rgb;
    vec4 wn = texture2D(colortex4, texcoord);   // rgb 水面法线, a=掩码（辅助，不单独放行）

    float depth = texture2D(depthtex0, uv).r;
    float depth1 = texture2D(depthtex1, texcoord).r;
    vec3 pos = ssReconstructView(uv, depth, gbufferProjectionInverse);
    vec3 normal = normalize(cross(dFdx(pos), dFdy(pos)));

    // 水面判定以不透明深度 depthtex1 为准：水面/玻璃在半透明通道，
    // 深度比背后地形近；不透明地形两个深度相等。
    // 只靠 colortex4 的 alpha 在部分移动版 Iris 上不可靠——缓冲没被保留时
    // 会读到垃圾，把草地误判成水面，折射/反射沿错误法线拉出放射条纹。
    bool translucent = depth < depth1 - 1.0e-5;
    bool isWaterMask = translucent && depth < 0.9995;
    // 天空判定：不透明深度 depth1 也在远平面才算天空。
    // 只看 depth0 的紧阈值在手机端深度精度下会把远处地形漏过去，
    // 导致本该画在天空上的日月/光柱/云漏到远处地面上。
    // 兜底：若加载器没绑定 depthtex1（采样恒为 0），退回 depth0 门限，
    // 不至于把真天空上的日月/云/光柱整个关掉。
    bool depth1Unbound = depth1 <= 1.0e-6;
    bool isSky = depth >= 0.99995 && (depth1 >= 0.99995 || depth1Unbound);

    // ---------- 折射（中 / 高配） ----------
    // 只在水面像素上做：拿 gbuffers_water 写进来的水面法线，
    // 把采样点沿法线在屏幕空间的投影推开，水下的地形就被"折"了一下。
#ifdef SS_ENABLE_REFRACTION
    if (isEyeInWater != 1 && isWaterMask) {
        vec3 nW = vec3(0.0, 1.0, 0.0);
        if (wn.a > 0.5) {
            nW = normalize(wn.rgb * 2.0 - 1.0);
        }
        vec3 nV = transpose(mat3(gbufferModelViewInverse)) * nW;
        vec2 off = nV.xy * 0.020;
        vec2 ruv = clamp(texcoord + off, vec2(0.001), vec2(0.999));
        // 混大部分原色回去，岸边不会拉出硬缝
        color = mix(color, texture2D(colortex0, ruv).rgb, 0.60);
    }
#endif

    // ---------- 水面 SSR（高配） ----------
    // 只在水面像素上做，且必须已通过 depth < depth1 验证（下面这层门是硬的）。
    // 用波纹法线反出的真实反射方向去撞屏幕里的地形/天空，
    // 撞到就贴那段颜色，撞不到就保持原样（不叠加任何东西）。
#ifdef SS_ENABLE_WATER_SSR
    if (isEyeInWater != 1 && isWaterMask) {
        vec3 nW = vec3(0.0, 1.0, 0.0);
        if (wn.a > 0.5) {
            nW = normalize(wn.rgb * 2.0 - 1.0);
        }
        vec3 vW = normalize(mat3(gbufferModelViewInverse) * normalize(pos));
        vec3 rW = reflect(vW, nW);
        // 只反射地平线以上：水面不该照出水底
        if (rW.y > 0.03) {
            vec4 refl = ssWaterSSR(uv, pos, rW, colortex0, depthtex0,
                                   gbufferProjection, mat3(gbufferModelViewInverse), texel);
            float fres = pow(1.0 - max(dot(nW, -vW), 0.0), 5.0);
            if (refl.w > 0.5) {
                color = mix(color, refl.rgb, 0.38 * (0.35 + 0.65 * fres));
            }
        }
    }
#endif

    // ---------- FXAA（高配） ----------
#ifdef SS_ENABLE_FXAA
    color = ssFXAA(colortex0, uv, texel, ssLuma(color));
#endif

    // ---------- 正圆日月（中 / 高配） ----------
    // 角半径 3.34°（Complementary 同款）；外面套一个 12° 的擦除圈，
    // 把原版方块日月换成周围天空色，只留中间那个圆盘
#ifdef SS_ENABLE_ROUND_SUN
    if (isSky) {
        vec3 skyDir = normalize(ssReconstructView(uv, 1.0, gbufferProjectionInverse));
        vec3 skyDirW = normalize(mat3(gbufferModelViewInverse) * skyDir);
        vec3 sunDirW = normalize(mat3(gbufferModelViewInverse) * sunPosition);

        // 0.9983 / 12° 擦除圈：数值照 Complementary r5.9 最高配的 sunSizeFactor1。
        // 天体自己在地平线以下时函数会直接跳过，所以白天只处理太阳、
        // 夜里只处理月亮，日出日落交界两个都贴地平线、两个都处理。
        color = ssCelestialDisc(color, uv, skyDir, sunPosition, skyDirW, sunDirW,
                                fogColor, vec3(1.00, 0.80, 0.52) * 0.55,
                                colortex0, depthtex0, depthtex1, texel, gbufferProjection,
                                vec3(1.00, 0.92, 0.76) * 3.4, 0.9983, 0.2094, 0.16, -1);
        color = ssCelestialDisc(color, uv, skyDir, moonPosition, skyDirW, sunDirW,
                                fogColor, vec3(0.55, 0.64, 0.92) * 0.10,
                                colortex0, depthtex0, depthtex1, texel, gbufferProjection,
                                vec3(0.74, 0.81, 1.00) * 1.4, 0.9983, 0.2094, 0.10, moonPhase);
    }
#endif

    // ---------- 去星点（丐版） ----------
#ifdef SS_NO_STARS
    if (isSky) {
        color = ssRemoveStars(color, uv, texel, colortex0);
    }
#endif

    // ---------- SSAO ----------
#ifdef SS_ENABLE_SSAO
    if (depth < 0.9995) {
        float ao = ssSSAO(uv, depth, pos, normal, depthtex0, gbufferProjectionInverse, texel);
        color *= ao;
    }
#endif

    // ---------- GodRays ----------
#ifdef SS_ENABLE_GODRAYS
    vec2 sunUVg = ssProjectToScreen(normalize(sunPosition), gbufferProjection);
    // 太阳可见性：从硬开关改成平滑过渡，避免太阳刚进屏幕时整屏亮度跳变
    vec2 sunClamped = clamp(sunUVg, vec2(0.0, 0.0), vec2(1.0, 1.0));
    float sunDist = distance(sunUVg, sunClamped);
    float sunVisible = smoothstep(0.35, 0.0, sunDist);
    // GodRays 只在真正的天空像素上跑，云面跳过，避免碎深度刮出横向条纹
    // 太阳贴近地平线时淡出：此时射线方向上全是山脊，遮挡差会让光柱
    // 沿太阳方位角甩出放射状亮条纹（跟旧扇面很像），索性不给
    if (isSky) {
        float shaftFade = smoothstep(0.04, 0.30, sunY);
        color += ssGodRays(uv, sunUVg, sunVisible * dayLight * shaftFade,
                           depthtex0, vec3(1.0, 0.92, 0.78));
    }
#endif

    // ---------- 云层（中 / 高配） ----------
#ifdef SS_ENABLE_CLOUDS
    if (isSky) {
        vec3 viewDirV = normalize(ssReconstructView(uv, 1.0, gbufferProjectionInverse));
        vec3 worldDir = normalize(mat3(gbufferModelViewInverse) * viewDirV);
        vec3 sunDirW  = normalize(mat3(gbufferModelViewInverse) * sunPosition);

        // 白天暖白、黄昏橙红、夜里几乎不发光
        vec3 cloudSun = mix(vec3(1.0, 0.55, 0.28), vec3(1.0, 0.97, 0.90),
                            smoothstep(0.0, 0.55, sunY));
        cloudSun *= 0.18 + 0.82 * max(dayLight, 0.06);
        vec3 cloudAmb = mix(vec3(0.05, 0.07, 0.14), vec3(0.52, 0.60, 0.74),
                            smoothstep(-0.1, 0.4, sunY));

        float cloudTrans = 1.0;
        vec3 cloudCol;
#if CLOUD_STYLE == 0
        // 平面云：每像素只采一次噪声，镜头怎么动都不闪
        cloudCol = ssCloudFlat(worldDir, cameraPosition, sunDirW,
                               frameTimeCounter, cloudSun, cloudAmb, cloudTrans);
#else
        cloudCol = ssVolumetricClouds(worldDir, cameraPosition, sunDirW,
                                      frameTimeCounter, cloudSun, cloudAmb, cloudTrans);
#endif
        // 正确合成：云会遮挡后面的天空和日月，而不是单纯叠加
        color = color * cloudTrans + cloudCol;
    }
#endif

    // ---------- 流星雨（低 / 中 / 高，50 游戏日一次） ----------
#ifdef SS_ENABLE_METEOR
    if (isSky && sunY < 0.05) {
        color = ssMeteor(color, uv, frameTimeCounter, ssGameDay(float(worldTime)), vec2(aspect, 1.0));
    }
#endif

    // ---------- 焦散（高配，水下） ----------
#ifdef SS_ENABLE_CAUSTICS
    if (isEyeInWater == 1 && depth < 0.9995) {
        vec3 worldPosC = mat3(gbufferModelViewInverse) * pos;
        worldPosC += vec3(cameraPosition.x, 0.0, cameraPosition.z);
        color = ssCausticsWorld(color, worldPosC, frameTimeCounter);
    }
#endif

    // ---------- 泛光（高配） ----------
#ifdef SS_ENABLE_BLOOM
    color += ssBloom(colortex0, uv, texel, 0.82) * 0.28;
#endif

    // ---------- 色调映射 / 滤镜 / 玩家滑块 ----------
#ifndef SS_NO_POST
    color = ssToneMap(color);
    color = ssApplyFilter(color);
    color = ssUserAdjust(color);
#endif
    color += ssDither(gl_FragCoord.xy, frameTimeCounter);

    gl_FragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
