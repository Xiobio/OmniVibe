"""Render OmniVibe launch materials and deterministic icon motion exports."""
from __future__ import annotations
import hashlib
import html
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import zipfile

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/brand'
spec=importlib.util.spec_from_file_location('brand',ROOT/'tools/build-brand-icons.py')
brand=importlib.util.module_from_spec(spec);spec.loader.exec_module(brand)
FONT='C:/Windows/Fonts/msyh.ttc';BOLD='C:/Windows/Fonts/msyhbd.ttc';LATIN='C:/Windows/Fonts/seguisb.ttf'
WHITE=brand.WHITE;JADE=brand.JADE;GOLD=brand.GOLD;MUTED='#95ADA5'


def font(size,bold=False,latin=False):return ImageFont.truetype(LATIN if latin else BOLD if bold else FONT,size)


def background(w,h):
    yy,xx=np.mgrid[:h,:w].astype(np.float32)
    light=np.exp(-(((xx-w*.72)/(w*.6))**2+((yy-h*.36)/(h*.8))**2))
    a=np.array([7,17,20]);b=np.array([19,48,43])
    return Image.fromarray(np.rint(a+(b-a)*light[:,:,None]).astype(np.uint8),'RGB').convert('RGBA')


def text(draw,pos,value,size,color=WHITE,bold=False,latin=False):
    face=font(size,bold,latin);draw.text(pos,value,font=face,fill=color)
    return draw.textbbox(pos,value,font=face)


def center_text(draw,y,value,size,color=WHITE,bold=False,latin=False,width=1080):
    face=font(size,bold,latin);length=draw.textlength(value,font=face)
    draw.text(((width-length)/2,y),value,font=face,fill=color)


def pill(draw,x,y,value,size=23):
    face=font(size);w=draw.textlength(value,font=face)+36
    draw.rounded_rectangle((x,y,x+w,y+size+26),radius=10,fill='#112E28',outline='#3C6758')
    draw.text((x+18,y+8),value,font=face,fill=JADE)


def wordmark_png(dark=True):
    im=Image.new('RGBA',(2200,480));d=ImageDraw.Draw(im)
    im.alpha_composite(brand.render(480,mono=None if dark else '#21775E'),(0,0))
    text(d,(555,70),'Omni',244,WHITE if dark else '#16322D',latin=True)
    offset=d.textlength('Omni',font=font(244,latin=True))
    text(d,(555+offset,70),'Vibe',244,JADE if dark else '#21775E',latin=True)
    text(d,(571,340),'THE TASK INVENTORY FOR VIBE CODING',40,MUTED if dark else '#55726A',latin=True)
    return im


