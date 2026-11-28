// ============================================================
// Spectrisma Shaders v1.3 - 大气 / 天空 / 体积云
//
// 云层是真体积云：从相机世界坐标出发，对 y∈[178,222] 的云层
// slab 做 raymarch。云固定在世界里，不会跟着镜头平移。
// ============================================================
#ifndef SS_ATMOSPHERE_GLSL
#define SS_ATMOSPHERE_GLSL

#include "/include/ss_utils.glsl"

// 原版天空色（Iris 提供，已按昼夜 / 天气算好）与月亮相位
uniform vec3 skyColor;
uniform int moonPhase;

// 把 view 空间方向投影到屏幕 UV；不可见时返回 x = -10
vec2 ssProjectToScreen(vec3 viewDir, mat4 proj) {
    vec4 c = proj * vec4(viewDir, 1.0);
    if (c.w <= 0.0) {
        return vec2(-10.0);
    }
    return c.xy / c.w * 0.5 + 0.5;
}

vec3 ssSkyGradient(vec3 viewDir, vec3 horizonColor, vec3 zenithColor, vec3 sunDir, vec3 sunColor) {
    float up = clamp(viewDir.y, 0.0, 1.0);
    vec3 col = mix(horizonColor, zenithColor, pow(up, 0.55));
    float sunAmount = max(dot(viewDir, sunDir), 0.0);
    col += sunColor * pow(sunAmount, 24.0) * 0.35;
    col += sunColor * pow(sunAmount, 4.0) * 0.06;
    return col;
}

// ---------------- 体积云（中 / 高配） ----------------
#ifdef SS_ENABLE_CLOUDS

// 云密度：横向 FBM 叠出云团形状，再用高度做上下软包络
// 只用两层噪声，控制每像素开销
float ssCloudDensity(vec3 wp, float t) {
    // 漂移必须同向、而且要慢。原来第二层写的是 -drift*1.7（反向漂移），
    // 两层一正一反互相推，云就在原地"翻搅"，看上去就是乱动
    vec2 drift = vec2(t * 0.0100, t * 0.0044);

    vec2 q1 = wp.xz * 0.0072 + drift;
    vec2 q2 = wp.xz * 0.0240 + drift * 1.35;

    float shape = ssFbm2(q1) * 0.72 + ssFbm2(q2) * 0.28;

    // 竖直包络：底部略平、顶部蓬松
    float h = clamp((wp.y - SS_CLOUD_BOTTOM) / (SS_CLOUD_TOP - SS_CLOUD_BOTTOM), 0.0, 1.0);
    float env = smoothstep(0.0, 0.26, h) * smoothstep(1.0, 0.52, h);

    float d = shape * env;
#if CLOUDS == 2
    // 浓密：阈值低，云铺得满
    return clamp((d - 0.40) * 2.6, 0.0, 1.0);
#else
    // 轻薄：阈值抬高，只留零散云团，天空透气
    return clamp((d - 0.56) * 3.0, 0.0, 1.0);
#endif
}

// 单次散射近似：往太阳方向再采一次密度，越厚越暗
float ssCloudLight(vec3 wp, vec3 sunDir, float t) {
    vec3 towardSun = wp + sunDir * 26.0;
    float shadowDensity = ssCloudDensity(towardSun, t);
    return clamp(1.0 - shadowDensity * 1.9, 0.0, 1.0);
}

