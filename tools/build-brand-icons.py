"""OmniVibe's editable nine-slot command-ring identity and native icon exports."""
from __future__ import annotations
import json
import math
from pathlib import Path
from xml.etree import ElementTree
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/brand'
INK='#091719'; JADE='#8BF5CF'; GOLD='#D4BB83'; WHITE='#ECF4EE'
GLYPH=[(181,169),(211,169),(289,243),(289,268),(211,342),(181,342),(181,309),(238,256),(181,202)]
CURSOR=[(295,312),(353,312),(353,342),(295,342)]


def rgb(value):return tuple(int(value[i:i+2],16) for i in (1,3,5))
def mix(a,b,t):return tuple(round(x*(1-t)+y*t) for x,y in zip(a,b))
def point(radius,angle):return 256+radius*math.cos(math.radians(angle)),256+radius*math.sin(math.radians(angle))


def sector(index):
    start=-106+index*40;end=start+31
    return [point(216,start+j*(end-start)/24) for j in range(25)]+[point(178,end-j*(end-start)/24) for j in range(25)]


def svg_path(index):
    start=-106+index*40;end=start+31
    a,b,c,d=point(216,start),point(216,end),point(178,end),point(178,start)
    return f'M{a[0]:.3f},{a[1]:.3f} A216,216 0 0 1 {b[0]:.3f},{b[1]:.3f} L{c[0]:.3f},{c[1]:.3f} A178,178 0 0 0 {d[0]:.3f},{d[1]:.3f}Z'


def colors(index,phase=None,mono=None):
    if mono:return mono
    if phase is None:return GOLD if index==2 else (JADE if index in (0,1,3) else '#438B7F')
    distance=(index/9-phase+.5)%1-.5
    intensity=math.exp(-(distance/.16)**2)
    value=mix(rgb('#32675E'),rgb(GOLD if index==2 else JADE),.15+.85*intensity)
    return '#%02X%02X%02X'%value


def render(size=1024,tile=False,phase=None,mono=None):
    scale=max(1,math.ceil(1024/size)) if size<512 else 1
    n=size*scale;factor=n/512
    im=Image.new('RGBA',(n,n));d=ImageDraw.Draw(im)
    if tile:
        yy,xx=np.mgrid[:n,:n].astype(np.float32)/n
        light=np.clip(1-np.hypot(xx-.3,yy-.15),0,1)*.14
        bg=np.asarray(rgb(INK));dest=np.asarray(rgb('#36625C'))
        arr=np.rint(bg+(dest-bg)*light[:,:,None]).astype(np.uint8)
        flat=Image.fromarray(arr,'RGB').convert('RGBA')
        mask=Image.new('L',(n,n));md=ImageDraw.Draw(mask)
        md.rounded_rectangle((n*.025,n*.025,n*.975,n*.975),radius=n*.225,fill=255)
        im.paste(flat,(0,0),mask)
        d=ImageDraw.Draw(im)
        d.rounded_rectangle((n*.026,n*.026,n*.974,n*.974),radius=n*.223,outline='#31534C',width=max(1,round(n*.002)))
    for i in range(9):
        d.polygon([(x*factor,y*factor) for x,y in sector(i)],fill=colors(i,phase,mono))
    glyph_color=mono or WHITE
    d.polygon([(x*factor,y*factor) for x,y in GLYPH],fill=glyph_color)
    d.polygon([(x*factor,y*factor) for x,y in CURSOR],fill=mono or JADE)
    if scale>1:im=im.resize((size,size),Image.Resampling.LANCZOS)
    return im


def svg(tile=False,mono=None,animated=False):
    items=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-labelledby="title desc">',
           '<title id="title">OmniVibe · 九槽指令环</title><desc id="desc">九个固定任务槽围绕终端指令符号，玉青与暖金区分焦点。</desc>']
    if animated:
        styles=['.slot{animation-duration:4.8s;animation-timing-function:linear;animation-iteration-count:infinite}']
        for i in range(9):
            steps=''.join(f'{s/24*100:.4f}%{{fill:{colors(i,phase=s/24)}}}' for s in range(25))
            styles.append(f'.s{i}{{animation-name:slot{i}}}@keyframes slot{i}{{{steps}}}')
        styles.append('@media(prefers-reduced-motion:reduce){.slot{animation:none!important}}')
        items.append('<style>'+''.join(styles)+'</style>')
    if tile:items.append('<rect x="13" y="13" width="486" height="486" rx="115" fill="#091719" stroke="#31534C"/>')
    for i in range(9):
        animation=f' class="slot s{i}"' if animated else ''
        items.append(f'<path d="{svg_path(i)}" fill="{colors(i,mono=mono)}"{animation}/>')
    for points,color in ((GLYPH,mono or WHITE),(CURSOR,mono or JADE)):
        items.append('<polygon points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="{color}"/>')
    return ''.join(items)+'</svg>'


