// Generated from frame-template.hlsl + designs/wonderland.hlsl.
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
    // Painted auspicious clouds: linked rounded lobes and a warm jade ribbon.
float cloud = max(ring(q,float2(13,19),6),ring(q,float2(20,14),5));
cloud = max(cloud,ring(q,float2(26,20),4));
ink = cloud * corner;
ink = max(ink,stroke(edge - 7,0.6) * 0.45);
float wave = 11.5 + 1.2 * sin(p.x * 0.028 - Time * 0.20);
light = stroke(q.y - wave,0.4) * (1.0 - step(24,q.y)) * 0.42;
light = max(light,diamond(q,float2(19,22),2.6) * corner * slow);

    float3 accent = float3(0.486275,0.349020,0.094118);
    float3 secondary = float3(0.129412,0.423529,0.466667);
    color.rgb = lerp(color.rgb, secondary, saturate(ink) * 0.66);
    color.rgb = lerp(color.rgb, accent, saturate(light) * 0.78);
    return color;
}
