// Layered metal equipment rails, inset rivets and warm forged highlights.
ink = max(stroke(edge - 6,0.9),stroke(edge - 11,0.4) * 0.55);
ink = max(ink, ring(q,float2(18,18),3.4) * corner);
float bevel = max(segment(q,float2(7,28),float2(28,7)),segment(q,float2(12,28),float2(28,12))) * corner;
light = bevel * 0.65;
light = max(light,ring(q,float2(18,18),0.8) * corner * slow);
light = max(light,stroke(edge - 8,0.2) * (0.12 + 0.08 * sin(p.x * 0.018 + p.y * 0.012 - Time * 0.3)));
