// Painted auspicious clouds: linked rounded lobes and a warm jade ribbon.
float cloud = max(ring(q,float2(13,19),6),ring(q,float2(20,14),5));
cloud = max(cloud,ring(q,float2(26,20),4));
ink = cloud * corner;
ink = max(ink,stroke(edge - 7,0.6) * 0.45);
float wave = 11.5 + 1.2 * sin(p.x * 0.028 - Time * 0.20);
light = stroke(q.y - wave,0.4) * (1.0 - step(24,q.y)) * 0.42;
light = max(light,diamond(q,float2(19,22),2.6) * corner * slow);