def wordmark(dark=True):
    fg=WHITE if dark else '#16322D';sub='#94B2A7' if dark else '#55726A'
    mark=svg(mono=None if dark else '#21775E').replace('<svg ', '<svg x="0" y="0" width="240" height="240" ',1)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1100 240" role="img" aria-label="OmniVibe">{mark}<text x="278" y="140" fill="{fg}" font-family="Bahnschrift,Segoe UI,sans-serif" font-size="122" font-weight="600" letter-spacing="-4">Omni<tspan fill="{"#8BF5CF" if dark else "#21775E"}">Vibe</tspan></text><text x="284" y="192" fill="{sub}" font-family="Segoe UI,sans-serif" font-size="24" letter-spacing="4">THE TASK INVENTORY FOR VIBE CODING</text></svg>'


def main():
    for folder in ('icons','logos','motion','promo','source'):(OUT/folder).mkdir(parents=True,exist_ok=True)
    for filename,value in {'omnivibe-mark.svg':svg(),'omnivibe-app.svg':svg(tile=True),'omnivibe-white.svg':svg(mono='#FFFFFF'),'omnivibe-ink.svg':svg(mono='#16322D')}.items():
        ElementTree.fromstring(value);(OUT/'logos'/filename).write_text(value,encoding='utf-8')
    for dark in (True,False):
        value=wordmark(dark);ElementTree.fromstring(value)
        (OUT/'logos'/f'omnivibe-wordmark-{"dark" if dark else "light"}.svg').write_text(value,encoding='utf-8')
    (OUT/'motion'/'omnivibe-loop.svg').write_text(svg(tile=True,animated=True),encoding='utf-8')
    sizes=(16,20,24,32,40,48,64,128,256,512,1024)
    for size in sizes:
        render(size).save(OUT/'icons'/f'omnivibe-mark-{size}.png')
        render(size,tile=True).save(OUT/'icons'/f'omnivibe-app-{size}.png')
    render(1024,tile=True).save(OUT/'icons'/'omnivibe.ico',sizes=[(n,n) for n in sizes if n<=256])
    render(64,tile=True).save(OUT/'icons'/'favicon.ico',sizes=[(16,16),(32,32),(48,48),(64,64)])
    render(1024,mono='#FFFFFF').save(OUT/'logos'/'omnivibe-white-1024.png')
    render(1024,mono='#16322D').save(OUT/'logos'/'omnivibe-ink-1024.png')
    # Honest size proofs against both Windows-style dark and light surfaces.
    proof=Image.new('RGB',(1440,640),'#0B191B');d=ImageDraw.Draw(proof)
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
    d.text((40,26),'OmniVibe · 九槽指令环 / Windows 图标尺寸检查',font=font,fill=WHITE)
    for j,bg in enumerate(('#0B191B','#E6ECE7')):
        d.rounded_rectangle((30,100+j*250,1410,320+j*250),radius=18,fill=bg)
        x=60
        for size in (16,24,32,48,64,128):
            icon=render(size,tile=True);proof.paste(icon,(x,155+j*250),icon)
            d.text((x,277+j*250),f'{size}px',font=ImageFont.truetype('C:/Windows/Fonts/seguisb.ttf',16),fill=WHITE if j==0 else '#16322D')
            x+=max(125,size+65)
    proof.save(OUT/'icon-size-proof.png')
    ico=Image.open(OUT/'icons'/'omnivibe.ico')
    assert ico.ico.sizes()=={(n,n) for n in sizes if n<=256}
    assert render(1024).getpixel((0,0))[3]==0
    (OUT/'source'/'palette.json').write_text(json.dumps({'name':'Nine-slot Command Ring','ink':INK,'jade':JADE,'gold':GOLD,'white':WHITE,'slots':9},indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'icons':len(sizes)*2,'icoSizes':sorted(ico.ico.sizes()),'output':str(OUT)}))


if __name__=='__main__':main()
