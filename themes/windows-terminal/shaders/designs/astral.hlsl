// Fine constellation paths and precisely spaced celestial nodes.
ink = max(segment(q,float2(7,29),float2(14,14)),segment(q,float2(14,14),float2(29,7))) * corner;
ink = max(ink,segment(q,float2(14,14),float2(25,25)) * corner * 0.70);
ink = max(ink,stroke(edge - 7,0.16) * 0.26);
light = max(ring(q,float2(14,14),2.0),ring(q,float2(25,25),1.1)) * corner * slow;
light = max(light,diamond(q,float2(29,7),2.4) * corner * 0.55);
float node = ring(float2(frac(p.x / 143.0) * 143.0,q.y),float2(71.5,8.5),1.6);
light = max(light,node * (1.0-step(24,q.y)) * 0.35);
