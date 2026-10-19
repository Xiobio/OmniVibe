"""A quieter, compact OmniVibe identity: precise folded shapes, no loading ring."""
from __future__ import annotations
import argparse
import hashlib
import html
import json
import math
from pathlib import Path
import subprocess
import zipfile
from xml.etree import ElementTree

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/brand/v2'
PAPER='#F7F6F2';INK='#292831';MUTED='#77757E';LILAC='#CFC7E2';ACCENT='#8774B0';LINE='#E3E0E7'
FONT='C:/Windows/Fonts/msyh.ttc';BOLD='C:/Windows/Fonts/msyhbd.ttc';LATIN='C:/Windows/Fonts/seguisb.ttf'

# The two main strokes have equal optical weight; the narrow facet is a fold,
# not a separate outline, ring, symbol or tiny decoration.
SHAPES={
 'fold':[
   ([(138,154),(211,154),(283,291),(246,363)],'main'),
   ([(301,154),(374,154),(265,366),(227,293)],'main'),
   ([(211,154),(283,291),(247,360),(245,286)],'facet')
 ],
 'orbit':[
   ([(256,123),(371,190),(371,322),(256,389),(141,322),(141,190),(187,217),(187,296),(256,336),(325,296),(325,217),(256,177),(208,205),(163,179)],'main'),
   ([(210,232),(252,208),(294,280),(331,215),(371,239),(294,372)],'facet')
 ],
 'pages':[
   ([(132,184),(246,132),(246,314),(132,366)],'main'),
   ([(267,132),(381,184),(381,366),(267,314)],'main'),
   ([(246,132),(267,132),(267,314),(256,329),(246,314)],'facet')
 ]
}


def rgb(value):return tuple(int(value[i:i+2],16) for i in (1,3,5))
def mix(a,b,t):return tuple(round(x*(1-t)+y*t) for x,y in zip(rgb(a),rgb(b)))
def face(size,bold=False,latin=False):return ImageFont.truetype(LATIN if latin else BOLD if bold else FONT,size)


def mark(size=512,tile=False,dark=False,mono=False,phase=None,kind='fold'):
    factor=max(2,math.ceil(768/size));n=size*factor;s=n/512
    im=Image.new('RGBA',(n,n));d=ImageDraw.Draw(im)
    if tile:
        d.rounded_rectangle((46*s,46*s,466*s,466*s),radius=100*s,fill=INK if dark else LILAC)
    color=PAPER if dark else INK
    facet=('#A798C7' if dark else '#9280B4') if not mono else color
    if phase is not None:
        # A restrained change on one small facet, rather than spinning/loading.
        amount=.5-.5*math.cos(phase*math.tau)
        facet=mix('#9280B4','#A293C0',amount)
    for points,role in SHAPES[kind]:
        d.polygon([(x*s,y*s) for x,y in points],fill=facet if role=='facet' else color)
    return im.resize((size,size),Image.Resampling.LANCZOS)


def svg(tile=False,dark=False,mono=False,animated=False,kind='fold'):
    color=PAPER if dark else INK;facet=color if mono else '#A798C7' if dark else '#9280B4'
    out=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" role="img" aria-label="OmniVibe · 折光">']
    if animated:out.append('<style>.facet{animation:breathe 4.8s ease-in-out infinite}@keyframes breathe{0%,100%{fill:#9280B4}50%{fill:#A293C0}}@media(prefers-reduced-motion:reduce){.facet{animation:none}}</style>')
    if tile:out.append(f'<rect x="46" y="46" width="420" height="420" rx="100" fill="{INK if dark else LILAC}"/>')
    for points,role in SHAPES[kind]:
        cls=' class="facet"' if role=='facet' and animated else ''
        out.append('<polygon points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="{facet if role=="facet" else color}"{cls}/>')
    return ''.join(out)+'</svg>'


def put(d,xy,label,size,fill=INK,bold=False,latin=False):
    d.text(xy,label,font=face(size,bold,latin),fill=fill)


def center(d,y,label,size,width,fill=INK,latin=False):
    f=face(size,latin=latin);w=d.textlength(label,font=f);d.text(((width-w)/2,y),label,font=f,fill=fill)


def concepts():
    OUT.mkdir(parents=True,exist_ok=True)
    im=Image.new('RGB',(1500,760),PAPER);d=ImageDraw.Draw(im)
    put(d,(70,46),'OmniVibe',42,latin=True)
    put(d,(72,111),'更小巧，更精致。',24,MUTED)
    for i,(kind,title) in enumerate((('fold','A / 折光'),('orbit','B / 交织'),('pages','C / 双页'))):
        x=66+i*490
        d.rounded_rectangle((x,203,x+412,615),radius=28,fill='#F0EDF5',outline=LINE)
        icon=mark(300,kind=kind);im.paste(icon,(x+56,235),icon)
        put(d,(x+8,650),title,22)
        for j,size in enumerate((16,24,32)):
            icon=mark(size,tile=True,kind=kind);im.paste(icon,(x+250+j*48,655),icon)
    im.save(OUT/'directions.png')
    for kind in SHAPES:
        (OUT/f'direction-{kind}.svg').write_text(svg(kind=kind),encoding='utf-8')
    print(str(OUT/'directions.png'),flush=True)


