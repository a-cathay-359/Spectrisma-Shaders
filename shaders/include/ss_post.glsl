// ============================================================
// Spectrisma Shaders v1.1 - 屏幕空间后处理库
// SSAO / GodRays / 去星点 / 流星雨 / 正圆日月 / 焦散 / 水下折射 / FXAA
// ============================================================
#ifndef SS_POST_GLSL
#define SS_POST_GLSL

#include "/include/ss_utils.glsl"

vec3 ssReconstructView(vec2 uv, float depth, mat4 projInv) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 v = projInv * ndc;
    return v.xyz / v.w;
}

// ---------------- SSAO ----------------
// 深度图里值越小 = 越靠近相机。遮挡物必须是"比当前像素更近"的邻居。
// 旧版条件写反了（把更远的邻居算成遮挡），导致山体前面的地面被大面积压黑。
float ssSSAO(vec2 uv, float depth, vec3 pos, vec3 normal, sampler2D depthtex0, mat4 projInv, vec2 texel) {
#ifdef SS_ENABLE_SSAO
    if (depth >= 0.9995) {
        return 1.0;
    }
    // 只在近处算接触阴影，远处交给雾
    if (length(pos) > 48.0) {
        return 1.0;
    }

    float occ = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = (float(i) + 0.5) * 0.78539816;
        vec2 suv = uv + vec2(cos(a), sin(a)) * texel * 4.5;
        float sd = texture2D(depthtex0, suv).r;

        // 邻居更远 → 不是遮挡物，跳过
        if (sd >= depth) {
            continue;
        }
        vec3 sp = ssReconstructView(suv, sd, projInv);
        vec3 d = sp - pos;
        float len = length(d);
        // 只认 0.6 格以内的接触阴影。原来给到 1.2 格，
        // 等于把每个方块的台阶边都描了一圈黑线，看起来像开了描边
        if (len < 0.02 || len > 0.6) {
            continue;
        }
        // 邻居必须明显"离开表面平面"才算遮挡。原来阈值 0.15 太松，
        // 稍微不平的邻居都会被当成遮挡物，方块棱角全被加深
        float nd = abs(dot(normal, d / len));
        if (nd > 0.55) {
            occ += clamp(1.0 - len / 0.6, 0.0, 1.0);
        }
    }
    return clamp(1.0 - occ / 8.0 * 0.45, 0.0, 1.0);
#else
    return 1.0;
#endif
}

// ---------------- 水面 SSR（高配） ----------------
// 只在"确认是水面"的像素上跑：调用方已经用 depthtex1 判定过
// depth < depth1（水面在半透明通道，比它背后的地形近），
// 所以这条长程拷贝路径不可能落到草地/树叶上 —— 之前那版全屏 SSR
// 才是把远处地形色糊到地面的元凶。
// 每一步都要做深度一致性校验，撞到东西就停；没撞到就原样返回，不留痕迹。
// 返回 vec4：rgb = 反射色，w = 1 表示确实撞到东西
vec4 ssWaterSSR(vec2 uv, vec3 viewPos, vec3 reflW,
                sampler2D sceneTex, sampler2D depthTex,
                mat4 proj, mat3 mvi, vec2 texel) {
#ifdef SS_ENABLE_WATER_SSR
    mat3 mv = transpose(mvi);

    float t = 0.35;
    for (int i = 0; i < 20; i++) {
        t += 0.35 + float(i) * 0.09;
        if (t > 72.0) break;

        vec3 p = mvi * viewPos + reflW * t;      // 相机相对的世界坐标
        vec4 c = proj * vec4(mv * p, 1.0);
        if (c.w <= 0.0) break;
        vec2 ruv = c.xy / c.w * 0.5 + 0.5;
        if (ruv.x < 0.02 || ruv.x > 0.98 || ruv.y < 0.02 || ruv.y > 0.98) break;

        float rz = c.z / c.w * 0.5 + 0.5;
        float sd = texture2D(depthTex, ruv).r;

        // 打中天空：反射就是那片天空
        if (sd >= 0.99995) {
            return vec4(texture2D(sceneTex, ruv).rgb, 1.0);
        }
        // 场景像素比射线更近 → 射线撞上了它；厚度限制避免穿墙
        if (rz - sd > 0.0 && rz - sd < 0.004) {
            return vec4(texture2D(sceneTex, ruv).rgb, 1.0);
        }
    }
    return vec4(0.0);
#else
    return vec4(0.0);
#endif
}