vec3 ssVolumetricClouds(vec3 worldDir, vec3 camPos, vec3 sunDir, float t,
                        vec3 sunColor, vec3 ambientColor, out float transmittance) {
    transmittance = 1.0;
    // 只处理朝上的视线；接近地平线时淡出，避免出现一条硬边
    if (worldDir.y < 0.006) {
        return vec3(0.0);
    }
    float horizonFade = smoothstep(0.006, 0.075, worldDir.y);

    // ---- 1. 与云层 slab 求交 ----
    float tBottom = (SS_CLOUD_BOTTOM - camPos.y) / worldDir.y;
    float tTop    = (SS_CLOUD_TOP    - camPos.y) / worldDir.y;
    float tNear = max(min(tBottom, tTop), 0.0);
    float tFar  = max(max(tBottom, tTop), 0.0);

    if (tFar <= tNear) {
        return vec3(0.0);
    }
    // 太远的云步长会变粗，容易出摩尔纹，索性在 1400 格处淡出
    float marchEnd = min(tFar, tNear + 1400.0);

#ifdef SS_CLOUDS_HQ
    const int STEPS = 12;
#else
    const int STEPS = 8;
#endif

    float span = marchEnd - tNear;
    float stepLen = span / float(STEPS);
    // 抖动起点，避免出现层状条纹
    vec3 p = camPos + worldDir * (tNear + stepLen * ssHash2(gl_FragCoord.xy));

    vec3 acc = vec3(0.0);
    float trans = 1.0;

    for (int i = 0; i < STEPS; i++) {
        float dens = ssCloudDensity(p, t);
        if (dens > 0.003) {
            // 吸收系数按每单位距离算，远近距离观感一致
            // 轻薄档再压一档不透明度，避免糊成一片
#if CLOUDS == 2
            float ext = dens * stepLen * 0.040;
#else
            float ext = dens * stepLen * 0.026;
#endif
            float alpha = 1.0 - exp(-ext);

            // 很薄的边缘不参与光照计算，省一大笔开销
            float lit = 1.0;
            if (dens > 0.02) {
                lit = ssCloudLight(p, sunDir, t);
            }

            // 远处淡出：步长变粗后细节会糊成噪点，提前消隐
            float camDist = tNear + float(i) * stepLen;
            alpha *= (1.0 - smoothstep(900.0, 1400.0, camDist));

            // 受光面偏暖白，背光面偏冷灰
            vec3 col = sunColor * (0.10 + 0.90 * lit) + ambientColor * (0.30 + 0.25 * lit);

            // 边缘提亮：密度薄的边缘散射更强，出现银边
            col += sunColor * pow(1.0 - dens, 6.0) * 0.9 * lit;

            acc += col * alpha * trans;
            trans *= (1.0 - alpha);
            if (trans < 0.03) {
                break;
            }
        }
        p += worldDir * stepLen;
    }

    // 整层在接近地平线时整体淡出
    acc *= horizonFade;
    trans = mix(1.0, trans, horizonFade);
    transmittance = trans;
    return acc;
}
#endif


// ---------------- 平面云（Krpmon 同款思路） ----------------
// 不做 raymarch：视线与云层平面求交，在交点处只采一次噪声。
// 因为每像素只有一个确定值、没有抖动、没有可见的步进分层，
// 所以镜头怎么动云都不会闪、不会爬行 —— 这正是体积云"乱动"的根源。
// 云层有真实高度（CL_ALT），所以飞上去能真的穿过去，不是永远在天边。
vec3 ssCloudFlat(vec3 worldDir, vec3 camPos, vec3 sunDir, float t,
                 vec3 sunColor, vec3 ambientColor, out float transmittance) {
    transmittance = 1.0;
    // 云是一层真实存在高度的平面（MC 里的云在 y≈192），做真正的射线-平面求交，
    // 所以飞上去能真的穿过去，不是永远在天边。
    const float CL_ALT = 190.0;
    if (abs(worldDir.y) < 1.0e-3) {
        return vec3(0.0);
    }
    float dz = CL_ALT - camPos.y;
    float tHit = dz / worldDir.y;
    if (tHit <= 0.5 || tHit > 1100.0) {
        return vec3(0.0);
    }
    float nearFade = smoothstep(0.0, 3.0, tHit);
    float farFade  = 1.0 - smoothstep(700.0, 1100.0, tHit);

    // 交点用相机相对坐标，再叠相机水平位置（取模 256 格）把图案钉在世界里
    vec2 hit = worldDir.xz * tHit;
    hit += vec2(mod(camPos.x, 256.0), mod(camPos.z, 256.0));
    hit += vec2(t * 0.0035, t * 0.0016);

    vec2 q = hit * 0.020;

#if CLOUDS == 2
    float amount  = 0.08;
    float opacity = 0.30;
#else
    float amount  = -0.05;
    float opacity = 0.20;
#endif

    // 主密度场：软阈值塑形（Krpmon get_clouds_flat 的写法），
    // 低噪声直接抹掉、高噪声保留，中间一段平滑过渡，边缘不会硬切
    float dens = ssFbm2(q);
    dens *= smoothstep(0.0, 0.4 - opacity, dens - 0.55 + amount);

    // 细节层在大团之间抠出缝隙，避免所有云粘成一整片
    float detail = ssFbm2(q * 2.7 + 31.0);
    dens = max(dens - (detail - 0.5) * 0.22, 0.0);

    dens *= nearFade * farFade;
    if (dens < 0.004) {
        return vec3(0.0);
    }

    const float DENSITY = 1.5;
    transmittance = exp(-dens * DENSITY);

    // 吸收阴影层：朝太阳方向偏移再采一次，pow4 压出暗洞，
    // 云团内部才有明暗层次，而不是一团均匀的白
    float absor = ssFbm2(q + sunDir.xz * 0.30);
    absor = pow(clamp(absor * 2.0, 0.0, 1.0), 4.0);

    // Henyey-Greenstein 前向散射：对着太阳方向有一圈亮边（银边）
    float vdotl = dot(worldDir, sunDir);
    float g = 0.7;
    float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * vdotl, 1.5);
    hg = clamp(hg, 0.25, 4.0);    // 迎着太阳那侧的前向散射不能炸白

    vec3 base = ambientColor * 0.55;
    vec3 lit  = sunColor * hg * exp(-absor * DENSITY);
    vec3 col  = base + lit;

    // 云顶受光的亮边
    col += sunColor * pow(1.0 - dens, 5.0) * 0.30;

    return col * dens * DENSITY;
}

