// Stone niche lintel and stepped old-gold shrine etching. No paper/wood motif.
ink = max(segment(q,float2(6,31),float2(6,6)),segment(q,float2(6,6),float2(31,6))) * corner;
ink = max(ink,max(segment(q,float2(12,30),float2(12,18)),segment(q,float2(12,18),float2(18,12))) * corner);
ink = max(ink,segment(q,float2(18,12),float2(30,12)) * corner);
ink = max(ink,stroke(edge - 6,0.6) * 0.25);
light = max(ring(q,float2(20,20),4.2),segment(q,float2(20,14),float2(20,26))) * corner * slow;
light = max(light,stroke(edge - 9,0.20) * 0.16);
