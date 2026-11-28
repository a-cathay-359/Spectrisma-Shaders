// ============================================================
// Spectrisma Shaders v1.4 - 阴影：畸变贴图 + 硬件深度比较 + 法线偏移
//
// 方案来源：Krpmon Shader（bias 做法回溯到 Complementary）
// 三个关键点，缺一个都会留下锯齿：
//  1. 阴影畸变：把阴影贴图中心的采样密度放大，玩家附近清晰，
//     所以 1024/2048 就能顶住，不需要靠堆分辨率
//  2. shadowHardwareFiltering：sampler2DShadow 一次采样自带 4 点
//     双线性深度比较，比手动 smoothstep 干净
//  3. 世界空间法线偏移 bias：按距离和入射角自动给偏移，
//     消除自阴影噪点，不用固定大 bias 去硬扛
// ============================================================
#ifndef SS_SHADOW_GLSL
#define SS_SHADOW_GLSL

#include "/include/ss_settings.glsl"
#include "/include/ss_utils.glsl"

// 开启后 shadowtex0/1 变成 sampler2DShadow（深度比较型采样器）
const bool shadowHardwareFiltering = true;

uniform sampler2DShadow shadowtex0;
uniform sampler2DShadow shadowtex1;

uniform mat4 shadowProjection;
uniform mat4 shadowModelView;
uniform mat4 gbufferModelViewInverse;

// ---- 与 shadow.vsh 必须完全一致，改一处要同步另一处 ----
const float ssShadowMapBias = 1.0 - 25.6 / shadowDistance;

vec3 ssShadowDistort(vec3 pos) {
    float factor = length(pos.xy) * ssShadowMapBias + (1.0 - ssShadowMapBias);
    return vec3(pos.xy / factor, pos.z * 0.2);
}

// 交错梯度噪声：给采样核一个每像素不同的旋转角，把残差打散成极细噪点
float ssIgn(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// 均匀圆盘螺旋采样（黄金角），比方阵网格更不容易出条纹
vec2 ssDiskSample(int i, int total, float rot, float radius) {
    float a = rot + float(i) * 2.39996323;
    float r = sqrt((float(i) + 0.5) / float(total)) * radius;
    return vec2(cos(a), sin(a)) * r;
}

// 世界空间法线偏移：距离越远偏移越大，正对光偏移越小，斜对光偏移越大
vec3 ssShadowBias(vec3 playerPos, vec3 worldNormal, float ndotl) {
    float distBias = pow(dot(playerPos, playerPos), 0.75);
    distBias = 0.12 + 0.0008 * distBias;
    return worldNormal * distBias * (2.0 - 0.95 * max(ndotl, 0.0));
}

// 采样点数与软化半径（单位：畸变后贴图的 texel）
#ifdef SS_ENABLE_PCSS
    #define SS_SHADOW_TAPS   13
    #define SS_SHADOW_RAD    3.0
#elif defined(SS_ENABLE_PCF)
    #define SS_SHADOW_TAPS    9
    #define SS_SHADOW_RAD    2.0
#else
    #define SS_SHADOW_TAPS    5
    #define SS_SHADOW_RAD    1.2
#endif

// 返回 1 = 全亮，0 = 全暗
// 只需要视线空间位置；法线、bias、投影都在这里自己算
float ssShadow(vec3 viewPos) {
#ifdef SS_ENABLE_SHADOW

    // ---- 1. 相机相对的世界坐标 ----
    vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos;

    // ---- 2. 几何法线（方块面法线，与参考包一致）----
    vec3 vnRaw = cross(dFdx(viewPos), dFdy(viewPos));
    float vnLen = length(vnRaw);
    vec3 viewNormal = vnLen > 1.0e-5 ? vnRaw / vnLen : normalize(-viewPos);
    vec3 worldNormal = mat3(gbufferModelViewInverse) * viewNormal;
    vec3 lightDirW = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    float ndotl = dot(worldNormal, lightDirW);

    // ---- 3. 加偏移后投影到阴影 NDC ----
    // playerPos 是"相机相对"坐标，补上相机位移才是世界坐标
    vec3 worldPos = playerPos + gbufferModelViewInverse[3].xyz;
    vec3 biased = worldPos + ssShadowBias(playerPos, worldNormal, ndotl);

    vec4 homo = shadowProjection * (shadowModelView * vec4(biased, 1.0));
    vec3 ndc = homo.xyz / homo.w;

    // ---- 4. 畸变后转到 UV ----
    vec3 uvz = ssShadowDistort(ndc) * 0.5 + 0.5;

    // 出界视为全亮
    if (uvz.x < 0.0 || uvz.x > 1.0 || uvz.y < 0.0 || uvz.y > 1.0 || uvz.z > 1.0) {
        return 1.0;
    }

    // ---- 5. 采样 ----
    float vis;
#if SS_SHADOW_TAPS > 5
    // 中/高配：螺旋盘 + 每像素旋转
    float rot = ssIgn(gl_FragCoord.xy) * 6.2831853;
    float invRes = 1.0 / float(shadowMapResolution);
    float sum = 0.0;
    for (int i = 0; i < SS_SHADOW_TAPS; i++) {
        vec2 o = ssDiskSample(i, SS_SHADOW_TAPS, rot, SS_SHADOW_RAD) * invRes;
        sum += texture(shadowtex1, vec3(uvz.xy + o, uvz.z));
    }
    vis = sum / float(SS_SHADOW_TAPS);
#else
    // 低配：参考包的 5 点交叉模糊，权重 0.25 + 4×0.1875
    vec2 r = vec2(SS_SHADOW_RAD) / float(shadowMapResolution);
    float c = texture(shadowtex1, uvz) * 0.25;
    c += texture(shadowtex1, vec3(uvz.xy + vec2(-0.33 * r.x,  r.y), uvz.z)) * 0.1875;
    c += texture(shadowtex1, vec3(uvz.xy + vec2( 0.33 * r.x, -r.y), uvz.z)) * 0.1875;
    c += texture(shadowtex1, vec3(uvz.xy + vec2( r.x,  0.33 * r.y), uvz.z)) * 0.1875;
    c += texture(shadowtex1, vec3(uvz.xy + vec2(-r.x, -0.33 * r.y), uvz.z)) * 0.1875;
    vis = c;
#endif

    // ---- 6. 远端淡出，避免阴影在一个圆圈上突然断掉 ----
    float fadeStart = shadowDistance * 0.82;
    vis = mix(vis, 1.0, smoothstep(fadeStart, shadowDistance, length(playerPos)));

    return clamp(vis, 0.0, 1.0);

#else
    return 1.0;
#endif
}

#endif