// ---------------- 正圆日月 ----------------
// 形状与数值照 ComplementaryUnbound r5.9.3 的最高配（SUN_MOON_STYLE 3）：
//   sunSizeFactor1 = 0.9983 → 圆盘角半径 3.34°
//   亮度沿 cos 线性衰减（不是硬边 + 临边昏暗），边缘很柔
//   叠 GetHorizonFactor：天体越贴近地平线越淡，落到地平线以下直接不画
//   月亮按 moonPhase 挖出月相，亏月与盈月换边
//
// 擦除圈的取色策略（两次踩坑后定稿）：
//   1) 优先从擦除圈外沿采"确认是天空"的像素 —— 这样能把那片天空的
//      渐变、夕照、星星原样保下来，视觉上最无缝。
//   2) 采不到（地平线附近圈外全是地形）时，改用解析天空色
//      ssSkyGradient(fogColor → skyColor)。skyColor 是 Iris 给的原版天空色
//      （已含昼夜与天气），地平线附近它和 fogColor 几乎一致，所以也不会脱色。
//   关键：两条路径都不会把地形色抄进来，所以放射条纹在结构上不可能再出现；
//   而第 2 条保证了"一定有颜色可用"，原版方块日月在任何时间都会被盖住。
//
// 天空像素判定。门限必须是 0.99995 而不是 0.9995：
// 归一化深度 ≈ 1 - near/z，near=0.05 时 0.9995 只对应 100 格外，
// 也就是说 100 格以外的所有地形都会被误判成"天空"。
// 0.99995 对应约 1000 格外，远超渲染距离，才能真正只圈住天空。
bool ssSkyPixel(sampler2D depthTex, sampler2D depthTex1, vec2 p) {
    float z0 = texture2D(depthTex, p).r;
    if (z0 < 0.99995) return false;
    float z1 = texture2D(depthTex1, p).r;
    if (z1 <= 1.0e-6) return true;      // 加载器未绑定 depthtex1 → 退回 z0
    return z1 >= 0.99995;
}

// 照 Complementary GetHorizonFactor（SUN_MOON_HORIZON 开启的那一支）：
// 天体高度 +0.10 以上为 1，-0.10 以下为 0，中间平滑过渡。
float ssHorizonFactor(float elev) {
    float h = clamp((elev + 0.10) * 10.0, 0.0, 1.0);
    h = h * h;
    return h * h * (3.0 - 2.0 * h);
}

