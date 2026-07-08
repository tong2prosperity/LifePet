#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Flowing stream shader for the Water Lab page.
// The source image is sampled only inside a hand-shaped stream mask. Time is
// wrapped in Swift before reaching this shader, so all animation math stays in a
// small float range.

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

static float streamMask(float2 uv) {
    // Coordinates are normalized against the fitted image rect.
    float d = 10.0;
    d = min(d, sdSegment(uv, float2(0.69, 0.48), float2(0.67, 0.56)) / 0.025);
    d = min(d, sdSegment(uv, float2(0.67, 0.56), float2(0.72, 0.64)) / 0.036);
    d = min(d, sdSegment(uv, float2(0.72, 0.64), float2(0.63, 0.72)) / 0.044);
    d = min(d, sdSegment(uv, float2(0.63, 0.72), float2(0.53, 0.81)) / 0.056);
    d = min(d, sdSegment(uv, float2(0.53, 0.81), float2(0.48, 0.92)) / 0.072);
    d = min(d, sdSegment(uv, float2(0.48, 0.92), float2(0.46, 1.06)) / 0.095);

    float bankNoise = valueNoise(uv * 23.0) * 0.12 - 0.06;
    return smoothstep(1.08 + bankNoise, 0.78 + bankNoise, d);
}

static float directionalWake(float2 uv, float time, float speed) {
    float centerLine = uv.y * 5.4 + uv.x * 1.2;
    float bands = sin((centerLine - time * speed) * 18.0);
    float fine = valueNoise(uv * float2(38.0, 72.0) + float2(time * speed * 1.5, -time * speed * 2.8));
    float streak = smoothstep(0.56, 1.0, bands * 0.5 + 0.5) * smoothstep(0.42, 0.96, fine);
    return streak;
}

[[ stitchable ]]
half4 flowingStream(float2 position, SwiftUI::Layer layer, float2 size,
                    float time, float speed, float rippleStrength, float highlightStrength) {
    float2 uv = position / size;
    float mask = streamMask(uv);
    half4 baseColor = layer.sample(position);
    if (mask <= 0.001) {
        return baseColor;
    }

    float flow = time * speed;
    float n1 = valueNoise(uv * float2(18.0, 34.0) + float2(flow * 0.42, -flow * 1.45));
    float n2 = valueNoise(uv * float2(42.0, 78.0) + float2(-flow * 0.25, -flow * 2.25));
    float wave = sin((uv.y * 22.0 + uv.x * 9.0 - flow * 12.0) + (n1 - 0.5) * 2.5);
    float2 refract = float2((n1 - 0.5) * 9.0 + wave * 2.5,
                            (n2 - 0.5) * 5.0 - 7.0) * rippleStrength * mask;

    half4 water = layer.sample(clamp(position + refract, float2(0.0), size));
    float wake = directionalWake(uv, time, speed);
    float sparkle = smoothstep(0.78, 1.0, n2) * smoothstep(0.70, 1.0, sin((uv.y - flow) * 95.0 + n1 * 6.0) * 0.5 + 0.5);
    float light = (wake * 0.36 + sparkle * 0.42) * highlightStrength * mask;

    half3 tint = half3(0.30h, 0.78h, 0.80h);
    water.rgb = mix(water.rgb, tint, half(0.18 * mask));
    water.rgb += half3(half(light));
    water.a = baseColor.a;

    return mix(baseColor, water, half(mask));
}

[[ stitchable ]]
half4 streamMaskPreview(float2 position, half4 color, float2 size) {
    float mask = streamMask(position / size);
    if (mask <= 0.001) {
        return color;
    }
    half3 overlay = half3(0.0h, 0.82h, 1.0h);
    color.rgb = mix(color.rgb, overlay, half(mask * 0.38));
    return color;
}
