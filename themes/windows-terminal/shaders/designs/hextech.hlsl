// Interlocking hexagonal gears and cyan power conduits.
float2 gear = q - float2(17, 17);
float angle = atan2(gear.y, gear.x) + Time * 0.035;
float tooth = 10.5 + 1.35 * smoothstep(-0.15, 0.15, cos(angle * 12.0));
ink = max(stroke(length(gear) - tooth, 0.65) * corner, ring(q, float2(17,17), 6.5) * corner);
ink = max(ink, stroke(edge - 7, 0.3) * 0.38);
light = max(diamond(q, float2(17,17), 3.5) * corner * slow, stroke(edge - 11.5, 0.2) * (0.24 + 0.13 * sin((p.x + p.y) * 0.035 - Time * 0.45)));
