// ============================================================
// Spectrisma Shaders v1.2 - 全局开关中心
//
// 【重要】Iris 的设置面板不是靠 shaders.properties 生成的，而是扫描
// 下面这几个 #define 以及行尾注释里的 [值清单]。
// 值清单决定选项类型与可选项，说明文字变成悬浮提示。
// shaders.properties 只负责 菜单布局 / 滑块 / 一键预设按钮。
//
// 这段与 final.fsh 顶部完全一致（Iris 会逐程序扫描选项）。
// ============================================================
#ifndef SS_SETTINGS_GLSL
#define SS_SETTINGS_GLSL

// ===== 用户选项 =====
#ifndef SS_USER_OPTIONS
#define SS_USER_OPTIONS
#define PRESET       3 // [0 1 2 3 4] 性能预设：0 发芽的马铃薯 / 1 马铃薯 / 2 低配 / 3 中配 / 4 高配
#define FILTER       0 // [0 1 2 3 4 5] 色彩滤镜：0 无滤镜 / 1 原版明艳 / 2 真实中性 / 3 真实冷 / 4 真实暖 / 5 日漫风
#define EXPOSURE   1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 3.0] 曝光
#define SATURATION 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0] 饱和度
#define CONTRAST   1.0 // [0.5 0.6 0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 1.7 1.8 1.9 2.0] 对比度
#define CLOUDS       1 // [0 1 2] 云层：0 关闭 / 1 轻薄稀疏 / 2 浓密
#define CLOUD_STYLE  0 // [0 1] 云类型：0 平面云（稳、省，轻薄成团）/ 1 体积云（立体但更贵）
#endif

// 方块 ID（Iris mc_Entity.x）。若你的整合包映射不同，改这两个即可
#define SS_ID_WATER      8.0
#define SS_ID_FLOW_LAVA  10.0
#define SS_ID_STILL_LAVA 11.0

// ---------------- 档位 0：发芽的马铃薯 ----------------
#if PRESET == 0
    #define SS_PRESET_GERMINATED
    #define SS_SOLID_WATER
    #define SS_SOLID_LAVA
    #define SS_NO_STARS
    #define SS_NO_PLANT_WIND
    #define SS_NO_SMOOTH_SHADING
    #define SS_NO_AO_PASS
    #define SS_NO_WETNESS
    #define SS_NO_ENCHANT_PULSE
    #define SS_NO_GODRAYS
    #define SS_NO_SSAO
    // 这片天上什么都不要：自定义云不开，原版方块云也 discard 掉
    #define SS_NO_VANILLA_CLOUDS
#endif

// ---------------- 档位 1：马铃薯（原版模拟） ----------------
#if PRESET == 1
    #define SS_PRESET_POTATO
    // 原版日月贴图已被本包置空，这里补一个圆盘，否则天上会一日月都没有
    #define SS_ENABLE_ROUND_SUN
#endif

// ---------------- 档位 2：低配 ----------------
#if PRESET == 2
    #define SS_PRESET_LOW
    #define SS_ENABLE_SHADOW
    #define SS_ENABLE_PCF
    #define SS_ENABLE_METEOR
    // 从 3 档下放的两项（都很便宜，但观感提升明显）
    #define SS_ENABLE_DIFFUSE      // 方块朝向光照，出体积感
    #define SS_ENABLE_ROUND_SUN    // 圆形日月 + 盖掉原版方块日月
#endif

// ---------------- 档位 3：中配 ----------------
#if PRESET == 3
    #define SS_PRESET_MEDIUM
    #define SS_ENABLE_SHADOW
    #define SS_ENABLE_PCF
    #define SS_ENABLE_METEOR
    #define SS_ENABLE_SSAO
    #define SS_ENABLE_GODRAYS
    #define SS_ENABLE_WATER_REFLECT
    #define SS_ENABLE_CLOUDS
    #define SS_NO_VANILLA_CLOUDS
    #define SS_ENABLE_DIFFUSE
    #define SS_ENABLE_ROUND_SUN
    #define SS_ENABLE_REFRACTION
    #define SS_ENABLE_CAUSTICS
    // 从 4 档下放
    #define SS_ENABLE_FXAA
    #define SS_ENABLE_BLOOM
#endif

// ---------------- 档位 4：高配 ----------------
#if PRESET >= 4
    #define SS_PRESET_HIGH
    #define SS_ENABLE_SHADOW
    #define SS_ENABLE_PCSS
    #define SS_ENABLE_METEOR
    #define SS_ENABLE_SSAO
    #define SS_ENABLE_GODRAYS
    #define SS_ENABLE_WATER_REFLECT
    #define SS_ENABLE_PBR
    #define SS_ENABLE_ACES
    #define SS_ENABLE_FXAA
    #define SS_ENABLE_CLOUDS
    #define SS_CLOUDS_HQ
    #define SS_NO_VANILLA_CLOUDS
    #define SS_ENABLE_REFRACTION
    #define SS_ENABLE_CAUSTICS
    #define SS_ENABLE_ROUND_SUN
    #define SS_ENABLE_DIFFUSE
    #define SS_ENABLE_BLOOM
    // 屏幕空间水面倒影：只在水面像素上做，见 ss_post.glsl ssWaterSSR
    #define SS_ENABLE_WATER_SSR
#endif

// PRESET == 5：闭源 RT 包专用，开源工程内不实现光追

// ---------------- 云层总开关（覆盖档位默认） ----------------
#if CLOUDS == 0
    #undef SS_ENABLE_CLOUDS
    #ifndef SS_NO_VANILLA_CLOUDS
        #define SS_NO_VANILLA_CLOUDS
    #endif
#endif

// ---------------- 滤镜 ----------------
#if FILTER == 0
    #define SS_FILTER_NONE
#endif
#if FILTER == 1
    #define SS_FILTER_VIVID
#endif
#if FILTER == 2
    #define SS_FILTER_REALISTIC
#endif
#if FILTER == 3
    #define SS_FILTER_COLD
#endif
#if FILTER == 4
    #define SS_FILTER_WARM
#endif
#if FILTER == 5
    #define SS_FILTER_ANIME
#endif

// 结构常量

// 【关键】软化半径用"阴影 UV 单位"，不是 texel 单位
// 0.0045 ≈ 阴影覆盖 128 格时的 0.5 格方块 —— 这个尺度才能肉眼看到柔边
// 之前按 texel 算（4.5 texel ≈ 0.14 格），等于没软化，所以怎么加采样都还是硬边

#define SS_METEOR_DAYS    50.0

// 云层（世界坐标 y 高度，与原版云层区间对齐）
#define SS_CLOUD_BOTTOM 178.0
#define SS_CLOUD_TOP    222.0

// 阴影贴图分辨率与覆盖距离（Iris 会扫描 const 并暴露成面板选项）
const int shadowMapResolution = 2048; // [1024 2048 4096]
const float shadowDistance = 128.0;   // [96 128 160 192]

#endif