def icons():
    for name in ('icons','logos','motion','promo','source'):(OUT/name).mkdir(parents=True,exist_ok=True)
    variants={'omnivibe-mark.svg':svg(),'omnivibe-app.svg':svg(tile=True),'omnivibe-white.svg':svg(dark=True,mono=True),'omnivibe-ink.svg':svg(mono=True)}
    for name,value in variants.items():
        ElementTree.fromstring(value);(OUT/'logos'/name).write_text(value,encoding='utf-8')
    for dark in (False,True):
        variant='dark' if dark else 'light';color=PAPER if dark else INK
        symbol=svg(dark=dark).replace('<svg ','<svg x="0" y="0" width="170" height="170" ',1)
        word=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 700 170" role="img" aria-label="OmniVibe">{symbol}<text x="169" y="108" font-family="Segoe UI,sans-serif" font-size="78" font-weight="600" letter-spacing="-2" fill="{color}">OmniVibe</text></svg>'
        (OUT/'logos'/f'omnivibe-wordmark-{variant}.svg').write_text(word,encoding='utf-8')
        im=Image.new('RGBA',(1400,340));d=ImageDraw.Draw(im);m=mark(340,dark=dark);im.alpha_composite(m,(0,0));put(d,(338,73),'OmniVibe',156,color,latin=True);im.save(OUT/'logos'/f'omnivibe-wordmark-{variant}.png')
    sizes=(16,20,24,32,40,48,64,128,256,512,1024)
    for size in sizes:
        mark(size).save(OUT/'icons'/f'omnivibe-mark-{size}.png')
        mark(size,tile=True).save(OUT/'icons'/f'omnivibe-app-{size}.png')
    mark(1024,tile=True).save(OUT/'icons'/'omnivibe.ico',sizes=[(n,n) for n in sizes if n<=256])
    mark(64,tile=True).save(OUT/'icons'/'favicon.ico',sizes=[(16,16),(32,32),(48,48),(64,64)])
    mark(1024).save(OUT/'icons'/'omnivibe-product.png')
    mark(1024,dark=True,mono=True).save(OUT/'logos'/'omnivibe-white-1024.png')
    mark(1024,mono=True).save(OUT/'logos'/'omnivibe-ink-1024.png')
    (OUT/'motion'/'omnivibe-loop.svg').write_text(svg(tile=True,animated=True),encoding='utf-8')
    proof=Image.new('RGB',(1400,610),PAPER);d=ImageDraw.Draw(proof)
    put(d,(55,35),'OmniVibe / 小尺寸检查',30)
    for row,bg in enumerate((PAPER,'#292831')):
        d.rounded_rectangle((40,112+row*225,1360,310+row*225),radius=16,fill=bg)
        x=80
        for size in (16,24,32,48,64,128):
            m=mark(size,tile=True);proof.paste(m,(x,147+row*225),m)
            put(d,(x,276+row*225),f'{size}px',15,MUTED,latin=True);x+=170
    proof.save(OUT/'icon-size-proof.png')