// ---------------- 泛光（高配） ----------------
// 两圈共 12 采样：近圈抓亮部边缘，远圈把光扩散开。
// colortex0 是 8bit，超过 1.0 的部分本来就被裁掉了，所以阈值取 0.82 就够。
vec3 ssBloom(sampler2D tex, vec2 uv, vec2 texel, float threshold) {
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 6; i++) {
        float a = float(i) * 1.0471976;
        vec3 c0 = texture2D(tex, uv + vec2(cos(a), sin(a)) * (texel * 7.0)).rgb;
        vec3 c1 = texture2D(tex, uv + vec2(cos(a + 0.5236), sin(a + 0.5236)) * (texel * 20.0)).rgb;
        acc += max(c0 - threshold, vec3(0.0)) * 0.6;
        acc += max(c1 - threshold, vec3(0.0)) * 0.4;
    }
    return acc / 6.0;
}

// ---------------- 水下焦散（世界坐标） ----------------
// 光斑必须钉在世界里，否则镜头一动整片焦散就跟着漂
vec3 ssCausticsWorld(vec3 color, vec3 wpos, float t) {
#ifdef SS_ENABLE_CAUSTICS
    vec2 p = wpos.xz * 0.9;
    float a = ssNoise2(p + vec2(t * 0.42, t * 0.27));
    float b = ssNoise2(p * 1.9 - vec2(t * 0.31, t * 0.48));
    float c = pow(clamp(a * b * 2.6, 0.0, 1.0), 3.4);
    // 深浅不影响强度：深水衰减交给雾和水体本色
    color *= 1.0 + c * 1.5;
#endif
    return color;
}

// ---------------- GodRays ----------------
vec3 ssGodRays(vec2 uv, vec2 sunUV, float sunVisible, sampler2D depthtex0, vec3 sunColor) {
#ifdef SS_ENABLE_GODRAYS
    float illum = 0.0;
    float decay = 1.0;
    vec2 delta = (sunUV - uv) * (1.0 / 12.0);
    // 每像素抖动起点：12 个粗采样沿太阳射线排布，不抖动会看到一层层
    // 横向台阶，看起来就像从太阳甩出来的细条纹
    vec2 p = uv + delta * ssHash2(gl_FragCoord.xy);
    for (int i = 0; i < 12; i++) {
        p += delta;
        float d = texture2D(depthtex0, p).r;
        // 只在真正的天空像素上累加；云层深度接近远平面但不是 1.0，
        // 云面的碎 alpha 深度会被 GodRays 采样成横向条纹
        float skyWeight = smoothstep(0.99995, 1.0, d);
        illum += skyWeight * decay;
        decay *= 0.90;
    }
    return sunColor * illum * 0.022 * sunVisible;
#else
    return vec3(0.0);
#endif
}

// ---------------- 去星点（丐版） ----------------
vec3 ssRemoveStars(vec3 color, vec2 uv, vec2 texel, sampler2D sceneTex) {
#ifdef SS_NO_STARS
    vec3 avg = (texture2D(sceneTex, uv + vec2(texel.x, 0.0)).rgb +
                texture2D(sceneTex, uv - vec2(texel.x, 0.0)).rgb +
                texture2D(sceneTex, uv + vec2(0.0, texel.y)).rgb +
                texture2D(sceneTex, uv - vec2(0.0, texel.y)).rgb) * 0.25;
    if (ssLuma(color) > ssLuma(avg) * 1.6 + 0.02) {
        return avg;
    }
    return color;
#else
    return color;
#endif
}

