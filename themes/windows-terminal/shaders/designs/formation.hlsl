// Rounded preparation tiles, checkerboard bays and a restrained orbiting unit.
float2 tile = max(abs(q - float2(17,17)) - float2(7,7),0);
ink = stroke(length(tile) - 3,0.45) * corner;
ink = max(ink,stroke(edge - 7,0.3) * 0.35);
float bays = step(0.56,frac(p.x / 32.0)) * step(11,q.y) * (1.0 - step(15,q.y));
ink = max(ink,bays * 0.30);
light = ring(q,float2(17,17),3.0) * corner * slow;
float2 unit = float2(17 + cos(Time * 0.15) * 8,17 + sin(Time * 0.15) * 8);
light = max(light,(1.0 - smoothstep(0.4,1.7,length(q-unit))) * corner * 0.60);
