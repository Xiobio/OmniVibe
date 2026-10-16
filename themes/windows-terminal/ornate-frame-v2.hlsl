// OmniVibe: bronze cloud corners, jade inlays and a slow travelling rim light.
// The inner terminal content is returned unchanged, including its alpha channel.
Texture2D shaderTexture : register(t0);
SamplerState samplerState : register(s0);
cbuffer PixelShaderSettings : register(b0)
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
};

float stroke(float d, float thickness)
{
    return 1.0 - smoothstep(thickness, thickness + 0.8, abs(d));
}

float segment(float2 p, float2 a, float2 b)
{
    float2 v = b - a;
    float t = saturate(dot(p - a, v) / max(dot(v, v), 0.001));
    return stroke(length(p - a - t * v), 0.35);
}

float4 main(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 color = shaderTexture.Sample(samplerState, tex);
    float scale = max(Scale, 0.5);
    float2 size = Resolution / scale;
    float2 p = tex * size;
    float2 q = min(p, size - p);
    float edge = min(q.x, q.y);
    if (edge > 33.0) return color;

    float perimeter = 2.0 * (size.x + size.y);
    float along = p.x;
    if (q.x < q.y) along = p.x > size.x * 0.5 ? size.x + p.y : perimeter - p.y;
    else if (p.y > size.y * 0.5) along = size.x + size.y + size.x - p.x;
    float distanceAlong = abs(along - frac(Time / 32.0) * perimeter);
    distanceAlong = min(distanceAlong, perimeter - distanceAlong);
    float travelling = exp(-distanceAlong * distanceAlong / 14500.0);

    float frame = max(stroke(edge - 6.5, 0.35), stroke(edge - 10.5, 0.2) * 0.42);
    float bronze = frame * (0.48 + 0.30 * travelling);
    float jade = 0.0;
    if (max(q.x, q.y) < 33.0)
    {
        float ornament = segment(q, float2(7, 30), float2(7, 7));
        ornament = max(ornament, segment(q, float2(7, 7), float2(30, 7)));
        ornament = max(ornament, segment(q, float2(12, 30), float2(12, 12)));
        ornament = max(ornament, segment(q, float2(12, 12), float2(30, 12)));
        ornament = max(ornament, segment(q, float2(19, 30), float2(29, 30)));
        ornament = max(ornament, segment(q, float2(29, 30), float2(29, 19)));
        ornament = max(ornament, segment(q, float2(29, 19), float2(23, 19)));
        ornament = max(ornament, segment(q, float2(23, 19), float2(23, 24)));
        ornament = max(ornament, stroke(length(q - float2(17, 17)) - 5.5, 0.3));
        bronze = max(bronze, ornament * 0.76);
        float gem = abs(q.x - 17) + abs(q.y - 17);
        jade = (1.0 - smoothstep(2.5, 4.4, gem)) * (0.44 + 0.12 * sin(Time * 0.65));
        jade += exp(-dot(q - 17, q - 17) / 50.0) * 0.075;
    }

    float3 brassColor = float3(0.68, 0.53, 0.31) + travelling * float3(0.15, 0.13, 0.07);
    color.rgb = lerp(color.rgb, brassColor, saturate(bronze));
    color.rgb = lerp(color.rgb, float3(0.58, 0.82, 0.67), saturate(jade));

    if (p.x > size.x - 27.0)
    {
        float spark = 0.0;
        [unroll] for (int i = 0; i < 6; ++i)
        {
            float y = frac(i * 0.173 - Time * (0.006 + i * 0.0005)) * size.y;
            float x = size.x - 18.0 + 4.0 * sin(Time * 0.35 + i * 2.1);
            float2 delta = p - float2(x, y);
            spark += exp(-dot(delta, delta) / 3.3) * 0.42;
        }
        color.rgb = lerp(color.rgb, float3(0.72, 0.81, 0.56), saturate(spark));
    }
    return color;
}