def promo():
    product=Image.open(OUT/'source/product-icon-3d.png').convert('RGBA')
    assert product.getchannel('A').getextrema()[0]==0,'Product icon needs true transparency'
    product.save(OUT/'icons/omnivibe-product-3d.png')
    product.save(OUT/'icons/omnivibe-premium.ico',sizes=[(n,n) for n in (16,24,32,48,64,128,256)])
    key=Image.open(OUT/'source/brand-keyvisual.png').convert('RGB')
    for dark in (True,False):wordmark_png(dark).save(OUT/'logos'/f'omnivibe-wordmark-{"dark" if dark else "light"}.png')
    # Cinematic launch cover; generated art has no baked-in typography.
    im=ImageOps.fit(key,(1920,1080),method=Image.Resampling.LANCZOS).convert('RGBA');d=ImageDraw.Draw(im)
    text(d,(100,135),'OMNIVIBE / COMMAND YOUR WORKSPACE',25,JADE,latin=True)
    text(d,(89,225),'OmniVibe',148,latin=True)
    text(d,(100,438),'让并行开发，',52,bold=True)
    text(d,(100,515),'像切换装备一样直觉。',52,bold=True)
    text(d,(103,648),'固定任务槽位 · 快捷切换 · 状态提醒',27,MUTED)
    pill(d,103,756,'Windows 桌面 · 多 Agent 工作台')
    text(d,(104,992),'DEVELOPMENT PREVIEW  /  BRAND KEY VISUAL',19,'#6F9084',latin=True)
    im.convert('RGB').save(OUT/'promo/launch-cover-1920x1080.png')
    # README banner uses a distinct layout, keeping the entire icon visible.
    im=background(1600,600);d=ImageDraw.Draw(im)
    im.alpha_composite(brand.render(90),(78,65))
    text(d,(190,70),'OmniVibe',77,latin=True)
    text(d,(84,222),'让并行开发，像切换装备一样直觉。',43,bold=True)
    text(d,(86,310),'固定 1–9 槽位  /  快捷切换  /  十套主题',26,MUTED)
    pill(d,87,407,'The Task Inventory for Vibe Coding',21)
    cut=product.copy();cut.thumbnail((550,550),Image.Resampling.LANCZOS);im.alpha_composite(cut,(1005,25))
    im.convert('RGB').save(OUT/'promo/readme-banner-1600x600.png')
    # Social sharing: separate square and landscape compositions.
    im=background(1280,640);d=ImageDraw.Draw(im)
    text(d,(74,97),'OmniVibe',94,latin=True)
    text(d,(80,246),'多 Agent 的任务装备核心',36,bold=True)
    text(d,(81,316),'固定位置，直觉切换。',30,MUTED)
    pill(d,83,445,'WINDOWS · VIBE CODING',21)
    cut=product.copy();cut.thumbnail((540,540),Image.Resampling.LANCZOS);im.alpha_composite(cut,(730,50))
    im.convert('RGB').save(OUT/'promo/social-card-1280x640.png')
    im=background(1080,1080);d=ImageDraw.Draw(im)
    cut=product.copy();cut.thumbnail((590,590),Image.Resampling.LANCZOS);im.alpha_composite(cut,((1080-cut.width)//2,35))
    center_text(d,637,'OmniVibe',104,latin=True)
    center_text(d,801,'让并行开发，像切换装备一样直觉。',36,bold=True)
    center_text(d,903,'固定任务槽位  ·  快捷切换  ·  十套主题',26,MUTED)
    center_text(d,1000,'WINDOWS / DEVELOPMENT PREVIEW',18,'#6F9084',latin=True)
    im.convert('RGB').save(OUT/'promo/social-square-1080.png')
    # Real native component fixture, never presented as a live user screenshot.
    im=background(1920,1080);d=ImageDraw.Draw(im)
    im.alpha_composite(brand.render(88),(82,65));text(d,(194,65),'OmniVibe',75,latin=True)
    text(d,(90,230),'把并行任务，',55,bold=True);text(d,(90,315),'装进你的装备栏。',55,bold=True)
    features=[('01','固定 1–9 槽位','按位置记住任务，切换时快速直达。'),('02','快捷键与任务轮盘','Alt + 数字，或按住 Alt+Q 指向任务。'),('03','状态提示与主题外观','接入 Agent hooks，搭配十套终端主题。')]
    for i,(n,title,detail) in enumerate(features):
        y=470+i*145;text(d,(92,y),n,32,JADE,latin=True)
        text(d,(157,y-3),title,31,bold=True);text(d,(157,y+52),detail,23,MUTED)
    shot=Image.open(ROOT/'docs/weapon-loadout/screens/radial.png').convert('RGBA')
    shot.thumbnail((850,760),Image.Resampling.LANCZOS)
    im.alpha_composite(shot,(1000,182))
    text(d,(1030,950),'原生任务轮盘 · 示例任务演示',22,MUTED)
    im.convert('RGB').save(OUT/'promo/product-features-1920x1080.png')
    print(json.dumps({'promoImages':5,'wordmarkPng':2,'premiumIcon':True}),flush=True)


def motion():
    frames=[]
    for i in range(96):frames.append(brand.render(512,tile=True,phase=i/96))
    # APNG retains edge transparency; GIF is composited onto a stable dark field.
    frames[0].save(OUT/'motion/omnivibe-loop.apng',save_all=True,append_images=frames[1:],duration=50,loop=0,disposal=0,blend=0)
    palette_source=Image.new('RGB',(512*4,512*4),brand.INK)
    for i in range(16):
        frame=frames[i*6];tile=Image.new('RGB',frame.size,brand.INK);tile.paste(frame,mask=frame.getchannel('A'));palette_source.paste(tile,((i%4)*512,(i//4)*512))
    palette=palette_source.quantize(colors=224,method=Image.Quantize.MEDIANCUT)
    gifs=[]
    for frame in frames:
        bg=Image.new('RGB',frame.size,brand.INK);bg.paste(frame,mask=frame.getchannel('A'))
        gifs.append(bg.quantize(palette=palette,dither=Image.Dither.NONE))
    gifs[0].save(OUT/'motion/omnivibe-loop.gif',save_all=True,append_images=gifs[1:],duration=50,loop=0,disposal=1,optimize=True)
    ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
    video=OUT/'motion/omnivibe-loop-1024.mp4'
    process=subprocess.Popen([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1024x1024','-r','30','-i','-','-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],stdin=subprocess.PIPE,stderr=subprocess.PIPE)
    for i in range(144):
        frame=brand.render(1024,tile=True,phase=i/144);bg=Image.new('RGB',(1024,1024),brand.INK);bg.paste(frame,mask=frame.getchannel('A'));process.stdin.write(bg.tobytes())
    process.stdin.close();error=process.stderr.read();code=process.wait()
    if code:raise RuntimeError(error.decode(errors='replace'))
    check=Image.open(OUT/'motion/omnivibe-loop.gif');assert check.n_frames==96
    hashes=set()
    for i in range(check.n_frames):check.seek(i);hashes.add(hashlib.sha256(check.convert('RGB').tobytes()).hexdigest())
    assert len(hashes)==96,'Frozen icon animation'
    apng=Image.open(OUT/'motion/omnivibe-loop.apng');assert apng.n_frames==96 and apng.getpixel((0,0))[3]==0
    # Decoder validates the entire MP4, not just its file extension.
    subprocess.run([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    reader=imageio_ffmpeg.read_frames(str(video));metadata=next(reader);reader.close()
    assert tuple(metadata['size'])==(1024,1024) and metadata['fps']==30 and abs(metadata['duration']-4.8)<.05
    report=dict(passed=True,fixedSlotCount=9,icoSizes=sorted(Image.open(OUT/'icons/omnivibe.ico').ico.sizes()),
                gif=dict(frames=96,uniqueDecodedFrames=len(hashes),durationMs=4800),
                apng=dict(frames=apng.n_frames,transparentCorners=True),
                mp4=dict(size=metadata['size'],fps=metadata['fps'],durationSeconds=metadata['duration'],decoded=True))
    (OUT/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    storyboard=Image.new('RGB',(1600,360),brand.INK);d=ImageDraw.Draw(storyboard)
    text(d,(28,12),'固定槽位，光在流动。 / 4.8s seamless loop',25)
    for i in range(6):
        frame=frames[i*16].resize((235,235),Image.Resampling.LANCZOS);storyboard.paste(frame,(20+i*263,78),frame)
        text(d,(95+i*263,315),f'{i*.8:.1f}s',18,MUTED)
    storyboard.save(OUT/'motion/storyboard.png')
    print(json.dumps({'motionFormats':['SVG','GIF','APNG','MP4'],'durationSeconds':4.8,'gifUniqueFrames':len(hashes),'mp4Decoded':True}),flush=True)


def overview():
    board=Image.new('RGB',(1920,1680),brand.INK);d=ImageDraw.Draw(board)
    text(d,(55,28),'OmniVibe / Brand & Launch Kit',58,latin=True)
    text(d,(59,112),'九槽指令环 · Windows 图标 · 产品视觉 · 图标动效 · 发布素材',25,MUTED)
    for file,xy,size in [('icons/omnivibe-app-1024.png',(60,195),(350,350)),('icons/omnivibe-product-3d.png',(490,180),(400,400)),('logos/omnivibe-white-1024.png',(1020,210),(290,290)),('logos/omnivibe-ink-1024.png',(1470,210),(290,290))]:
        pic=Image.open(OUT/file).convert('RGBA');pic.thumbnail(size,Image.Resampling.LANCZOS)
        if 'ink-' in file:d.rounded_rectangle((1410,180,1840,565),radius=25,fill='#E6ECE7')
        board.paste(pic,xy,pic)
    for x,label in ((65,'Windows / 平面图标'),(505,'产品图标 / 透明立体版'),(1020,'单色 / 深色背景'),(1450,'单色 / 浅色背景')):text(d,(x,586),label,23,MUTED)
    for file,xy in [('promo/launch-cover-1920x1080.png',(55,672)),('promo/product-features-1920x1080.png',(990,672))]:
        pic=Image.open(OUT/file);pic.thumbnail((870,490),Image.Resampling.LANCZOS);board.paste(pic,xy)
    pic=Image.open(OUT/'promo/readme-banner-1600x600.png');pic.thumbnail((1200,450),Image.Resampling.LANCZOS);board.paste(pic,(55,1200))
    text(d,(1330,1240),'4.8 秒图标循环',31,bold=True)
    text(d,(1330,1310),'SVG / GIF / APNG / MP4',23,JADE)
    text(d,(1330,1380),'可编辑源图与透明资源',23,MUTED)
    text(d,(1330,1450),'发布图与品牌使用说明',23,MUTED)
    board.save(OUT/'brand-overview.png')


def gallery():
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>OmniVibe · 品牌与宣传素材</title><style>:root{color-scheme:dark}*{box-sizing:border-box}body{margin:0;background:#091719;color:#ecf4ee;font:16px/1.7 system-ui,"Microsoft YaHei UI",sans-serif}main{max-width:1440px;margin:auto;padding:48px 24px}h1{font-size:42px;line-height:1.2}h2{font-size:26px}p{color:#95ada5}a{color:#8bf5cf}nav{display:flex;gap:22px;flex-wrap:wrap}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}article{background:#102521;border:1px solid #29483e;border-radius:20px;padding:24px;margin:20px 0}img,video{display:block;width:100%;height:auto;border-radius:12px}.icon{max-width:300px;margin:0 auto}.checker{background:repeating-conic-gradient(#20332f 0% 25%,#152723 0% 50%) 0/24px 24px;border-radius:12px}header{margin-bottom:44px}.wide{margin:36px 0}.light{background:#e6ece7}.hint{font-size:13px}</style><main><header><p>OMNIVIBE / BRAND & LAUNCH KIT</p><h1>九槽指令环。</h1><p>固定的任务位置，直觉的终端切换。墨黑、玉青与暖金构成独立于各套皮肤的产品识别。</p><nav><a href="OmniVibe-brand-kit.zip" download>下载整套素材 ZIP</a><a href="README.md">规格与使用说明</a><a href="brand-overview.png">素材总览图</a><a href="source/brand-keyvisual.prompt.md">imagegen 主视觉提示词</a></nav></header><div class="grid"><article><h2>桌面图标</h2><img class="icon" src="icons/omnivibe-app-512.png" alt="OmniVibe桌面图标"><nav><a href="icons/omnivibe.ico" download>Windows ICO</a><a href="logos/omnivibe-app.svg">SVG</a></nav></article><article><h2>产品图标</h2><div class="checker"><img class="icon" src="icons/omnivibe-product-3d.png" alt="透明立体产品图标"></div><nav><a href="icons/omnivibe-product-3d.png" download>透明 PNG</a><a href="icons/omnivibe-premium.ico" download>立体 ICO</a></nav></article><article><h2>图标动画</h2><img class="icon" src="motion/omnivibe-loop.svg" alt="固定槽位间流动的图标光效"><nav><a href="motion/omnivibe-loop.gif">GIF</a><a href="motion/omnivibe-loop.apng">透明 APNG</a><a href="motion/omnivibe-loop.svg">SVG</a><a href="motion/omnivibe-loop-1024.mp4">MP4</a></nav><p class="hint">4.8 秒无声循环；SVG 支持减少动态效果偏好。</p></article></div><section class="wide"><h2>发布主视觉 · 1920×1080</h2><a href="promo/launch-cover-1920x1080.png"><img src="promo/launch-cover-1920x1080.png" alt="OmniVibe发布主视觉"></a><p>品牌概念主视觉，非产品截图。</p></section><section class="wide"><h2>README 横幅 · 1600×600</h2><img src="promo/readme-banner-1600x600.png" alt="README横幅"></section><section class="wide"><h2>功能宣传图 · 1920×1080</h2><img src="promo/product-features-1920x1080.png" alt="功能宣传图"><p>右侧为项目原生轮盘组件的示例任务演示。</p></section><div class="grid"><article><h2>社交分享横图</h2><img src="promo/social-card-1280x640.png" alt="1280x640分享图"></article><article><h2>方形发布图</h2><img src="promo/social-square-1080.png" alt="1080方形发布图"></article></div><section class="wide"><h2>动画视频</h2><video controls loop muted playsinline preload="metadata" poster="icons/omnivibe-app-512.png" style="max-width:600px"><source src="motion/omnivibe-loop-1024.mp4" type="video/mp4"></video></section></main></html>'''
    (OUT/'index.html').write_text(page,encoding='utf-8')


def manifest():
    files=[]
    for path in sorted(OUT.rglob('*')):
        if path.is_file() and path.suffix!='.zip' and path.name not in ('manifest.json','validation.json'):
            item=dict(path=path.relative_to(OUT).as_posix(),bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
            if path.suffix.lower() in ('.png','.gif','.apng','.ico'):
                im=Image.open(path);item.update(width=im.width,height=im.height,mode=im.mode)
            files.append(item)
    (OUT/'manifest.json').write_text(json.dumps({'product':'OmniVibe','version':1,'files':files},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with zipfile.ZipFile(OUT/'OmniVibe-brand-kit.zip','w',zipfile.ZIP_DEFLATED,compresslevel=6) as bundle:
        for path in sorted(OUT.rglob('*')):
            if path.is_file() and path.suffix!='.zip':bundle.write(path,'OmniVibe-brand-kit/'+path.relative_to(OUT).as_posix())
    print(json.dumps({'files':len(files),'zipBytes':(OUT/'OmniVibe-brand-kit.zip').stat().st_size,'output':str(OUT)}))


if __name__=='__main__':
    promo();motion();overview();gallery();manifest()