// ---------------- 流星雨（低/中/高） ----------------
vec3 ssMeteor(vec3 color, vec2 uv, float t, float day, vec2 aspectScale) {
#ifdef SS_ENABLE_METEOR
    float trigger = ssHash1(day * 7.31 + 3.71);
    if (trigger > 1.0 / SS_METEOR_DAYS) {
        return color;
    }
    vec2 dir = normalize(vec2(0.9, 0.45));
    for (int i = 0; i < 3; i++) {
        float s = ssHash1(day + float(i) * 13.73 + 0.5);
        float life = fract(t * 0.06 + s);
        vec2 head0 = vec2(ssHash1(s + 1.7) * 0.9 - 0.1, ssHash1(s + 3.1) * 0.5 + 0.15);
        vec2 head = head0 + dir * (life * 0.75);
        vec2 d = (uv - head) * aspectScale;
        float along = dot(d, dir);
        float across = dot(d, vec2(-dir.y, dir.x));
        float tail = exp(-abs(across) * 300.0) * smoothstep(-0.30, 0.0, along) * smoothstep(0.02, -0.02, along + 0.30);
        float core = exp(-dot(d, d) * 900.0);
        float fade = sin(clamp(life, 0.0, 1.0) * 3.14159);
        color += vec3(1.0, 0.93, 0.80) * (tail * 1.1 + core) * fade;
    }
    return color;
#else
    return color;
#endif
}

// ---------------- 正圆日月（高配） ----------------
// 用"局部背景色 + 圆形遮罩"的方式把方形日月裁成圆

// ---------------- 焦散（高配，水下） ----------------
vec3 ssCaustics(vec3 color, vec2 uv, float t) {
#ifdef SS_ENABLE_CAUSTICS
    vec2 p = uv * 9.0;
    float a = ssNoise2(p + vec2(t * 0.30, t * 0.19));
    float b = ssNoise2(p * 1.7 - vec2(t * 0.23, -t * 0.17));
    float c = pow(clamp(a * b, 0.0, 1.0), 3.0) * 5.0;
    return color * (1.0 + c * 0.30);
#else
    return color;
#endif
}

// ---------------- 水下折射（高配） ----------------
vec2 ssRefractUV(vec2 uv, float t) {
#ifdef SS_ENABLE_REFRACTION
    vec2 o = vec2(sin(uv.y * 40.0 + t * 1.6), cos(uv.x * 33.0 + t * 1.3)) * 0.0016;
    return uv + o;
#else
    return uv;
#endif
}

// ---------------- FXAA（高配） ----------------
vec3 ssFXAA(sampler2D tex, vec2 uv, vec2 texel, float lumaM) {
#ifdef SS_ENABLE_FXAA
    float lumaNW = ssLuma(texture2D(tex, uv + vec2(-1.0, -1.0) * texel).rgb);
    float lumaNE = ssLuma(texture2D(tex, uv + vec2(1.0, -1.0) * texel).rgb);
    float lumaSW = ssLuma(texture2D(tex, uv + vec2(-1.0, 1.0) * texel).rgb);
    float lumaSE = ssLuma(texture2D(tex, uv + vec2(1.0, 1.0) * texel).rgb);

    float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    if (lumaMax - lumaMin < 0.02) {
        return texture2D(tex, uv).rgb;
    }

    vec2 dir = vec2(-((lumaNW + lumaNE) - (lumaSW + lumaSE)),
                    ((lumaNW + lumaSW) - (lumaNE + lumaSE)));
    float reduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * 0.03, 0.001);
    float rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
    dir = clamp(dir * rcp, vec2(-8.0), vec2(8.0)) * texel;

    vec3 rgbA = 0.5 * (texture2D(tex, uv + dir * (1.0 / 3.0 - 0.5)).rgb +
                       texture2D(tex, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 rgbB = rgbA * 0.5 + 0.25 * (texture2D(tex, uv + dir * -0.5).rgb +
                                     texture2D(tex, uv + dir * 0.5).rgb);
    float lumaB = ssLuma(rgbB);
    if (lumaB < lumaMin || lumaB > lumaMax) {
        return rgbA;
    }
    return rgbB;
#else
    return texture2D(tex, uv).rgb;
#endif
}

#endif
