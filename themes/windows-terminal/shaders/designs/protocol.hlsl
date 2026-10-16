// Clipped high contrast action-panel corners, moving short protocol dashes.
ink = max(segment(q,float2(7,29),float2(7,17)),segment(q,float2(7,17),float2(17,7)));
ink = max(ink,segment(q,float2(17,7),float2(29,7))) * corner;
ink = max(ink,stroke(edge - 7,0.35) * step(37,max(q.x,q.y)) * 0.30);
float dashed = step(0.72, frac((p.x + p.y - Time * 5.0) / 44.0));
light = dashed * stroke(edge - 11,0.7) * 0.65;
light = max(light,segment(q,float2(15,26),float2(26,15)) * corner * slow);
