// Weapon-rack blades: paired diagonals, intersecting bronze seals, ember runes.
ink = max(segment(q,float2(6,30),float2(27,9)),segment(q,float2(9,27),float2(30,6))) * corner;
ink = max(ink,diamond(q,float2(18,18),8) * corner * 0.70);
ink = max(ink,stroke(edge - 7.5,0.45) * 0.34);
light = max(segment(q,float2(14,23),float2(23,14)),segment(q,float2(15,14),float2(22,21))) * corner * slow;
float rune = diamond(float2(frac(p.x / 100.0) * 100.0, q.y),float2(50,13),3.0);
light = max(light,rune * (1.0 - step(24,q.y)) * 0.45);