def promo():
    # Small optical symbol, quiet typography, ample white space; no 3D props.
    im=Image.new('RGB',(1920,1080),PAPER);d=ImageDraw.Draw(im)
    m=mark(120);im.paste(m,(85,67),m);put(d,(193,99),'OmniVibe',34,latin=True)
    put(d,(117,325),'让并行开发，',70,bold=True)
    put(d,(117,428),'像切换装备一样直觉。',70,bold=True)
    put(d,(121,610),'多 Agent 的任务装备核心',29,MUTED)
    put(d,(121,851),'固定 1–9 槽位     /     快捷切换     /     十套主题',24,MUTED)
    m=mark(760);im.paste(m,(1050,115),m)
    put(d,(121,1000),'WINDOWS · DEVELOPMENT PREVIEW',17,MUTED,latin=True)
    im.save(OUT/'promo'/'launch-cover-1920x1080.png')
    im=Image.new('RGB',(1600,600),PAPER);d=ImageDraw.Draw(im)
    m=mark(110);im.paste(m,(61,47),m);put(d,(166,75),'OmniVibe',39,latin=True)
    put(d,(94,245),'让并行开发，像切换装备一样直觉。',45,bold=True)
    put(d,(97,356),'固定任务槽位 · 快捷切换 · 十套主题',24,MUTED)
    m=mark(510);im.paste(m,(1070,40),m);im.save(OUT/'promo'/'readme-banner-1600x600.png')
    im=Image.new('RGB',(1280,640),PAPER);d=ImageDraw.Draw(im)
    put(d,(82,90),'OmniVibe',65,latin=True)
    put(d,(84,257),'固定位置，直觉切换。',38,bold=True)
    put(d,(86,342),'多 Agent 的任务装备核心',24,MUTED)
    put(d,(87,550),'WINDOWS · VIBE CODING',17,MUTED,latin=True)
    m=mark(550);im.paste(m,(710,35),m);im.save(OUT/'promo'/'social-card-1280x640.png')
    im=Image.new('RGB',(1080,1080),PAPER);d=ImageDraw.Draw(im)
    m=mark(590);im.paste(m,(245,80),m)
    center(d,682,'OmniVibe',80,1080,latin=True)
    center(d,820,'让并行开发，像切换装备一样直觉。',34,1080)
    center(d,979,'WINDOWS · DEVELOPMENT PREVIEW',17,1080,MUTED,latin=True)
    im.save(OUT/'promo'/'social-square-1080.png')
    # Same real native UI fixture as v1, framed as a subordinate product detail.
    im=Image.new('RGB',(1920,1080),PAPER);d=ImageDraw.Draw(im)
    m=mark(120);im.paste(m,(72,66),m);put(d,(182,100),'OmniVibe',34,latin=True)
    put(d,(108,292),'任务各就其位。',64,bold=True)
    for i,(title,body) in enumerate((('固定槽位','1–9 号位置，记住你的工作现场。'),('直觉切换','快捷键与任务轮盘，快速进入任务。'),('可信状态','接入 Agent hooks，查看可靠的状态提醒。'))):
        y=478+i*125;put(d,(112,y),title,29,bold=True);put(d,(112,y+48),body,23,MUTED)
    shot=Image.open(ROOT/'docs/weapon-loadout/screens/radial.png').convert('RGB');shot.thumbnail((800,650),Image.Resampling.LANCZOS)
    im.paste(shot,(1000,220));put(d,(1000,910),'任务轮盘 · 示例任务演示',19,MUTED)
    im.save(OUT/'promo'/'product-features-1920x1080.png')


