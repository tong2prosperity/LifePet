#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// 「玻璃水面」着色器 —— 活动卡底部水池的折射 + 镜面高光。
// 每个落点的相位 local(0..1) 与强度 amp(0..1) 由 WaterSurface.swift 算好后传入：
// amp 对应该列的「雨量」（卡路里/运动/站立 各自的达成度），amp 越大起伏越强、
// amp=0 的列保持静止水面；local 在 Swift 端以 Double 取模，避免把大数量级时间喂进
// float32（每列周期还不同，更不能在 shader 里除时间）。

constant float kImpactFrac = 0.36;   // 前 36% 在下落，之后才触水起波
constant float kFrontSpeed = 132.0;  // 波前外扩的最大半径(像素)
constant float kWaveK      = 0.20;   // 同心波纹空间频率
constant float kDecay      = 0.010;  // 离落点越远越弱
constant float kRefractPx  = 9.0;    // 折射位移强度(像素)
constant float kNormalStr  = 1.6;    // 法线陡峭度 → 高光强度
constant float kSpecPow    = 22.0;   // 高光锐度

// 单个落点在 uv(像素) 处贡献的水面高度。
static float dropHeight(float2 uv, float2 c, float local, float amp) {
    if (amp <= 0.001 || local < kImpactFrac) return 0.0;      // 静止列 / 水滴还在下落
    float rt = (local - kImpactFrac) / (1.0 - kImpactFrac);   // 0..1 涟漪年龄
    float d  = length(uv - c);
    float front = rt * kFrontSpeed;                           // 波前半径随时间外扩
    float wave  = sin((d - front) * kWaveK);                  // 一圈圈同心波纹
    float lead  = smoothstep(front + 30.0, front - 10.0, d);  // 只在波前内侧有起伏
    float decay = exp(-d * kDecay);                           // 远处更弱
    float age   = 1.0 - rt;                                   // 整圈随年龄淡出
    return wave * lead * decay * age * amp;                   // 雨量越大，起伏越强
}

static float surface(float2 uv,
                     float2 c0, float l0, float a0,
                     float2 c1, float l1, float a1,
                     float2 c2, float l2, float a2) {
    return dropHeight(uv, c0, l0, a0)
         + dropHeight(uv, c1, l1, a1)
         + dropHeight(uv, c2, l2, a2);
}

[[ stitchable ]]
half4 waterGlass(float2 position, SwiftUI::Layer layer, float2 size,
                 float2 c0, float l0, float a0,
                 float2 c1, float l1, float a1,
                 float2 c2, float l2, float a2) {
    float eps = 1.5;
    float h  = surface(position,                  c0, l0, a0, c1, l1, a1, c2, l2, a2);
    float hx = surface(position + float2(eps, 0), c0, l0, a0, c1, l1, a1, c2, l2, a2);
    float hy = surface(position + float2(0, eps), c0, l0, a0, c1, l1, a1, c2, l2, a2);
    float2 grad = float2(hx - h, hy - h);              // 高度梯度 ≈ 水面斜率

    // 折射：沿斜率方向偏移采样底层像素（clamp 防止采到 layer 边界外的透明区）。
    float2 refr = clamp(position + grad * kRefractPx, float2(0.0), size);
    half4 color = layer.sample(refr);

    // 镜面高光：由水面法线与光向得到玻璃般的反光，仅在有水的像素上叠加。
    float3 n = normalize(float3(-grad * kNormalStr, 1.0));
    float3 L = normalize(float3(-0.35, -0.55, 0.78));
    float spec = pow(max(dot(n, L), 0.0), kSpecPow);
    color.rgb += half3(half(spec) * 0.55h * color.a);

    return color;
}
