// Inward ruler notches, staggered targeting brackets and slow perimeter scan.
float ticks = 1.0 - smoothstep(0.6, 1.3, abs(frac((p.x + p.y) / 24.0) - 0.5) * 24.0);
ink = stroke(edge - 8, 0.35) * 0.60;
ink = max(ink, ticks * step(9, edge) * (1.0 - step(14, edge)) * 0.65);
ink = max(ink, max(segment(q,float2(7,28),float2(7,7)),segment(q,float2(7,7),float2(28,7))) * corner);
float scanner = 1.0 - smoothstep(0.0, 46.0, abs(p.y - frac(Time / 24.0) * size.y));
light = scanner * stroke(q.x - 17, 0.65) * 0.65;
light = max(light, segment(q,float2(16,23),float2(23,16)) * corner * slow);