def motion():
    frames=[mark(512,tile=True,phase=i/96) for i in range(96)]
    frames[0].save(OUT/'motion'/'omnivibe-loop.apng',save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=0,blend=0)
    palette=Image.new('RGB',(512*4,512*4),PAPER)
    for i in range(16):
        bg=Image.new('RGB',(512,512),PAPER);bg.paste(frames[i*6],mask=frames[i*6].getchannel('A'));palette.paste(bg,((i%4)*512,(i//4)*512))
    palette=palette.quantize(colors=224,method=Image.Quantize.MEDIANCUT)
    gifs=[]
    for f in frames:
        bg=Image.new('RGB',f.size,PAPER);bg.paste(f,mask=f.getchannel('A'));gifs.append(bg.quantize(palette=palette,dither=Image.Dither.NONE))
    gifs[0].save(OUT/'motion'/'omnivibe-loop.gif',save_all=True,append_images=gifs[1:],duration=50,loop=0,disposal=1,optimize=True)
    # Direct vector motion is intentionally understated; fixed silhouette.
    ff=imageio_ffmpeg.get_ffmpeg_exe();video=OUT/'motion'/'omnivibe-loop-1024.mp4'
    p=subprocess.Popen([ff,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1024x1024','-r','30','-i','-','-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    for i in range(144):
        f=mark(1024,tile=True,phase=i/144);bg=Image.new('RGB',f.size,PAPER);bg.paste(f,mask=f.getchannel('A'));p.stdin.write(bg.tobytes())
    p.stdin.close();error=p.stderr.read();code=p.wait()
    if code:raise RuntimeError(error.decode(errors='replace'))
    subprocess.run([ff,'-v','error','-i',str(video),'-f','null','-'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    print('Motion exported',flush=True)


def package():
    preview=Image.new('RGB',(1800,1180),PAPER);d=ImageDraw.Draw(preview)
    put(d,(62,40),'OmniVibe',42,latin=True);put(d,(66,105),'折光 · 小巧，精致。',24,MUTED)
    for i,(dark,tile,label) in enumerate(((False,True,'桌面图标'),(False,False,'透明产品标记'),(True,False,'深色背景'))):
        x=65+i*575;d.rounded_rectangle((x,190,x+520,625),radius=20,fill=INK if dark else '#F0EDF5')
        m=mark(375,tile=tile,dark=dark);preview.paste(m,(x+72,195),m);put(d,(x+30,575),label,21,'#AAA7B2' if dark else MUTED)
    for file,x in (('readme-banner-1600x600.png',65),('social-card-1280x640.png',940)):
        m=Image.open(OUT/'promo'/file);m.thumbnail((790,390),Image.Resampling.LANCZOS);preview.paste(m,(x,700))
    preview.save(OUT/'brand-overview.png')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 折光</title><link rel="icon" href="icons/favicon.ico"><style>*{box-sizing:border-box}body{margin:0;background:#f7f6f2;color:#292831;font:16px/1.8 system-ui,"Microsoft YaHei UI",sans-serif}main{max-width:1200px;margin:auto;padding:64px 24px}h1{font-size:42px;letter-spacing:-1px}h2{font-size:23px}p{color:#77757e}a{color:#75609c}nav{display:flex;gap:22px;flex-wrap:wrap}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:24px}.card{border:1px solid #e3e0e7;border-radius:18px;padding:24px}.card img{width:200px;height:200px;object-fit:contain;margin:auto}.wide{margin-top:55px}img,video{display:block;max-width:100%;height:auto;border-radius:12px}.hint{font-size:13px}</style><main><header><h1>OmniVibe</h1><p>折光。更紧凑的标记，更轻的色彩，更安静的排版。</p><nav><a href="OmniVibe-brand-kit-v2.zip" download>下载新版素材</a><a href="README.md">规格与源文件</a><a href="directions.png">三种方向对照</a><a href="icon-size-proof.png">小尺寸检查</a></nav></header><section class="grid wide"><article class="card"><h2>桌面图标</h2><img src="icons/omnivibe-app-512.png" alt="折光桌面图标"><nav><a href="icons/omnivibe.ico">ICO</a><a href="logos/omnivibe-app.svg">SVG</a></nav></article><article class="card"><h2>产品标记</h2><img src="icons/omnivibe-product.png" alt="透明产品标记"><nav><a href="icons/omnivibe-product.png">透明 PNG</a><a href="logos/omnivibe-mark.svg">可编辑 SVG</a></nav></article><article class="card"><h2>轻量动效</h2><img src="motion/omnivibe-loop.svg" alt="折面轻微明暗变化"><nav><a href="motion/omnivibe-loop.gif">GIF</a><a href="motion/omnivibe-loop.apng">APNG</a><a href="motion/omnivibe-loop-1024.mp4">MP4</a></nav><p class="hint">4.8 秒循环，只有折面微光变化。</p></article></section><section class="wide"><h2>README 横幅</h2><img src="promo/readme-banner-1600x600.png" alt="新版横幅"></section><section class="wide"><h2>发布封面</h2><img src="promo/launch-cover-1920x1080.png" alt="新版发布封面"></section><section class="wide"><h2>功能介绍</h2><img src="promo/product-features-1920x1080.png" alt="功能介绍"></section><section class="grid wide"><img src="promo/social-card-1280x640.png" alt="分享横图"><img src="promo/social-square-1080.png" alt="方形分享图"></section><section class="wide"><h2>视频</h2><video controls loop muted playsinline preload="metadata" poster="icons/omnivibe-app-512.png" width="480"><source src="motion/omnivibe-loop-1024.mp4" type="video/mp4"></video></section></main></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')
    ico=Image.open(OUT/'icons'/'omnivibe.ico');assert len(ico.ico.sizes())==9
    gif=Image.open(OUT/'motion'/'omnivibe-loop.gif');apng=Image.open(OUT/'motion'/'omnivibe-loop.apng')
    assert gif.n_frames>1 and apng.n_frames>1 and mark(512).getpixel((0,0))[3]==0
    files=[]
    for path in sorted(OUT.rglob('*')):
        if path.is_file() and path.suffix!='.zip' and path.name!='manifest.json':files.append(dict(path=path.relative_to(OUT).as_posix(),bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    (OUT/'manifest.json').write_text(json.dumps(dict(version=2,files=files,gifFrames=gif.n_frames,apngFrames=apng.n_frames,smallIconSizes=sorted(ico.ico.sizes())),indent=2)+'\n',encoding='utf-8')
    with zipfile.ZipFile(OUT/'OmniVibe-brand-kit-v2.zip','w',zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.rglob('*')):
            if p.is_file() and p.suffix!='.zip':z.write(p,'OmniVibe-brand-v2/'+p.relative_to(OUT).as_posix())
    print(json.dumps(dict(output=str(OUT),files=len(files),gifFrames=gif.n_frames,zipBytes=(OUT/'OmniVibe-brand-kit-v2.zip').stat().st_size)),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--concepts-only',action='store_true');args=parser.parse_args()
    concepts()
    if not args.concepts_only:icons();promo();motion();package()
