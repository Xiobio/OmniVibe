// Generated from frame-template.hlsl + designs/formation.hlsl.
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
    // Rounded preparation tiles, checkerboard bays and a restrained orbiting unit.
float2 tile = max(abs(q - float2(17,17)) - float2(7,7),0);
ink = stroke(length(tile) - 3,0.45) * corner;
ink = max(ink,stroke(edge - 7,0.3) * 0.35);
float bays = step(0.56,frac(p.x / 32.0)) * step(11,q.y) * (1.0 - step(15,q.y));
ink = max(ink,bays * 0.30);
light = ring(q,float2(17,17),3.0) * corner * slow;
float2 unit = float2(17 + cos(Time * 0.15) * 8,17 + sin(Time * 0.15) * 8);
light = max(light,(1.0 - smoothstep(0.4,1.7,length(q-unit))) * corner * 0.60);

    float3 accent = float3(0.941176,0.807843,0.533333);
    float3 secondary = float3(0.737255,0.662745,0.937255);
    color.rgb = lerp(color.rgb, secondary, saturate(ink) * 0.66);
    color.rgb = lerp(color.rgb, accent, saturate(light) * 0.78);
    return color;
}