// phase：-1 = 太阳（不挖月相）；0..7 = 月亮相位（0 满月 / 4 新月）
vec3 ssCelestialDisc(vec3 color, vec2 uv, vec3 viewDir, vec3 lightDir, vec3 dirW,
                     vec3 sunDirW, vec3 horizonCol, vec3 glowColor,
                     sampler2D sceneTex, sampler2D depthTex, sampler2D depthTex1,
                     vec2 texel, mat4 proj,
                     vec3 discColor, float cosEdge, float eraseAngle,
                     float haloAmount, int phase) {
#ifdef SS_ENABLE_ROUND_SUN
    // 天体自己在地平线以下：不画也不擦。这条同时实现
    // "白天只处理太阳、夜里只处理月亮"，交界时两个都贴地平线、两个都处理。
    float elev = dirW.y;
    if (elev < -0.098) return color;
    float hf = ssHorizonFactor(elev);

    float cosA = dot(normalize(viewDir), normalize(lightDir));
    if (cosA <= cos(eraseAngle * 1.65)) {
        return color;                                   // 离得远，完全不碰
    }

    vec3 d = normalize(lightDir);
    vec2 cUV = ssProjectToScreen(d, proj);
    if (cUV.x < -0.5 || cUV.x > 1.5 || cUV.y < -0.5 || cUV.y > 1.5) return color;

    // 擦除圈的屏幕半径：把方向绕垂直轴转一个角度再投影
    vec3 axis = normalize(cross(d, abs(d.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
    vec3 edgeDir = normalize(d * cos(eraseAngle) + axis * sin(eraseAngle));
    float rPx = length((ssProjectToScreen(edgeDir, proj) - cUV) / texel);
    if (rPx < 2.0) return color;

    float pd = length((uv - cUV) / texel) / rPx;
    if (pd > 1.22) return color;

    // 圆盘自身的屏幕半径（用来把像素坐标归一化到圆盘坐标系）
    vec3 discEdge = normalize(d * cosEdge + axis * sin(max(cosEdge, 1.0e-4)));
    float rDisc = length((ssProjectToScreen(discEdge, proj) - cUV) / texel);

    // ---- 取色：先采真天空，失败就解析算 ----
    float rOut = rPx * 1.20;
    vec3 sky = vec3(0.0);
    float valid = 0.0;

    vec2 awayV = uv - cUV;
    float awayL = length(awayV);
    vec2 uvA = (awayL > 1.0e-6) ? cUV + awayV / awayL * (rOut * texel)
                               : cUV + vec2(0.0, rOut * texel);
    uvA = clamp(uvA, vec2(0.002), vec2(0.998));
    if (ssSkyPixel(depthTex, depthTex1, uvA)) {
        sky = texture2D(sceneTex, uvA).rgb;
        valid = 1.0;
    }

    if (valid < 1.0) {
        for (int i = 0; i < 8; i++) {
            float a = float(i) * 0.7853982;
            vec2 ps = clamp(cUV + vec2(cos(a), sin(a)) * (rOut * texel),
                            vec2(0.002), vec2(0.998));
            if (!ssSkyPixel(depthTex, depthTex1, ps)) continue;
            sky = min(sky, texture2D(sceneTex, ps).rgb);
            valid += 1.0;
        }
    }

    if (valid < 1.0) {
        // 解析天空：地平线附近的还原度最高（fogColor 本来就是那里的颜色）
        vec3 zen = max(skyColor, horizonCol * 0.35);
        sky = ssSkyGradient(normalize(dirW), horizonCol, zen, sunDirW, glowColor);
    }

    // ---- 圆盘本体：cos 线性衰减，中心最亮、边缘归零 ----
    float u = clamp((cosA - cosEdge) / max(1.0 - cosEdge, 1.0e-7), 0.0, 1.0);
    float halo = pow(clamp(cosA, 0.0, 1.0), 260.0) * haloAmount;

    // ---- 月相：在圆盘坐标系里用椭圆明暗界线切出月牙 ----
    float phaseMask = 1.0;
    if (phase >= 0 && phase <= 7) {
        // 亮面比例：0 满月 → 4 新月 → 7 盈凸
        float lit = 1.0 - (phase <= 4 ? float(phase) : float(8 - phase)) * 0.25;
        if (lit < 0.99) {
            vec2 sp = (uv - cUV) / (texel * max(rDisc, 1.0));
            float sgn = (phase > 4) ? -1.0 : 1.0;          // 亏月 / 盈月换边
            float kk = 1.0 - 2.0 * lit;                    // -1 全亮 … +1 全暗
            float edge = kk * sqrt(max(1.0 - min(sp.y * sp.y, 1.0), 0.0));
            phaseMask = smoothstep(0.0, 0.16, sp.x * sgn - edge);
            phaseMask = mix(1.0, phaseMask, smoothstep(0.02, 0.20, 1.0 - lit));
        }
    }

    vec3 body = discColor * u * hf * phaseMask;
    vec3 target = sky + body + discColor * halo * hf;

    // 向外羽化：正好盖住原版方块日月，外加一圈渐变过渡，接缝看不见
    float m = smoothstep(1.18, 0.96, pd);
    return mix(color, target, m);
#else
    return color;
#endif
}

#endif
