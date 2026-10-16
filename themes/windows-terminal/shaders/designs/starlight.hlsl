// Skill-badge aureole: concentric arcs and a soft four-samplePosition star at each corner.
float2 star = q - float2(18,18);
ink = max(ring(q,float2(18,18),11),ring(q,float2(18,18),8.2) * 0.40) * corner;
ink = max(ink,stroke(edge - 7,0.3) * 0.35);
float rays = min(abs(star.x),abs(star.y));
light = (1.0 - smoothstep(0.0,1.0,rays)) * (1.0 - smoothstep(0.0,7.0,length(star))) * corner * slow;
light = max(light,diamond(q,float2(18,18),4.5) * corner * 0.65);
light = max(light,stroke(edge - 11,0.2) * 0.16);
