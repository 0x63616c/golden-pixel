#include <metal_stdlib>
using namespace metal;

struct VOut { float4 position [[position]]; float2 uv; };

vertex VOut fullscreen(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.position = float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
    o.uv = p;
    return o;
}

/// Glow at art resolution: each pixel's colour weighted by its glow byte (alpha), blurred with
/// a 9x9 tent. The base image is never touched by this.
fragment half4 glowPass(VOut in [[stage_in]], texture2d<half> base [[texture(0)]]) {
    int2 size = int2(base.get_width(), base.get_height());
    int2 c = int2(in.position.xy);
    half3 sum = 0; half wsum = 0;
    for (int dy = -4; dy <= 4; dy++) {
        for (int dx = -4; dx <= 4; dx++) {
            int2 q = clamp(c + int2(dx, dy), int2(0), size - 1);
            half4 t = base.read(uint2(q));
            half w = half(5 - abs(dx)) * half(5 - abs(dy));
            sum += t.rgb * t.a * w;
            wsum += w;
        }
    }
    return half4(sum / wsum * 2.2h, 1);
}

struct PresentUniforms { int2 origin; int scale; int glow; };

/// Final pass at an integer scale: exact texel reads, so every art pixel is a crisp N x N block
/// with no filtering and no seams, then the soft glow added on top.
fragment half4 presentPass(VOut in [[stage_in]],
                           constant PresentUniforms &u [[buffer(0)]],
                           texture2d<half> base [[texture(0)]],
                           texture2d<half> glow [[texture(1)]],
                           sampler lin [[sampler(0)]]) {
    int2 px = (int2(in.position.xy) - u.origin) / u.scale;
    int2 size = int2(base.get_width(), base.get_height());
    px = clamp(px, int2(0), size - 1);
    half3 c = base.read(uint2(px)).rgb;
    if (u.glow != 0) {
        float2 uv = (in.position.xy - float2(u.origin)) / float(u.scale) / float2(size);
        c += glow.sample(lin, uv).rgb;
    }
    return half4(min(c, half3(1)), 1);
}
