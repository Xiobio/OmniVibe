// Generated from frame-template.hlsl + designs/protocol.hlsl.
// Original OmniVibe edge ornament. Central glyph texture is returned verbatim.
// No texture loops, noise grids, frame buffers, text distortion or flashing.
Texture2D shaderTexture : register(t0);
SamplerState samplerState : register(s0);
cbuffer PixelShaderSettings : register(b0)
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
};
float stroke(float distance, float thickness)
{
    return 1.0 - smoothstep(thickness, thickness + 0.65, abs(distance));
}
float segment(float2 samplePosition, float2 a, float2 b)
{
    float2 delta = b - a;
    float t = saturate(dot(samplePosition - a, delta) / max(dot(delta, delta), 0.001));
    return stroke(length(samplePosition - a - t * delta), 0.45);
}
float ring(float2 samplePosition, float2 center, float radius)
{
    return stroke(length(samplePosition - center) - radius, 0.45);
}
float diamond(float2 samplePosition, float2 center, float radius)
{
    return stroke(abs(samplePosition.x - center.x) + abs(samplePosition.y - center.y) - radius, 0.45);
}
float4 main(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 color = shaderTexture.Sample(samplerState, tex);
    float2 size = Resolution / max(Scale, 0.5);
    float2 p = tex * size;
    float2 q = min(p, size - p);
    float edge = min(q.x, q.y);
    // Settings reserve 36x32 DIPs. Decoration stops at 24 DIPs on every edge,
    // leaving an additional 8+ DIPs before any terminal glyph can be drawn.
    if (edge > 24.0) return color;
    // Richer art is confined to the empty rim. At the readable center the image
    // stays at its calibrated 12%; this boost never crosses the glyph boundary.
    float artBoost = lerp(3.25, 1.0, smoothstep(5.0, 24.0, edge));
    color.rgb = saturate(Background.rgb + (color.rgb - Background.rgb) * artBoost);
    float ink = 0.0;
    float light = 0.0;
    float slow = 0.70 + 0.12 * sin(Time * 0.4);
    float corner = 1.0 - smoothstep(30.0, 40.0, max(q.x, q.y));
    // Clipped high contrast action-panel corners, moving short protocol dashes.
ink = max(segment(q,float2(7,29),float2(7,17)),segment(q,float2(7,17),float2(17,7)));
ink = max(ink,segment(q,float2(17,7),float2(29,7))) * corner;
ink = max(ink,stroke(edge - 7,0.35) * step(37,max(q.x,q.y)) * 0.30);
float dashed = step(0.72, frac((p.x + p.y - Time * 5.0) / 44.0));
light = dashed * stroke(edge - 11,0.7) * 0.65;
light = max(light,segment(q,float2(15,26),float2(26,15)) * corner * slow);

    float3 accent = float3(1.000000,0.549020,0.556863);
    float3 secondary = float3(0.458824,0.878431,0.831373);
    color.rgb = lerp(color.rgb, secondary, saturate(ink) * 0.66);
    color.rgb = lerp(color.rgb, accent, saturate(light) * 0.78);
    return color;
}
