// Generated from frame-template.hlsl + designs/tactical.hlsl.
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
    // Inward ruler notches, staggered targeting brackets and slow perimeter scan.
float ticks = 1.0 - smoothstep(0.6, 1.3, abs(frac((p.x + p.y) / 24.0) - 0.5) * 24.0);
ink = stroke(edge - 8, 0.35) * 0.60;
ink = max(ink, ticks * step(9, edge) * (1.0 - step(14, edge)) * 0.65);
ink = max(ink, max(segment(q,float2(7,28),float2(7,7)),segment(q,float2(7,7),float2(28,7))) * corner);
float scanner = 1.0 - smoothstep(0.0, 46.0, abs(p.y - frac(Time / 24.0) * size.y));
light = scanner * stroke(q.x - 17, 0.65) * 0.65;
light = max(light, segment(q,float2(16,23),float2(23,16)) * corner * slow);

    float3 accent = float3(0.850980,0.729412,0.423529);
    float3 secondary = float3(0.650980,0.788235,0.580392);
    color.rgb = lerp(color.rgb, secondary, saturate(ink) * 0.66);
    color.rgb = lerp(color.rgb, accent, saturate(light) * 0.78);
    return color;
}
